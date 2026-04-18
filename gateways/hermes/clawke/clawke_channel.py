"""Clawke channel — connects Hermes AIAgent to Clawke Server as an AI gateway.

Protocol reference: docs/GATEWAY_INTEGRATION.md

This channel runs as a standalone Python process sharing the Hermes Python
environment, connecting to Clawke Server's upstream WebSocket port (default
8766). It directly instantiates Hermes AIAgent with five callbacks mapped
to the CUP protocol:

  stream_delta_callback  →  agent_text_delta
  reasoning_callback     →  agent_thinking_delta / agent_thinking_done
  tool_progress_callback →  agent_tool_call / agent_tool_result
  clarify_callback       →  clarify_request / clarify_response
  approval (notify)      →  approval_request / approval_response

Architecture reference:
  - nanobot gateway (gateways/nanobot/clawke/clawke.py) — WS client pattern
  - hermes-webui (api/streaming.py) — AIAgent instantiation + callbacks
  - OpenClaw gateway (gateways/openclaw/clawke/src/gateway.ts) — streaming + abort
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
import random
import sys
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

import websockets

logger = logging.getLogger("clawke.hermes")

# ─── CUP Protocol Message Types (mirror of protocol.ts) ─────────────────────

class GatewayMessageType:
    """Gateway → Clawke Server (downstream: AI output)."""
    Identify = "identify"
    ModelsResponse = "models_response"
    SkillsResponse = "skills_response"

    AgentTyping = "agent_typing"
    AgentTextDelta = "agent_text_delta"
    AgentTextDone = "agent_text_done"
    AgentText = "agent_text"

    AgentMedia = "agent_media"

    AgentToolCall = "agent_tool_call"
    AgentToolResult = "agent_tool_result"

    AgentThinkingDelta = "agent_thinking_delta"
    AgentThinkingDone = "agent_thinking_done"

    AgentStatus = "agent_status"
    AgentTurnStats = "agent_turn_stats"

    ApprovalRequest = "approval_request"
    ClarifyRequest = "clarify_request"


class InboundMessageType:
    """Clawke Server → Gateway (upstream: user input / control)."""
    Chat = "chat"
    Abort = "abort"
    QueryModels = "query_models"
    QuerySkills = "query_skills"
    ApprovalResponse = "approval_response"
    ClarifyResponse = "clarify_response"


class AgentStatusValue:
    """agent_status message status field values."""
    Compacting = "compacting"
    Thinking = "thinking"
    Queued = "queued"


# ─── Exponential Backoff ─────────────────────────────────────────────────────

BACKOFF_FIRST_S = 0.1
BACKOFF_MAX_S = 10.0
BACKOFF_BASE = 2


def _backoff_delay(attempt: int) -> float:
    """Calculate exponential backoff delay with ±25% jitter."""
    exp = BACKOFF_FIRST_S * (BACKOFF_BASE ** attempt)
    capped = min(exp, BACKOFF_MAX_S)
    return capped * (0.75 + random.random() * 0.5)


# ─── Lazy imports for Hermes components ──────────────────────────────────────

_AIAgent = None
_SessionDB = None


def _get_ai_agent():
    """Lazily import AIAgent from hermes-agent."""
    global _AIAgent
    if _AIAgent is None:
        try:
            from run_agent import AIAgent
            _AIAgent = AIAgent
        except ImportError:
            logger.error("Failed to import AIAgent from run_agent. "
                         "Ensure hermes-agent is on sys.path.")
    return _AIAgent


def _get_session_db():
    """Lazily create a SessionDB instance."""
    global _SessionDB
    if _SessionDB is None:
        try:
            from hermes_state import SessionDB
            _SessionDB = SessionDB()
        except Exception as e:
            logger.warning("SessionDB init failed (session_search unavailable): %s", e)
    return _SessionDB


# ─── Gateway ─────────────────────────────────────────────────────────────────

@dataclass
class GatewayConfig:
    """Configuration for the Hermes Clawke Gateway."""
    ws_url: str = "ws://127.0.0.1:8766"
    account_id: str = "hermes"
    model: str = ""
    provider: str = ""
    base_url: str = ""
    toolsets: list[str] = field(default_factory=list)


class ClawkeHermesGateway:
    """Clawke gateway channel — runs inside Hermes process.

    Connects to Clawke Server via WebSocket, receives user messages,
    runs them through Hermes AIAgent with streaming callbacks, and
    sends responses back using the CUP protocol.
    """

    def __init__(self, config: GatewayConfig):
        self.config = config
        self._ws: Any = None
        self._running = False
        self._reconnect_attempt = 0
        self._loop: asyncio.AbstractEventLoop | None = None

        # Per-session state
        self._cancel_events: dict[str, threading.Event] = {}
        self._agents: dict[str, Any] = {}
        self._session_locks: dict[str, asyncio.Lock] = {}
        self._active_dispatches: dict[str, asyncio.Task] = {}

        # Streaming state per conversation
        self._partial_texts: dict[str, str] = {}

        # Approval/Clarify pending requests (session_id → {event, result})
        self._pending_approvals: dict[str, dict] = {}
        self._pending_clarifies: dict[str, dict] = {}

    # ── Public API ───────────────────────────────────────────────────────

    async def start(self) -> None:
        """Start the gateway: connect and listen with auto-reconnect."""
        self._running = True
        self._loop = asyncio.get_event_loop()
        logger.info("Clawke Hermes Gateway starting → %s", self.config.ws_url)

        while self._running:
            try:
                await self._connect()
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error("Clawke connection error: %s", e)

            if not self._running:
                break

            delay = _backoff_delay(self._reconnect_attempt)
            self._reconnect_attempt += 1
            logger.info("Reconnecting in %.1fs (attempt %d)",
                        delay, self._reconnect_attempt)
            await asyncio.sleep(delay)

    async def stop(self) -> None:
        """Stop the gateway gracefully."""
        self._running = False
        if self._ws:
            await self._ws.close()
            self._ws = None
        # Cancel all active dispatches
        for task in self._active_dispatches.values():
            task.cancel()
        logger.info("Clawke Hermes Gateway stopped")

    # ── Connection ───────────────────────────────────────────────────────

    async def _connect(self) -> None:
        """Establish WebSocket connection and handle messages."""
        async with websockets.connect(self.config.ws_url) as ws:
            self._ws = ws
            self._reconnect_attempt = 0
            logger.info("Connected to Clawke Server")

            # Handshake: identify
            await ws.send(json.dumps({
                "type": GatewayMessageType.Identify,
                "accountId": self.config.account_id,
            }))
            logger.info("Identified as account=%s", self.config.account_id)

            # Listen for inbound messages
            async for raw in ws:
                try:
                    msg = json.loads(raw)
                except (json.JSONDecodeError, TypeError):
                    continue

                msg_type = msg.get("type")

                if msg_type == InboundMessageType.Chat:
                    await self._dispatch_chat(msg)

                elif msg_type == InboundMessageType.Abort:
                    self._handle_abort(msg)

                elif msg_type == InboundMessageType.QueryModels:
                    await self._handle_query_models()

                elif msg_type == InboundMessageType.QuerySkills:
                    await self._handle_query_skills()

                elif msg_type == InboundMessageType.ApprovalResponse:
                    self._handle_approval_response(msg)

                elif msg_type == InboundMessageType.ClarifyResponse:
                    self._handle_clarify_response(msg)

        self._ws = None
        logger.info("Disconnected from Clawke Server")

    # ── Message Dispatch (serial per-session queue) ──────────────────────

    async def _dispatch_chat(self, msg: dict) -> None:
        """Dispatch chat message with per-session serial execution."""
        sender_id = msg.get("conversation_id", "clawke_user")

        # Get or create per-session lock
        if sender_id not in self._session_locks:
            self._session_locks[sender_id] = asyncio.Lock()
        lock = self._session_locks[sender_id]

        # If session is busy, notify client
        if lock.locked():
            logger.info("⏳ Session %s busy, queuing message", sender_id)
            await self._send({
                "type": GatewayMessageType.AgentStatus,
                "status": AgentStatusValue.Queued,
                "account_id": self.config.account_id,
                "conversation_id": sender_id,
            })

        async with lock:
            # Check if abort was requested while queued
            cancel = self._cancel_events.get(sender_id)
            if cancel and cancel.is_set():
                logger.info("🚫 Session %s aborted while queued, dropping", sender_id)
                self._cancel_events.pop(sender_id, None)
                return
            await self._handle_chat(msg)

    async def _handle_chat(self, msg: dict) -> None:
        """Core: instantiate AIAgent, register callbacks, run conversation."""
        text = msg.get("text", "")
        sender_id = msg.get("conversation_id", "clawke_user")
        client_msg_id = msg.get("client_msg_id", f"clawke_{int(time.time() * 1000)}")
        msg_id = f"reply_{int(time.time() * 1000)}"
        thinking_msg_id = f"think_{msg_id}"

        logger.info("📥 Inbound: %s (conv=%s)", text[:80], sender_id)

        # Create cancel event for this dispatch
        cancel_event = threading.Event()
        self._cancel_events[sender_id] = cancel_event

        # Streaming state
        has_streamed_text = False
        has_streamed_thinking = False
        full_text = ""
        reasoning_text = ""
        tool_calls: list[dict] = []
        tool_call_counter = 0

        # ── Callbacks → CUP Protocol ────────────────────────────────────

        def on_token(text_chunk: str | None) -> None:
            """stream_delta_callback → agent_text_delta."""
            nonlocal has_streamed_text, full_text
            if text_chunk is None or cancel_event.is_set():
                return
            has_streamed_text = True
            full_text += text_chunk
            self._partial_texts[sender_id] = full_text
            self._send_sync({
                "type": GatewayMessageType.AgentTextDelta,
                "message_id": msg_id,
                "delta": text_chunk,
                "account_id": self.config.account_id,
                "conversation_id": sender_id,
            })

        def on_reasoning(text_chunk: str | None) -> None:
            """reasoning_callback → agent_thinking_delta."""
            nonlocal has_streamed_thinking, reasoning_text
            if text_chunk is None or cancel_event.is_set():
                return
            has_streamed_thinking = True
            reasoning_text += str(text_chunk)
            self._send_sync({
                "type": GatewayMessageType.AgentThinkingDelta,
                "message_id": thinking_msg_id,
                "delta": str(text_chunk),
                "account_id": self.config.account_id,
                "conversation_id": sender_id,
            })

        def on_tool(*cb_args, **cb_kwargs) -> None:
            """tool_progress_callback → agent_tool_call / agent_tool_result."""
            nonlocal tool_call_counter, has_streamed_thinking
            if cancel_event.is_set():
                return

            # Parse variable-length callback arguments (same as WebUI)
            event_type = None
            name = None
            preview = None
            args = None

            if len(cb_args) >= 4:
                event_type, name, preview, args = cb_args[:4]
            elif len(cb_args) == 3:
                name, preview, args = cb_args
                event_type = "tool.started"
            elif len(cb_args) == 2:
                event_type, name = cb_args
            elif len(cb_args) == 1:
                name = cb_args[0]
                event_type = "tool.started"

            # Handle reasoning emitted via tool callback
            if event_type in ("reasoning.available", "_thinking"):
                reason_text = preview if event_type == "reasoning.available" else name
                if reason_text:
                    on_reasoning(str(reason_text))
                return

            if event_type in (None, "tool.started"):
                # Finalize previous thinking stream before tool card
                if has_streamed_thinking:
                    self._send_sync({
                        "type": GatewayMessageType.AgentThinkingDone,
                        "message_id": thinking_msg_id,
                        "account_id": self.config.account_id,
                        "conversation_id": sender_id,
                    })
                    has_streamed_thinking = False

                tool_call_counter += 1
                tool_call_id = f"{msg_id}_tool_{tool_call_counter}"
                tool_calls.append({
                    "name": name or "tool",
                    "id": tool_call_id,
                    "start_time": time.time(),
                })
                # Build compact args snapshot
                args_snap = {}
                if isinstance(args, dict):
                    for k, v in list(args.items())[:4]:
                        s = str(v)
                        args_snap[k] = s[:120] + ("..." if len(s) > 120 else "")

                self._send_sync({
                    "type": GatewayMessageType.AgentToolCall,
                    "message_id": msg_id,
                    "toolCallId": tool_call_id,
                    "toolName": name or "tool",
                    "toolTitle": str(preview or "")[:60],
                    "account_id": self.config.account_id,
                    "conversation_id": sender_id,
                })
                logger.info("🔧 Tool started: %s", name)

            elif event_type == "tool.completed":
                # Find matching tool call
                duration_ms = None
                tool_id = ""
                for tc in reversed(tool_calls):
                    if not tc.get("done") and (not name or tc["name"] == name):
                        tc["done"] = True
                        duration_ms = int((time.time() - tc["start_time"]) * 1000)
                        tool_id = tc["id"]
                        break

                self._send_sync({
                    "type": GatewayMessageType.AgentToolResult,
                    "message_id": msg_id,
                    "toolCallId": tool_id,
                    "toolName": name or "tool",
                    "durationMs": duration_ms,
                    "account_id": self.config.account_id,
                    "conversation_id": sender_id,
                })
                logger.info("🔧 Tool completed: %s (%sms)", name, duration_ms)

        # ── Send typing indicator ───────────────────────────────────────

        await self._send({
            "type": GatewayMessageType.AgentTyping,
            "account_id": self.config.account_id,
            "conversation_id": sender_id,
        })

        # ── Instantiate AIAgent and run (in thread) ─────────────────────

        AIAgent = _get_ai_agent()
        if AIAgent is None:
            await self._send({
                "type": GatewayMessageType.AgentText,
                "message_id": msg_id,
                "text": "⚠️ Hermes AIAgent not available. Check hermes-agent installation.",
                "account_id": self.config.account_id,
                "conversation_id": sender_id,
            })
            return

        session_db = _get_session_db()

        # Resolve model/provider (use config or Hermes defaults)
        resolved_model = self.config.model
        resolved_provider = self.config.provider
        resolved_base_url = self.config.base_url
        resolved_api_key = None

        try:
            from hermes_cli.runtime_provider import resolve_runtime_provider
            rt = resolve_runtime_provider(requested=resolved_provider or None)
            resolved_api_key = rt.get("api_key")
            if not resolved_provider:
                resolved_provider = rt.get("provider", "")
            if not resolved_model:
                resolved_model = rt.get("model", "")
            if not resolved_base_url:
                resolved_base_url = rt.get("base_url", "")
        except Exception as e:
            logger.warning("resolve_runtime_provider failed: %s", e)

        # Resolve toolsets
        toolsets = self.config.toolsets or None
        if not toolsets:
            try:
                from api.config import _resolve_cli_toolsets, get_config
                cfg = get_config()
                toolsets = _resolve_cli_toolsets(cfg)
            except Exception:
                toolsets = None

        # ── Clarify callback (blocking — waits for client response) ────

        def on_clarify(question, choices):
            """clarify_callback → clarify_request, blocks until response."""
            timeout = 120  # seconds
            choices_list = [str(c) for c in (choices or [])]

            # Push clarify_request to client
            self._send_sync({
                "type": GatewayMessageType.ClarifyRequest,
                "conversation_id": sender_id,
                "account_id": self.config.account_id,
                "question": str(question or ""),
                "choices": choices_list,
                "message_id": msg_id,
            })

            # Create pending entry with Event
            evt = threading.Event()
            self._pending_clarifies[sender_id] = {
                "event": evt, "result": None,
            }

            # Wait for response or timeout
            deadline = time.monotonic() + timeout
            while True:
                if cancel_event.is_set():
                    self._pending_clarifies.pop(sender_id, None)
                    return (
                        "The user did not provide a response within the time limit. "
                        "Use your best judgement to make the choice and proceed."
                    )
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    self._pending_clarifies.pop(sender_id, None)
                    return (
                        "The user did not provide a response within the time limit. "
                        "Use your best judgement to make the choice and proceed."
                    )
                if evt.wait(timeout=min(1.0, remaining)):
                    result = str(self._pending_clarifies.get(sender_id, {}).get("result", "")).strip()
                    self._pending_clarifies.pop(sender_id, None)
                    return (
                        result
                        or "The user did not provide a response within the time limit. "
                           "Use your best judgement to make the choice and proceed."
                    )

        def _run_agent():
            """Run AIAgent.run_conversation in a background thread."""
            nonlocal full_text

            # Register approval notify callback
            _unreg_approval = None
            try:
                from tools.approval import (
                    register_gateway_notify as _reg_approval,
                    unregister_gateway_notify as _unreg_approval_fn,
                )

                def _on_approval_notify(approval_data):
                    """Push approval request to client via WS."""
                    if cancel_event.is_set():
                        return
                    # Create pending entry
                    evt = threading.Event()
                    self._pending_approvals[sender_id] = {
                        "event": evt, "result": None,
                    }
                    self._send_sync({
                        "type": GatewayMessageType.ApprovalRequest,
                        "conversation_id": sender_id,
                        "account_id": self.config.account_id,
                        "message_id": msg_id,
                        "command": approval_data.get("command", ""),
                        "description": approval_data.get("description", ""),
                        "pattern_keys": approval_data.get("pattern_keys", []),
                    })

                _reg_approval(sender_id, _on_approval_notify)
                _unreg_approval = lambda: _unreg_approval_fn(sender_id)
            except ImportError:
                logger.debug("Approval module not available")

            try:
                agent = AIAgent(
                    model=resolved_model,
                    provider=resolved_provider,
                    base_url=resolved_base_url or None,
                    api_key=resolved_api_key,
                    platform="cli",
                    quiet_mode=True,
                    enabled_toolsets=toolsets,
                    session_id=sender_id,
                    session_db=session_db,
                    stream_delta_callback=on_token,
                    reasoning_callback=on_reasoning,
                    tool_progress_callback=on_tool,
                    clarify_callback=on_clarify,
                )

                # Store agent for abort access
                self._agents[sender_id] = agent

                # Check for pre-flight cancel
                if cancel_event.is_set():
                    return None

                result = agent.run_conversation(
                    user_message=text,
                    conversation_history=[],
                    task_id=sender_id,
                )
                return result

            except Exception as e:
                logger.error("AIAgent.run_conversation failed: %s", e, exc_info=True)
                return {"error": str(e)}
            finally:
                self._agents.pop(sender_id, None)
                self._pending_approvals.pop(sender_id, None)
                self._pending_clarifies.pop(sender_id, None)
                if _unreg_approval:
                    try:
                        _unreg_approval()
                    except Exception:
                        pass

        # Run in thread pool to avoid blocking the event loop
        loop = asyncio.get_event_loop()
        try:
            result = await loop.run_in_executor(None, _run_agent)
        except Exception as e:
            logger.error("Agent execution failed: %s", e)
            result = {"error": str(e)}

        # Clean up cancel event
        self._cancel_events.pop(sender_id, None)
        self._partial_texts.pop(sender_id, None)

        # ── Check for cancel during execution ───────────────────────────

        if cancel_event.is_set():
            logger.info("🚫 Agent cancelled for %s", sender_id)
            return

        # ── Finalize thinking stream (if still open) ────────────────────

        if has_streamed_thinking:
            await self._send({
                "type": GatewayMessageType.AgentThinkingDone,
                "message_id": thinking_msg_id,
                "account_id": self.config.account_id,
                "conversation_id": sender_id,
            })

        # ── Send completion ─────────────────────────────────────────────

        final_text = full_text
        if result and isinstance(result, dict):
            # Prefer final_response from result if available
            final_text = result.get("final_response", full_text) or full_text

        error = result.get("error") if isinstance(result, dict) else None

        if has_streamed_text:
            # Send remaining delta (if any) + done signal
            await self._send({
                "type": GatewayMessageType.AgentTextDone,
                "message_id": msg_id,
                "fullText": final_text,
                "account_id": self.config.account_id,
                "conversation_id": sender_id,
                "model": resolved_model,
                "provider": resolved_provider,
            })
            logger.info("📤 Reply done (stream): %s", final_text[:80])

        elif final_text.strip():
            # Non-streaming fallback
            await self._send({
                "type": GatewayMessageType.AgentText,
                "message_id": msg_id,
                "text": final_text,
                "account_id": self.config.account_id,
                "conversation_id": sender_id,
                "model": resolved_model,
                "provider": resolved_provider,
            })
            logger.info("📤 Reply done (full): %s", final_text[:80])

        else:
            # No reply generated — send error fallback
            error_text = (f"⚠️ 请求大模型接口失败：{error}" if error
                          else "⚠️ AI 未能生成回复，请重试。")
            await self._send({
                "type": GatewayMessageType.AgentText,
                "message_id": msg_id,
                "text": error_text,
                "account_id": self.config.account_id,
                "conversation_id": sender_id,
            })
            logger.warning("📤 No reply, sent fallback error")

        # ── Tool stats ──────────────────────────────────────────────────

        if tool_calls:
            await self._send({
                "type": GatewayMessageType.AgentTurnStats,
                "message_id": msg_id,
                "toolCallCount": len(tool_calls),
                "tools": [tc["name"] for tc in tool_calls],
                "account_id": self.config.account_id,
                "conversation_id": sender_id,
            })

    # ── Abort ────────────────────────────────────────────────────────────

    def _handle_abort(self, msg: dict) -> None:
        """Handle abort request: cancel event + agent.interrupt()."""
        sender_id = msg.get("conversation_id", "clawke_user")
        logger.info("📥 Abort request: conversation=%s", sender_id)

        # Set cancel event
        cancel = self._cancel_events.get(sender_id)
        if cancel:
            cancel.set()

        # Interrupt agent if running
        agent = self._agents.get(sender_id)
        if agent:
            try:
                agent.interrupt("Cancelled by user")
                logger.info("📥 agent.interrupt() called for %s", sender_id)
            except Exception as e:
                logger.warning("agent.interrupt() failed: %s", e)

    def _handle_approval_response(self, msg: dict) -> None:
        """Route approval_response from client to waiting thread."""
        sender_id = msg.get("conversation_id", "")
        choice = msg.get("choice", "once")  # once|session|always|deny
        pending = self._pending_approvals.get(sender_id)
        if pending:
            pending["result"] = choice
            pending["event"].set()
            logger.info("📥 Approval response: %s → %s", sender_id, choice)

            # Route to Hermes approval system
            try:
                from tools.approval import submit_response
                submit_response(sender_id, choice)
            except Exception as e:
                logger.debug("approval.submit_response failed: %s", e)
        else:
            logger.warning("📥 Approval response for unknown session: %s", sender_id)

    def _handle_clarify_response(self, msg: dict) -> None:
        """Route clarify_response from client to waiting on_clarify thread."""
        sender_id = msg.get("conversation_id", "")
        response_text = msg.get("response", "")
        pending = self._pending_clarifies.get(sender_id)
        if pending:
            pending["result"] = response_text
            pending["event"].set()
            logger.info("📥 Clarify response: %s → %s", sender_id, response_text[:40])
        else:
            logger.warning("📥 Clarify response for unknown session: %s", sender_id)

    # ── Query Handlers ───────────────────────────────────────────────────

    async def _handle_query_models(self) -> None:
        """Return available models from Hermes runtime."""
        models = []
        try:
            from hermes_cli.runtime_provider import resolve_runtime_provider
            rt = resolve_runtime_provider()
            model = rt.get("model", "")
            if model:
                models.append(model)
        except Exception:
            pass

        await self._send({
            "type": GatewayMessageType.ModelsResponse,
            "models": models,
        })
        logger.info("📤 Models response: %d models", len(models))

    async def _handle_query_skills(self) -> None:
        """Return available Hermes toolsets/skills."""
        skills = []
        try:
            hermes_home = Path(os.environ.get("HERMES_HOME", "~/.hermes")).expanduser()
            skills_dir = hermes_home / "skills"
            if skills_dir.is_dir():
                for entry in skills_dir.iterdir():
                    if not entry.is_dir():
                        continue
                    skill_md = entry / "SKILL.md"
                    if skill_md.exists():
                        content = skill_md.read_text(errors="ignore")
                        desc = entry.name
                        # Try to extract description from YAML frontmatter
                        import re
                        fm_match = re.search(r"^---\s*\n([\s\S]*?)\n---", content)
                        if fm_match:
                            desc_match = re.search(r"description:\s*(.+)", fm_match.group(1), re.I)
                            if desc_match:
                                desc = desc_match.group(1).strip()
                        skills.append({"name": entry.name, "description": desc})
        except Exception as e:
            logger.debug("Skills scan failed: %s", e)

        await self._send({
            "type": GatewayMessageType.SkillsResponse,
            "skills": skills,
        })
        logger.info("📤 Skills response: %d skills", len(skills))

    # ── WebSocket Send Helpers ───────────────────────────────────────────

    async def _send(self, data: dict) -> None:
        """Send JSON message to Clawke Server (async)."""
        if self._ws:
            try:
                await self._ws.send(json.dumps(data, ensure_ascii=False))
            except Exception as e:
                logger.error("Send failed: type=%s, error=%s", data.get("type"), e)
        else:
            logger.warning("WS not connected, dropping: type=%s", data.get("type"))

    def _send_sync(self, data: dict) -> None:
        """Send JSON message from a synchronous callback (thread-safe).

        Called from AIAgent callbacks which run in a background thread.
        Uses run_coroutine_threadsafe to schedule the send on the event loop.
        """
        if not self._ws or not self._loop:
            return
        try:
            future = asyncio.run_coroutine_threadsafe(
                self._send(data), self._loop
            )
            # Don't block waiting — fire and forget
            future.add_done_callback(
                lambda f: f.exception() and logger.debug("send_sync error: %s", f.exception())
            )
        except Exception as e:
            logger.debug("_send_sync scheduling failed: %s", e)
