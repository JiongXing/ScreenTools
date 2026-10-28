"""无需设备或 pymobiledevice3，隔离执行真实辅助进程的相册方法。

通过 AST 只加载相册方法与协议分发，避免 helper 顶层重定向 stdout、写日志和加载设备依赖。
运行：python3 -B -m unittest discover -s mac-app/helper/tests
"""
from __future__ import annotations

import ast
import asyncio
import datetime
import logging
import os
import time
from pathlib import Path
import types
import unittest
from unittest.mock import AsyncMock, patch


def load_media_code():
    tree = ast.parse((Path(__file__).parents[1] / "ios_helper.py").read_text())
    selected = [ast.ImportFrom(module="__future__", names=[ast.alias(name="annotations")], level=0)]
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(target, ast.Name) and target.id.startswith(("PHOTO_", "VIDEO_", "MEDIA_"))
            for target in node.targets
        ):
            selected.append(node)
        elif isinstance(node, ast.ClassDef) and node.name == "Session":
            node.body = [method for method in node.body if isinstance(method, ast.AsyncFunctionDef) and method.name in ("photos_list", "photos_pull")]
            selected.append(node)
        elif isinstance(node, ast.AsyncFunctionDef) and node.name == "handle":
            selected.append(node)
    namespace = {
        "os": os, "asyncio": asyncio, "time": time, "logger": logging.getLogger(__name__),
        "AfcException": type("AfcException", (OSError,), {}), "ConnectionTerminatedError": ConnectionError,
    }
    exec(compile(ast.fix_missing_locations(ast.Module(body=selected, type_ignores=[])), "ios_media", "exec"), namespace)
    return types.SimpleNamespace(**namespace)


class MediaTests(unittest.IsolatedAsyncioTestCase):
    async def test_listing_includes_videos_preserves_limit_and_ignores_hidden(self):
        media = load_media_code()
        afc = AsyncMock()
        afc.__aenter__.return_value = afc
        afc.listdir.side_effect = lambda path: {
            "/DCIM": ["100APPLE", ".hidden"],
            "/DCIM/100APPLE": ["IMG_0001.HEIC", "IMG_0002.MOV", "IMG_0003.MP4", "IMG_0004.BMP", ".hidden.MOV", "sidecar.AAE"],
        }[path]
        afc.isdir.return_value = True
        afc.stat.return_value = {"st_size": 123, "st_mtime": datetime.datetime(2026, 10, 28)}
        lockdown = types.SimpleNamespace(close=AsyncMock())
        session = media.Session()
        session._open_afc = AsyncMock(return_value=(lockdown, afc))
        result = await session.photos_list("DEVICE", 3)
        self.assertEqual(result["total"], 4)
        self.assertEqual([item["path"] for item in result["photos"]], [
            "/DCIM/100APPLE/IMG_0004.BMP", "/DCIM/100APPLE/IMG_0003.MP4", "/DCIM/100APPLE/IMG_0002.MOV",
        ])
        lockdown.close.assert_awaited_once()

    async def test_protocol_selects_video_timeout_without_changing_reply(self):
        media = load_media_code()
        session = types.SimpleNamespace(lock=asyncio.Lock(), photos_pull=AsyncMock(return_value={"results": []}))
        real_wait_for = asyncio.wait_for
        for path, timeout in [("/DCIM/100APPLE/clip.MOV", 900), ("/DCIM/100APPLE/image.HEIC", 240)]:
            with patch.object(asyncio, "wait_for", wraps=real_wait_for) as wait_for:
                result = await media.handle(session, {"cmd": "photos_pull", "udid": "DEVICE", "items": [{"path": path, "out": "/tmp/unused"}]})
                self.assertEqual(wait_for.call_args.args[1], timeout)
                self.assertEqual(result, {"ok": True, "results": []})

    async def test_missing_device_file_does_not_abort_remaining_preview_items(self):
        media = load_media_code()
        afc = AsyncMock()
        afc.__aenter__.return_value = afc
        afc.pull.side_effect = [media.AfcException("file no longer exists"), None]
        lockdown = types.SimpleNamespace(close=AsyncMock())
        session = media.Session()
        session._open_afc = AsyncMock(return_value=(lockdown, afc))
        result = await session.photos_pull("DEVICE", [
            {"path": "/DCIM/100APPLE/missing.MOV", "out": "/tmp/missing"},
            {"path": "/DCIM/100APPLE/present.HEIC", "out": "/tmp/present"},
        ])
        self.assertEqual([item["ok"] for item in result["results"]], [False, True])
        lockdown.close.assert_awaited_once()


if __name__ == "__main__":
    unittest.main()
