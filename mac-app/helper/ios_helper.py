#!/usr/bin/env python3
"""PhoneShot 的 iOS 辅助进程。

由菜单栏 App 启动并常驻，通过 stdin/stdout 按行收发 JSON：
    → {"id": 1, "cmd": "list", "refresh": true}
    ← {"id": 1, "ok": true, "devices": [{"udid": ..., "name": ..., "devMode": true, ...}]}
    → {"id": 2, "cmd": "screenshot", "udid": "0000...", "out": "/tmp/x.png"}
    ← {"id": 2, "ok": true, "device": {...}, "ms": 420}
失败时返回 {"id": .., "ok": false, "code": "DEV_MODE_OFF", "message": "..."}。
不传 udid 时自动选择（数据线优先）。

iOS 17.4+ 用 pymobiledevice3 的用户态隧道（UserspaceRsdTunnel），无需 root；
隧道在进程内常驻复用，空闲一段时间后自动关闭。
"""

import asyncio
import json
import logging
import os
import sys
import time
from logging.handlers import RotatingFileHandler
from pathlib import Path
from typing import Any, Optional

# stdout 只留给 JSON 协议，库里任何 print 都改道到 stderr
_PROTOCOL_OUT = os.fdopen(os.dup(sys.stdout.fileno()), "w", buffering=1, encoding="utf-8")
sys.stdout = sys.stderr

LOG_DIR = Path.home() / "Library" / "Logs" / "PhoneShot"
LOG_DIR.mkdir(parents=True, exist_ok=True)
_handler = RotatingFileHandler(LOG_DIR / "ios-helper.log", maxBytes=2_000_000, backupCount=2, encoding="utf-8")
_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s"))
logging.basicConfig(level=logging.INFO, handlers=[_handler])
logging.getLogger("urllib3").setLevel(logging.WARNING)
logger = logging.getLogger("phoneshot.ios")

from pymobiledevice3 import usbmux  # noqa: E402
from pymobiledevice3.exceptions import (  # noqa: E402
    AlreadyMountedError,
    ChannelClosedError,
    ConnectionFailedToUsbmuxdError,
    ConnectionTerminatedError,
    DeveloperModeIsNotEnabledError,
    DeviceNotFoundError,
    FatalPairingError,
    InvalidHostIDError,
    InvalidServiceError,
    NoDeviceConnectedError,
    NotPairedError,
    NotTrustedError,
    PairingDialogResponsePendingError,
    PasswordRequiredError,
    RemoteXPCHandshakeTimeoutError,
    StartServiceError,
    UserDeniedPairingError,
    UserspaceTunnelUnavailableError,
)
from pymobiledevice3.lockdown import create_using_usbmux  # noqa: E402
from pymobiledevice3.remote.userspace_tunnel import UserspaceRsdTunnel  # noqa: E402
from pymobiledevice3.services.amfi import AmfiService  # noqa: E402
from pymobiledevice3.services.dvt.instruments.dvt_provider import DvtProvider  # noqa: E402
from pymobiledevice3.services.dvt.instruments.screenshot import Screenshot  # noqa: E402
from pymobiledevice3.services.mobile_image_mounter import auto_mount  # noqa: E402

IDLE_CLOSE_SECONDS = 600
TUNNEL_TIMEOUT = 25
SHOT_TIMEOUT = 20
MOUNT_TIMEOUT = 180
PAIR_TIMEOUT = 30
LIST_DEVICE_TIMEOUT = 10

