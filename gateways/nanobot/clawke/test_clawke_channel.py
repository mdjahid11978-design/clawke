from __future__ import annotations

import json
import sys
import types

import pytest


class _BaseChannel:
    def __init__(self, config, bus):
        self.config = config
        self.bus = bus
        self._running = False

    def is_allowed(self, _sender_id):
        return True


class _OutboundMessage:
    def __init__(self, content="", chat_id="", metadata=None):
        self.content = content
        self.chat_id = chat_id
        self.metadata = metadata or {}


nanobot = types.ModuleType("nanobot")
nanobot_bus = types.ModuleType("nanobot.bus")
nanobot_bus_events = types.ModuleType("nanobot.bus.events")
nanobot_bus_events.InboundMessage = object
nanobot_bus_events.OutboundMessage = _OutboundMessage
nanobot_bus_queue = types.ModuleType("nanobot.bus.queue")
nanobot_bus_queue.MessageBus = object
nanobot_channels = types.ModuleType("nanobot.channels")
nanobot_channels_base = types.ModuleType("nanobot.channels.base")
nanobot_channels_base.BaseChannel = _BaseChannel
sys.modules.setdefault("nanobot", nanobot)
sys.modules.setdefault("nanobot.bus", nanobot_bus)
sys.modules.setdefault("nanobot.bus.events", nanobot_bus_events)
sys.modules.setdefault("nanobot.bus.queue", nanobot_bus_queue)
sys.modules.setdefault("nanobot.channels", nanobot_channels)
sys.modules.setdefault("nanobot.channels.base", nanobot_channels_base)

loguru = types.ModuleType("loguru")
loguru.logger = types.SimpleNamespace(
    info=lambda *args, **kwargs: None,
    warning=lambda *args, **kwargs: None,
    warn=lambda *args, **kwargs: None,
    error=lambda *args, **kwargs: None,
    debug=lambda *args, **kwargs: None,
)
websockets = types.ModuleType("websockets")
websockets.connect = None
sys.modules.setdefault("loguru", loguru)
sys.modules.setdefault("websockets", websockets)

from clawke import ClawkeChannel


class Config:
    url = "ws://127.0.0.1:8766"
    account_id = "nanobot"


class FakeWs:
    def __init__(self):
        self.sent = []

    async def send(self, raw):
        self.sent.append(json.loads(raw))


@pytest.fixture
def channel():
    ch = ClawkeChannel(Config(), object())
    ch._ws = FakeWs()
    return ch


@pytest.mark.asyncio
async def test_system_request_returns_response_without_user_message(channel):
    async def fake_run(msg):
        assert msg["system_session_id"] == "__clawke_system__:nanobot"
        assert msg["prompt"] == "Return strict JSON."
        return '{"description":"中文描述"}'

    channel._run_system_session = fake_run

    await channel._handle_gateway_system_request({
        "type": "gateway_system_request",
        "request_id": "req_1",
        "gateway_id": "nanobot",
        "system_session_id": "__clawke_system__:nanobot",
        "purpose": "translation",
        "prompt": "Return strict JSON.",
    })

    assert channel._ws.sent == [{
        "type": "gateway_system_response",
        "request_id": "req_1",
        "ok": True,
        "json": {"description": "中文描述"},
    }]


@pytest.mark.asyncio
async def test_system_request_invalid_json_returns_safe_error(channel):
    async def fake_run(_msg):
        return "not json"

    channel._run_system_session = fake_run

    await channel._handle_gateway_system_request({
        "type": "gateway_system_request",
        "request_id": "req_2",
        "gateway_id": "nanobot",
        "system_session_id": "__clawke_system__:nanobot",
        "purpose": "translation",
        "prompt": "Return strict JSON.",
    })

    assert channel._ws.sent[0]["type"] == "gateway_system_response"
    assert channel._ws.sent[0]["request_id"] == "req_2"
    assert channel._ws.sent[0]["ok"] is False
    assert channel._ws.sent[0]["error_code"] == "invalid_json"
