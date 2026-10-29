"""隔离加载真实剪贴板实现，不启动 helper、写日志或访问手机。"""
import ast
import asyncio
import logging
import plistlib
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
        if isinstance(node, ast.FunctionDef) and node.name in (
                "clipboard_items", "clipboard_text", "promises_text", "version_tuple",
                "protobuf_string", "notes_text"):
            selected.append(node)
        elif isinstance(node, ast.Assign) and any(
                getattr(target, "id", None) in ("TEXT_UTIS", "NOTES_UTI") for target in node.targets):
            selected.append(node)
        elif isinstance(node, ast.ClassDef) and node.name == "Session":
            node.body = [method for method in node.body if isinstance(method, ast.AsyncFunctionDef)
                         and method.name in ("clipboard", "_clipboard_read")]
            selected.append(node)
        elif isinstance(node, ast.AsyncFunctionDef) and node.name == "handle":
            selected.append(node)
    ns = dict(asyncio=asyncio, plistlib=plistlib, time=time, ShotError=ShotError, CLIPBOARD_TIMEOUT=0.05,
              MAX_CLIPBOARD_BYTES=1024 * 1024,
              POLICY_PROMISE_SECONDARY={"promiseSecondary": {}},
              SERVICE_ERRORS=(ServiceError,),
              RECONNECT_ERRORS=(ConnectionError, OSError, asyncio.TimeoutError, EOFError),
              logger=logging.getLogger(__name__))
    exec(compile(ast.fix_missing_locations(ast.Module(body=selected, type_ignores=[])), "clipboard", "exec"), ns)
    return types.SimpleNamespace(**ns), ns


def snapshot(text, uti="public.utf8-plain-text"):
    return {"pasteboard": {"items": [{"data": {uti: {"data": text.encode("utf-8")}}}]}}


def promised_text(primary, data=b"primary"):
    """手机上复制富文本时 promiseSecondary 的形态：首类型内联，纯文本被承诺（{}）。"""
    types = [primary, "public.utf8-plain-text", "public.rtf"]
    return {"pasteboard": {"items": [{"types": types, "data": {primary: {"data": data},
                                                                "public.utf8-plain-text": {}, "public.rtf": {}}}]}}


def notes_archive(text):
    """备忘录首类型的形态：ICNotePasteboardData 归档，attributedStringData 是 protobuf（字段 2 为正文）。"""
    body = text.encode("utf-8")
    proto = bytes([0x08, 0x00, 0x12]) + varint(len(body)) + body + bytes([0x2A, 0x02, 0x08, 0x01])
    return plistlib.dumps({
        "$version": 100000, "$archiver": "NSKeyedArchiver", "$top": {"root": plistlib.UID(1)},
        "$objects": ["$null", {"attributedStringData": plistlib.UID(2), "$class": plistlib.UID(3)},
                     {"NS.data": proto}, {"$classname": "ICNotePasteboardData"}],
    }, fmt=plistlib.FMT_BINARY)


def varint(n):
    out = bytearray()
    while True:
        out.append((n & 0x7F) | (0x80 if n > 0x7F else 0))
        n >>= 7
        if not n:
            return bytes(out)


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
        service.get.reset_mock()
        service.get.side_effect = [snapshot("")]
        service.set_text.return_value = {}
        self.assertEqual(await session.clipboard("TEST", ""), {})
        service.set_text.assert_awaited_once_with("")
        service.get.assert_awaited_once_with(data_policy={"promiseSecondary": {}})

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

    async def test_write_replaces_unreadable_content_without_reading_first(self):
        code, ns = load_code()
        service = AsyncMock()
        service.set_text.return_value = {}
        service.get.return_value = snapshot("new text")
        ns["PasteboardService"] = Mock(return_value=service)
        session = self.session(code)
        self.assertEqual(await session.clipboard("TEST", "new text"), {})
        service.set_text.assert_awaited_once_with("new text")
        # 只有写后核对的一次读取，且不全量拉取。
        service.get.assert_awaited_once_with(data_policy={"promiseSecondary": {}})

    async def test_notes_primary_is_parsed_without_full_pull(self):
        code, ns = load_code()
        text = "备忘录 🧪\n" * 30 + "\ufffc附件后"
        service = AsyncMock()
        service.get.return_value = promised_text("com.apple.notes.richtext", notes_archive(text))
        ns["PasteboardService"] = Mock(return_value=service)
        session = self.session(code)
        self.assertEqual(await session.clipboard("TEST"), {"text": text.replace("\ufffc", "")})
        service.get.assert_awaited_once_with(data_policy={"promiseSecondary": {}})
        self.assertIsNone(code.notes_text(promised_text("com.apple.notes.richtext", b"not a plist")))

    async def test_promised_text_is_reported_without_slow_full_pull(self):
        code, ns = load_code()
        service = AsyncMock()
        # Safari 网页复制：首类型只是个标记，纯文本被承诺。
        service.get.return_value = promised_text("iOS rich content paste pasteboard type", b"iOS rich content paste pasteboard type")
        ns["PasteboardService"] = Mock(return_value=service)
        session = self.session(code)
        with self.assertRaises(ShotError) as error:
            await session.clipboard("TEST")
        self.assertEqual(error.exception.code, "CLIPBOARD_NO_DATA")
        service.get.assert_awaited_once_with(data_policy={"promiseSecondary": {}})
        # 图片等非文本内容表示没有文本，不报错。
        service.get.reset_mock()
        service.get.return_value = snapshot("png", "public.png")
        self.assertEqual(await session.clipboard("TEST"), {"text": None})

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