MESSAGES = {
    "NO_DEVICE": "没检测到 iPhone：请用数据线连接，或确认手机与电脑在同一 Wi‑Fi 且之前用数据线信任过此电脑",
    "DEVICE_GONE": "所选的 iPhone 已断开，请重新连接或在菜单中换一台设备",
    "NOT_PAIRED": "iPhone 尚未信任此电脑：请插线、解锁手机，在弹窗中点「信任」",
    "LOCKED": "请先解锁 iPhone 再截图",
    "DEV_MODE_OFF": "iPhone 未开启开发者模式：设置 → 隐私与安全性 → 开发者模式，打开后按提示重启并确认",
    "MOUNT_FAILED": "挂载开发者镜像失败（手机重启后首次截图需要联网下载），请检查网络后重试",
    "UNSUPPORTED": "暂不支持该 iOS 版本（iOS 17.0–17.3），请升级到 iOS 17.4 或以上",
    "TIMEOUT": "连接超时：请解锁手机；如果弹出「要信任此电脑吗」请点「信任」",
    "UNKNOWN": "截图失败",
}

# 连接断开类错误：关掉隧道重建一次即可恢复
RECONNECT_ERRORS = (
    ConnectionError,
    OSError,
    asyncio.TimeoutError,
    EOFError,
    ConnectionTerminatedError,
    ChannelClosedError,
    RemoteXPCHandshakeTimeoutError,
)
# 服务启动失败：多半是开发者镜像未挂载（手机重启后会失效）
SERVICE_ERRORS = (InvalidServiceError, StartServiceError)


class ShotError(Exception):
    def __init__(self, code: str, detail: str = "") -> None:
        super().__init__(code)
        self.code = code
        self.detail = detail


def classify(e: BaseException) -> ShotError:
    if isinstance(e, ShotError):
        return e
    if isinstance(e, (NoDeviceConnectedError, DeviceNotFoundError, ConnectionFailedToUsbmuxdError)):
        return ShotError("NO_DEVICE")
    if isinstance(e, PasswordRequiredError):
        return ShotError("LOCKED")
    if isinstance(
        e,
        (
            NotPairedError,
            PairingDialogResponsePendingError,
            UserDeniedPairingError,
            InvalidHostIDError,
            NotTrustedError,
            FatalPairingError,
        ),
    ):
        return ShotError("NOT_PAIRED")
    if isinstance(e, DeveloperModeIsNotEnabledError):
        return ShotError("DEV_MODE_OFF")
    if isinstance(e, UserspaceTunnelUnavailableError):
        return ShotError("UNSUPPORTED")
    return ShotError("UNKNOWN", f"{type(e).__name__}: {e}")


def version_tuple(v: str) -> tuple:
    parts = []
    for p in v.split("."):
        try:
            parts.append(int(p))
        except ValueError:
            break
    return tuple(parts)


