"""隔离加载真实剪贴板实现，不启动 helper、写日志或访问手机。"""
import ast
import asyncio
import logging
import time
import types
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, Mock


class ShotError(Exception):
    def __init__(self, code, detail=""):
        self.code, self.detail = code, detail


class ServiceError(Exception):
    pass


def load_code():
    tree = ast.parse((Path(__file__).parents[1] / "ios_helper.py").read_text())
    selected = [ast.ImportFrom(module="__future__", names=[ast.alias(name="annotations")], level=0)]
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name in ("clipboard_text", "checked_clipboard_text", "version_tuple"):
            selected.append(node)
        elif isinstance(node, ast.ClassDef) and node.name == "Session":
            node.body = [method for method in node.body if isinstance(method, ast.AsyncFunctionDef) and method.name == "clipboard"]
            selected.append(node)
        elif isinstance(node, ast.AsyncFunctionDef) and node.name == "handle":
            selected.append(node)
    ns = dict(asyncio=asyncio, time=time, ShotError=ShotError, CLIPBOARD_TIMEOUT=0.05, MAX_CLIPBOARD_BYTES=1024 * 1024,
              POLICY_PROMISE_SECONDARY={"promiseSecondary": {}}, SERVICE_ERRORS=(ServiceError,),
              RECONNECT_ERRORS=(ConnectionError, OSError, asyncio.TimeoutError, EOFError),
              logger=logging.getLogger(__name__))
    exec(compile(ast.fix_missing_locations(ast.Module(body=selected, type_ignores=[])), "clipboard", "exec"), ns)
    return types.SimpleNamespace(**ns), ns


def snapshot(text, uti="public.utf8-plain-text"):
    return {"pasteboard": {"items": [{"data": {uti: {"data": text.encode("utf-8")}}}]}}


class ClipboardTests(unittest.IsolatedAsyncioTestCase):
    def session(self, code):
        session = code.Session()
        session.pick_device = AsyncMock(return_value=types.SimpleNamespace(serial="TEST"))
        session.device_info = AsyncMock(return_value={"version": "26.6.2", "devMode": True})
        session.ensure_tunnel = AsyncMock(return_value=object())
        session.close_tunnel = AsyncMock()
        session._mount = AsyncMock()
        return session

    def test_text_url_empty_and_non_text(self):
        code, _ = load_code()
        for text in ("", "中文🧪\n'\"", "a" * 100000):
            self.assertEqual(code.clipboard_text(snapshot(text)), text)
        self.assertEqual(code.clipboard_text(snapshot("https://example.com", "public.url")), "https://example.com")
        self.assertIsNone(code.clipboard_text(snapshot("image", "public.png")))
        self.assertIsNone(code.clipboard_text({"pasteboard": {"items": []}}))
        self.assertIsNone(code.clipboard_text({"pasteboard": {"items": [{"data": {"public.text": {"isPromised": True}}}]}}))

    async def test_read_primary_policy_and_write_empty(self):
        code, ns = load_code()
        service = AsyncMock()
        service.get.return_value = snapshot("中文 🧪")
        ns["PasteboardService"] = Mock(return_value=service)
        session = self.session(code)
        self.assertEqual(await session.clipboard("TEST"), {"text": "中文 🧪"})
        service.get.assert_awaited_once_with(data_policy={"promiseSecondary": {}})
        service.close.assert_awaited_once()
        service.get.side_effect = [snapshot("中文 🧪"), snapshot("")]
        service.set_text.return_value = {}
        await session.clipboard("TEST", "")
        service.set_text.assert_awaited_once_with("")

    async def test_missing_service_mounts_once_without_sending_write(self):
        code, ns = load_code()
        service = AsyncMock()
        service.connect.side_effect = ServiceError()
        ns["PasteboardService"] = Mock(return_value=service)
        session = self.session(code)
        with self.assertRaises(ShotError) as error:
            await session.clipboard("TEST", "must not write")
        self.assertEqual(error.exception.code, "CLIPBOARD_UNSUPPORTED")
        session._mount.assert_awaited_once()
        service.set_text.assert_not_awaited()

    async def test_timeout_and_disconnect_close_tunnel_without_retry(self):
        for failure in (asyncio.TimeoutError(), ConnectionError()):
            code, ns = load_code()
            service = AsyncMock()
            service.get.return_value = snapshot("original")
            service.set_text.side_effect = failure
            ns["PasteboardService"] = Mock(return_value=service)
            session = self.session(code)
            with self.assertRaises(ShotError) as error:
                await session.clipboard("TEST", "test")
            self.assertEqual(error.exception.code, "CLIPBOARD_TIMEOUT" if isinstance(failure, asyncio.TimeoutError) else "DEVICE_GONE")
            service.set_text.assert_awaited_once_with("test")
            session.close_tunnel.assert_awaited_once()
            service.close.assert_awaited_once()
            # 下一次手动读取重新连接并成功，不重试之前的写入。
            self.assertEqual(await session.clipboard("TEST"), {"text": "original"})
            self.assertEqual(service.connect.await_count, 2)
            service.set_text.assert_awaited_once_with("test")

    async def test_unavailable_text_data_prevents_write(self):
        code, ns = load_code()
        service = AsyncMock()
        service.get.return_value = {"pasteboard": {"items": [{"types": ["public.utf8-plain-text"],
                                                             "data": {"public.utf8-plain-text": {}}}]}}
        ns["PasteboardService"] = Mock(return_value=service)
        session = self.session(code)
        with self.assertRaises(ShotError) as error:
            await session.clipboard("TEST", "new text")
        self.assertEqual(error.exception.code, "CLIPBOARD_NO_DATA")
        service.set_text.assert_not_awaited()

    async def test_write_must_be_verified_and_size_limit_precedes_device_access(self):
        code, ns = load_code()
        service = AsyncMock()
        service.get.return_value = snapshot("old text")
        service.set_text.return_value = {}
        ns["PasteboardService"] = Mock(return_value=service)
        session = self.session(code)
        with self.assertRaises(ShotError) as error:
            await session.clipboard("TEST", "new text")
        self.assertEqual(error.exception.code, "CLIPBOARD_VERIFY_FAILED")
        with self.assertRaises(ShotError) as error:
            await session.clipboard("TEST", "x" * (1024 * 1024 + 1))
        self.assertEqual(error.exception.code, "CLIPBOARD_TOO_LARGE")

    async def test_old_os_and_disabled_developer_mode(self):
        for info, expected in [({"version": "16.7", "devMode": True}, "CLIPBOARD_UNSUPPORTED"),
                               ({"version": "26.6", "devMode": False}, "DEV_MODE_OFF")]:
            code, _ = load_code()
            session = self.session(code)
            session.device_info.return_value = info
            with self.assertRaises(ShotError) as error:
                await session.clipboard("TEST")
            self.assertEqual(error.exception.code, expected)
            session.ensure_tunnel.assert_not_awaited()

    async def test_protocol_dispatch_get_and_set(self):
        code, _ = load_code()
        session = types.SimpleNamespace(lock=asyncio.Lock(), clipboard=AsyncMock(return_value={"text": "ok"}))
        result = await code.handle(session, {"cmd": "clipboard_get", "udid": "TEST"})
        self.assertEqual(result, {"ok": True, "text": "ok"})
        session.clipboard.assert_awaited_once_with("TEST", None)
        session.clipboard.reset_mock()
        await code.handle(session, {"cmd": "clipboard_set", "udid": "TEST", "text": ""})
        session.clipboard.assert_awaited_once_with("TEST", "")


if __name__ == "__main__":
    unittest.main()
