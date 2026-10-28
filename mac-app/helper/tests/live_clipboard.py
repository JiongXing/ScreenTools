"""显式指定设备才执行；完整备份 iPhone 剪贴板到内存，并在 finally 中恢复。

使用打包 Python 运行：live_clipboard.py --udid <UDID> [--hold-for-ui]
--hold-for-ui 在协议验证后等待回车，供操作者继续测试 App，再恢复原内容。
不把剪贴板正文写入文件、日志或终端。
"""
import argparse
import asyncio
import importlib.util
import json
import sys
from pathlib import Path

REPORT = sys.stdout


def report(message):
    print(message, file=REPORT, flush=True)


async def main(args):
    path = Path(__file__).parents[1] / "ios_helper.py"
    spec = importlib.util.spec_from_file_location("clipboard_live_helper", path)
    helper = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(helper)
    from pymobiledevice3.remote.core_device.pasteboard_service import PasteboardService

    session = helper.Session()
    backup = None
    child = None
    try:
        provider = await session.ensure_tunnel(args.udid)
        async with PasteboardService(provider) as service:
            snapshot = await asyncio.wait_for(service.get(), 90)
        candidate = snapshot["pasteboard"]
        for item in candidate.get("items", []):
            for uti in item.get("types", []):
                raw = item.get("data", {}).get(uti, {}).get("data")
                if not isinstance(raw, bytes):
                    raise RuntimeError("原剪贴板存在无法完整备份的内容，未执行写入测试")
        backup = candidate
        report("BACKUP_OK (contents retained in memory only)")
        await session.close_tunnel()
        child = await asyncio.create_subprocess_exec(
            sys.executable, "-I", "-B", str(path), stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
        )
        request_id = 0

        async def request(command, **params):
            nonlocal request_id
            request_id += 1
            payload = {"id": request_id, "cmd": command, "udid": args.udid, **params}
            child.stdin.write((json.dumps(payload) + "\n").encode())
            await child.stdin.drain()
            while True:
                line = await asyncio.wait_for(child.stdout.readline(), 240)
                if not line:
                    raise RuntimeError("helper exited")
                reply = json.loads(line)
                if reply.get("id") != request_id:
                    continue
                if not reply.get("ok"):
                    raise RuntimeError("helper failure: " + reply.get("code", "UNKNOWN"))
                return reply

        # 跨越真实 JSON-lines/HelperClient 相同的协议边界，空字符串也必须保持。
        for label, value in [
            ("unicode_multiline_url", "ScreenTools 调试 🧪\n'引号' \"双引号\"\nhttps://example.com/?a=1&b=2"),
            ("empty", ""),
            ("long_text", "ScreenTools长文本🧪\n" * 3000),
            ("repeat", "ScreenTools clipboard validation 🧪"),
            ("repeat_identical", "ScreenTools clipboard validation 🧪"),
        ]:
            await request("clipboard_set", text=value)
            result = await request("clipboard_get")
            if result.get("text") != value:
                raise RuntimeError("round trip mismatch: " + label)
            report("PASS " + label)
        child.stdin.close()
        await asyncio.wait_for(child.wait(), 10)
        child = None
        # 新 helper 进程/新隧道应能继续读到同一份内容。
        result = await session.clipboard(args.udid)
        if result.get("text") != "ScreenTools clipboard validation 🧪":
            raise RuntimeError("reconnect mismatch")
        report("PASS helper_restart_and_tunnel_reconnect")
        await session.close_tunnel()
        if args.hold_for_ui:
            report("UI_TEST_WINDOW_READY; send newline to restore original clipboard")
            await asyncio.to_thread(sys.stdin.readline)
    finally:
        if child is not None:
            child.stdin.close()
            try:
                await asyncio.wait_for(child.wait(), 10)
            except asyncio.TimeoutError:
                child.terminate()
                await child.wait()
        if backup is not None:
            provider = await session.ensure_tunnel(args.udid)
            async with PasteboardService(provider) as service:
                await asyncio.wait_for(service.set(backup.get("items", []), source_metadata=backup.get("sourceMetadata")), 30)
                restored = (await asyncio.wait_for(service.get(), 90))["pasteboard"]
            if restored.get("items", []) != backup.get("items", []):
                raise RuntimeError("恢复后的剪贴板与完整备份不一致")
            report("RESTORE_VERIFIED")
        await session.close_tunnel()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--udid", required=True)
    parser.add_argument("--hold-for-ui", action="store_true")
    arguments = parser.parse_args()
    try:
        asyncio.run(main(arguments))
    except Exception as error:
        report("LIVE_TEST_FAILED: " + type(error).__name__ + " " + str(error))
        raise SystemExit(1)