class Session:
    def __init__(self) -> None:
        self.lock = asyncio.Lock()
        self.tunnel: Optional[UserspaceRsdTunnel] = None
        self.tunnel_udid: Optional[str] = None
        self.rsd = None
        self.last_used = 0.0
        self.info_cache: dict[str, dict[str, Any]] = {}
        self.revealed: set[str] = set()

    # ---------- 设备 ----------

    async def connected(self) -> list[usbmux.MuxDevice]:
        """当前可连接的设备；同一台手机可能同时出现 USB 与 Network 两条，只保留 USB 那条。"""
        best: dict[str, usbmux.MuxDevice] = {}
        for dev in await usbmux.list_devices():
            if dev.serial not in best or (dev.is_usb and not best[dev.serial].is_usb):
                best[dev.serial] = dev
        return sorted(best.values(), key=lambda d: 0 if d.is_usb else 1)

    async def pick_device(self, udid: Optional[str] = None) -> usbmux.MuxDevice:
        devices = await self.connected()
        if udid:
            for dev in devices:
                if dev.serial == udid:
                    return dev
            raise ShotError("DEVICE_GONE")
        if not devices:
            raise ShotError("NO_DEVICE")
        return devices[0]

    async def device_info(
        self, dev: usbmux.MuxDevice, refresh_dev_mode: bool = False, autopair: bool = True
    ) -> dict[str, Any]:
        cached = self.info_cache.get(dev.serial)
        if cached is not None and not refresh_dev_mode:
            return {**cached, "connection": "USB" if dev.is_usb else "Wi-Fi"}
        lockdown = await create_using_usbmux(
            serial=dev.serial, connection_type=dev.connection_type, autopair=autopair, pair_timeout=PAIR_TIMEOUT
        )
        try:
            values = lockdown.all_values
            info = {
                "udid": dev.serial,
                "name": values.get("DeviceName") or "iPhone",
                "model": lockdown.display_name or values.get("ProductType"),
                "version": lockdown.product_version,
                "devMode": await lockdown.get_developer_mode_status(),
            }
            if not info["devMode"] and dev.serial not in self.revealed:
                # 让「设置 → 隐私与安全性」里出现「开发者模式」开关（默认隐藏，只能通过数据线触发）
                self.revealed.add(dev.serial)
                try:
                    await AmfiService(lockdown).reveal_developer_mode_option_in_ui()
                except Exception as e:
                    logger.info("reveal developer mode failed: %r", e)
        finally:
            await lockdown.close()
        self.info_cache[dev.serial] = info
        return {**info, "connection": "USB" if dev.is_usb else "Wi-Fi"}

    # ---------- 隧道 ----------

    async def close_tunnel(self) -> None:
        tunnel, self.tunnel, self.rsd, self.tunnel_udid = self.tunnel, None, None, None
        if tunnel is not None:
            logger.info("closing tunnel")
            try:
                await asyncio.wait_for(tunnel.aclose(), 5)
            except Exception:
                logger.exception("tunnel close failed")

    async def ensure_tunnel(self, udid: str):
        if self.tunnel is not None and self.tunnel_udid != udid:
            await self.close_tunnel()
        if self.rsd is None:
            logger.info("opening userspace tunnel to %s", udid)
            tunnel = UserspaceRsdTunnel(serial=udid)
            t0 = time.monotonic()
            try:
                rsd = await asyncio.wait_for(tunnel.aopen(), TUNNEL_TIMEOUT)
            except BaseException:
                try:
                    await asyncio.wait_for(tunnel.aclose(), 5)
                except Exception:
                    pass
                raise
            self.tunnel, self.rsd, self.tunnel_udid = tunnel, rsd, udid
            logger.info("tunnel ready in %.0f ms", (time.monotonic() - t0) * 1000)
        return self.rsd

    async def idle_watchdog(self) -> None:
        while True:
            await asyncio.sleep(30)
            if self.tunnel is None or self.lock.locked():
                continue
            if time.monotonic() - self.last_used > IDLE_CLOSE_SECONDS:
                async with self.lock:
                    await self.close_tunnel()

    # ---------- 命令 ----------

    async def list(self, refresh: bool) -> dict[str, Any]:
        """refresh=True 时重新读取每台设备的开发者模式状态（菜单打开时）；否则尽量用缓存（截图前）。"""
        async def one(dev: usbmux.MuxDevice) -> dict[str, Any]:
            try:
                # 列表刷新（菜单打开）只读取信息，不主动发起配对，避免每次开菜单都弹「信任此电脑」
                return await asyncio.wait_for(
                    self.device_info(dev, refresh_dev_mode=refresh, autopair=False), LIST_DEVICE_TIMEOUT
                )
            except Exception as e:
                err = ShotError("TIMEOUT") if isinstance(e, asyncio.TimeoutError) else classify(e)
                cached = self.info_cache.get(dev.serial, {})
                return {
                    "udid": dev.serial,
                    "name": cached.get("name", "iPhone"),
                    "model": cached.get("model"),
                    "version": cached.get("version"),
                    "connection": "USB" if dev.is_usb else "Wi-Fi",
                    "error": err.code,
                    "message": MESSAGES[err.code],
                }

        result = list(await asyncio.gather(*(one(d) for d in await self.connected())))
        return {"devices": result}

    async def screenshot(self, out: str, udid: Optional[str] = None) -> dict[str, Any]:
        t0 = time.monotonic()
        dev = await self.pick_device(udid)
        info = await self.device_info(dev)
        version = version_tuple(info["version"])
        if (17, 0) <= version < (17, 4):
            raise ShotError("UNSUPPORTED")

        mounted_once = False
        reconnected_once = False
        while True:
            lockdown = None
            try:
                if version < (17, 0):
                    lockdown = await create_using_usbmux(serial=dev.serial, connection_type=dev.connection_type)
                    provider = lockdown
                else:
                    provider = await self.ensure_tunnel(dev.serial)
                try:
                    data = await asyncio.wait_for(self._take(provider), SHOT_TIMEOUT)
                except SERVICE_ERRORS as e:
                    logger.warning("service unavailable: %r", e)
                    if mounted_once:
                        raise
                    info = await self.device_info(dev, refresh_dev_mode=True)
                    if not info["devMode"]:
                        raise ShotError("DEV_MODE_OFF") from e
                    await self._mount(provider)
                    mounted_once = True
                    continue
            except RECONNECT_ERRORS as e:
                if reconnected_once:
                    raise
                logger.warning("connection error, reconnecting: %r", e)
                reconnected_once = True
                await self.close_tunnel()
                continue
            finally:
                if lockdown is not None:
                    await lockdown.close()
            break

        Path(out).write_bytes(data)
        self.last_used = time.monotonic()
        ms = int((time.monotonic() - t0) * 1000)
        logger.info("screenshot %d bytes in %d ms", len(data), ms)
        return {"device": {**info, "connection": "USB" if dev.is_usb else "Wi-Fi"}, "ms": ms}

    async def _take(self, provider) -> bytes:
        async with DvtProvider(provider) as dvt, Screenshot(dvt) as shot:
            data = await shot.get_screenshot()
        if not data:
            raise ShotError("UNKNOWN", "设备返回了空截图")
        return data

    async def _mount(self, provider) -> None:
        logger.info("auto-mounting developer disk image")
        try:
            await asyncio.wait_for(auto_mount(provider), MOUNT_TIMEOUT)
        except AlreadyMountedError:
            pass
        except DeveloperModeIsNotEnabledError as e:
            raise ShotError("DEV_MODE_OFF") from e
        except Exception as e:
            logger.exception("auto-mount failed")
            raise ShotError("MOUNT_FAILED", f"{type(e).__name__}: {e}") from e


def reply(payload: dict[str, Any]) -> None:
    _PROTOCOL_OUT.write(json.dumps(payload, ensure_ascii=False) + "\n")
    _PROTOCOL_OUT.flush()


async def handle(session: Session, req: dict[str, Any]) -> dict[str, Any]:
    cmd = req.get("cmd")
    async with session.lock:
        try:
            if cmd == "list":
                result = await session.list(bool(req.get("refresh")))
            elif cmd == "screenshot":
                result = await session.screenshot(req["out"], req.get("udid"))
            elif cmd == "ping":
                result = {}
            else:
                raise ShotError("UNKNOWN", f"unknown command: {cmd}")
            return {"ok": True, **result}
        except BaseException as e:
            if isinstance(e, (KeyboardInterrupt, SystemExit, asyncio.CancelledError)):
                raise
            err = classify(e)
            if err.code == "UNKNOWN":
                logger.error("%s failed", cmd, exc_info=e)
                # 状态未知，丢弃隧道，下次重新建立
                await session.close_tunnel()
            else:
                logger.info("%s failed: %s %s", cmd, err.code, err.detail)
            return {"ok": False, "code": err.code, "message": MESSAGES[err.code], "detail": err.detail}


async def main() -> None:
    session = Session()
    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader()
    await loop.connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin)
    watchdog = asyncio.create_task(session.idle_watchdog())
    logger.info("helper started (pid %d)", os.getpid())
    reply({"event": "ready"})
    try:
        while True:
            line = await reader.readline()
            if not line:
                break  # App 退出，stdin 关闭
            try:
                req = json.loads(line)
            except json.JSONDecodeError:
                continue
            resp = await handle(session, req)
            reply({"id": req.get("id"), **resp})
    finally:
        watchdog.cancel()
        await session.close_tunnel()
        logger.info("helper exiting")


if __name__ == "__main__":
    asyncio.run(main())
