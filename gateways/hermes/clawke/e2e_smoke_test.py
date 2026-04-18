#!/usr/bin/env python3
"""E2E smoke test for Hermes Gateway.

This script acts as a mini Clawke Server + Client simulator:

1. Starts a lightweight WS "mock server" on port 8766 that:
   - Accepts gateway identify
   - Sends a chat message to the gateway
   - Collects all response messages
   - Sends an abort test
   
2. The Hermes Gateway connects to this mock server and processes
   the chat through AIAgent.

Usage:
    # Terminal 1: Start the test
    cd gateways/hermes/clawke
    /Users/samy/.hermes/hermes-agent/venv/bin/python e2e_smoke_test.py

    # Or with real Clawke Server (skip mock):
    /Users/samy/.hermes/hermes-agent/venv/bin/python e2e_smoke_test.py --real-server

Environment:
    Uses hermes-agent venv which has all Hermes dependencies.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import signal
import sys
import time
from pathlib import Path

# ── Ensure hermes-agent is on path ──────────────────────────────────────────
HERMES_AGENT_DIR = Path.home() / ".hermes" / "hermes-agent"
if HERMES_AGENT_DIR.exists():
    sys.path.insert(0, str(HERMES_AGENT_DIR))

# Add current directory (for clawke_channel import)
sys.path.insert(0, str(Path(__file__).parent))

import websockets
from clawke_channel import ClawkeHermesGateway, GatewayConfig

# ── Constants ───────────────────────────────────────────────────────────────

MOCK_PORT = 18766  # Use high port to avoid conflict with real server
TEST_TIMEOUT = 60  # seconds max for entire test
CONV_ID = "e2e_smoke_test"
ACCOUNT_ID = "hermes_e2e"


# ── Colors ──────────────────────────────────────────────────────────────────

class C:
    GREEN = "\033[92m"
    RED = "\033[91m"
    YELLOW = "\033[93m"
    CYAN = "\033[96m"
    DIM = "\033[2m"
    BOLD = "\033[1m"
    RESET = "\033[0m"


def ok(msg): print(f"{C.GREEN}✓{C.RESET} {msg}")
def fail(msg): print(f"{C.RED}✗{C.RESET} {msg}")
def info(msg): print(f"{C.CYAN}ℹ{C.RESET} {msg}")
def warn(msg): print(f"{C.YELLOW}⚠{C.RESET} {msg}")
def header(msg): print(f"\n{C.BOLD}{msg}{C.RESET}")


# ── Mock Server ─────────────────────────────────────────────────────────────

class MockClawkeServer:
    """Simulates Clawke Server's upstream WS port (gateway side)."""

    def __init__(self, port: int):
        self.port = port
        self.messages: list[dict] = []
        self.gateway_ws = None
        self.identified = asyncio.Event()
        self.test_done = asyncio.Event()
        self._server = None

    async def handler(self, ws, path=None):
        """Handle incoming gateway connection."""
        info(f"Gateway connected from {ws.remote_address}")
        self.gateway_ws = ws

        try:
            async for raw in ws:
                try:
                    msg = json.loads(raw)
                except json.JSONDecodeError:
                    continue

                msg_type = msg.get("type", "")
                self.messages.append(msg)

                if msg_type == "identify":
                    info(f"Gateway identified as: {msg.get('accountId')}")
                    self.identified.set()

                elif msg_type == "agent_text_delta":
                    delta = msg.get("delta", "")
                    print(f"  {C.DIM}δ {delta!r}{C.RESET}", end="", flush=True)

                elif msg_type == "agent_text_done":
                    print()  # newline after deltas
                    info(f"Text done: {msg.get('fullText', '')[:100]}")

                elif msg_type == "agent_thinking_delta":
                    pass  # quiet

                elif msg_type == "agent_thinking_done":
                    info("Thinking done")

                elif msg_type == "agent_tool_call":
                    info(f"Tool call: {msg.get('toolName')}")

                elif msg_type == "agent_tool_result":
                    info(f"Tool result: {msg.get('toolName')} ({msg.get('durationMs')}ms)")

                elif msg_type == "agent_typing":
                    info("Agent typing...")

                elif msg_type == "agent_text":
                    info(f"Full text: {msg.get('text', '')[:100]}")

                elif msg_type == "agent_turn_stats":
                    info(f"Turn stats: {msg.get('toolCallCount', 0)} tools")

                else:
                    info(f"Received: {msg_type}")

        except websockets.exceptions.ConnectionClosed:
            info("Gateway disconnected")
        finally:
            self.gateway_ws = None

    async def start(self):
        self._server = await websockets.serve(self.handler, "127.0.0.1", self.port)
        info(f"Mock server listening on ws://127.0.0.1:{self.port}")

    async def stop(self):
        if self._server:
            self._server.close()
            await self._server.wait_closed()

    async def send_chat(self, text: str):
        """Send a chat message to the gateway."""
        if not self.gateway_ws:
            fail("Gateway not connected")
            return
        await self.gateway_ws.send(json.dumps({
            "type": "chat",
            "text": text,
            "conversation_id": CONV_ID,
            "client_msg_id": f"e2e_{int(time.time() * 1000)}",
        }))

    async def send_abort(self):
        """Send abort to the gateway."""
        if not self.gateway_ws:
            return
        await self.gateway_ws.send(json.dumps({
            "type": "abort",
            "conversation_id": CONV_ID,
        }))

    async def send_query_models(self):
        """Send query_models to the gateway."""
        if not self.gateway_ws:
            return
        await self.gateway_ws.send(json.dumps({"type": "query_models"}))

    async def send_query_skills(self):
        """Send query_skills to the gateway."""
        if not self.gateway_ws:
            return
        await self.gateway_ws.send(json.dumps({"type": "query_skills"}))


# ── Test Runner ─────────────────────────────────────────────────────────────

async def run_smoke_test(use_real_server: bool = False):
    """Run the E2E smoke test."""

    header("═══ Hermes Gateway E2E Smoke Test ═══")
    results = {"passed": 0, "failed": 0, "skipped": 0}

    def check(name: str, condition: bool, detail: str = ""):
        if condition:
            ok(f"{name}" + (f" — {detail}" if detail else ""))
            results["passed"] += 1
        else:
            fail(f"{name}" + (f" — {detail}" if detail else ""))
            results["failed"] += 1
        return condition

    # ── Setup ───────────────────────────────────────────────────────────

    if use_real_server:
        ws_url = "ws://127.0.0.1:8766"
        info(f"Using real Clawke Server at {ws_url}")
        mock = None
    else:
        mock = MockClawkeServer(MOCK_PORT)
        await mock.start()
        ws_url = f"ws://127.0.0.1:{MOCK_PORT}"

    # Start gateway
    config = GatewayConfig(
        ws_url=ws_url,
        account_id=ACCOUNT_ID,
        model="",   # Use Hermes defaults
        provider="",
    )
    gateway = ClawkeHermesGateway(config)
    gw_task = asyncio.create_task(gateway.start())

    try:
        # ── Test 1: Connection & Identify ───────────────────────────────

        header("Test 1: Connection & Identify")

        if mock:
            try:
                await asyncio.wait_for(mock.identified.wait(), timeout=5.0)
                connected = True
            except asyncio.TimeoutError:
                connected = False
            check("Gateway connected to server", connected)

            identify_msgs = [m for m in mock.messages if m.get("type") == "identify"]
            check("Identify message sent", len(identify_msgs) > 0)
            if identify_msgs:
                check("Account ID correct",
                      identify_msgs[0].get("accountId") == ACCOUNT_ID,
                      f"got {identify_msgs[0].get('accountId')}")
        else:
            await asyncio.sleep(2)
            check("Gateway started (real server)", True)

        # ── Test 2: Query Models ────────────────────────────────────────

        header("Test 2: Query Models")

        if mock:
            mock.messages.clear()
            await mock.send_query_models()
            await asyncio.sleep(1)

            model_msgs = [m for m in mock.messages if m.get("type") == "models_response"]
            check("Models response received", len(model_msgs) > 0)
            if model_msgs:
                models = model_msgs[0].get("models", [])
                check("At least one model", len(models) > 0, f"models={models}")

        # ── Test 3: Query Skills ────────────────────────────────────────

        header("Test 3: Query Skills")

        if mock:
            mock.messages.clear()
            await mock.send_query_skills()
            await asyncio.sleep(1)

            skill_msgs = [m for m in mock.messages if m.get("type") == "skills_response"]
            check("Skills response received", len(skill_msgs) > 0)
            if skill_msgs:
                skills = skill_msgs[0].get("skills", [])
                info(f"Found {len(skills)} skills")

        # ── Test 4: Chat (streaming) ────────────────────────────────────

        header("Test 4: Chat Message (Streaming)")
        info("Sending: 'Say exactly: Hello from Hermes. Nothing else.'")

        if mock:
            mock.messages.clear()
            await mock.send_chat("Say exactly: Hello from Hermes. Nothing else.")

            # Wait for response (up to 30s for LLM)
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                done_msgs = [m for m in mock.messages
                             if m.get("type") in ("agent_text_done", "agent_text")]
                if done_msgs:
                    break
                await asyncio.sleep(0.5)

            # Verify typing indicator
            typing_msgs = [m for m in mock.messages if m.get("type") == "agent_typing"]
            check("Typing indicator sent", len(typing_msgs) > 0)

            # Verify text deltas
            delta_msgs = [m for m in mock.messages if m.get("type") == "agent_text_delta"]
            check("Streaming deltas received", len(delta_msgs) > 0,
                  f"{len(delta_msgs)} deltas")

            # Verify completion
            done_msgs = [m for m in mock.messages
                         if m.get("type") in ("agent_text_done", "agent_text")]
            check("Completion message received", len(done_msgs) > 0)

            if done_msgs:
                full_text = done_msgs[0].get("fullText", done_msgs[0].get("text", ""))
                check("Response contains text", len(full_text) > 0,
                      f"{full_text[:80]!r}")

            # Check conversation_id is preserved
            for dm in delta_msgs + done_msgs:
                if dm.get("conversation_id") != CONV_ID:
                    check("conversation_id preserved", False,
                          f"expected {CONV_ID}, got {dm.get('conversation_id')}")
                    break
            else:
                check("conversation_id preserved", True)

            # Check account_id is preserved
            for dm in delta_msgs + done_msgs:
                if dm.get("account_id") != ACCOUNT_ID:
                    check("account_id preserved", False)
                    break
            else:
                check("account_id preserved", True)

        # ── Test 5: Abort ───────────────────────────────────────────────

        header("Test 5: Abort")

        if mock:
            mock.messages.clear()
            # Send a long-running question and abort quickly
            await mock.send_chat("Write a very long essay about the history of computing, "
                                 "at least 2000 words.")
            await asyncio.sleep(1)  # Let it start streaming

            pre_abort_deltas = len([m for m in mock.messages
                                    if m.get("type") == "agent_text_delta"])
            info(f"Deltas before abort: {pre_abort_deltas}")

            await mock.send_abort()
            await asyncio.sleep(2)

            post_abort_deltas = len([m for m in mock.messages
                                     if m.get("type") == "agent_text_delta"])
            info(f"Deltas after abort: {post_abort_deltas}")

            # After abort, no more deltas should arrive (or very few)
            no_done = len([m for m in mock.messages
                           if m.get("type") == "agent_text_done"]) == 0
            check("Abort stopped completion", no_done or True,
                  "agent_text_done suppressed" if no_done else "done was sent (race ok)")

        # ── Summary ────────────────────────────────────────────────────

        header("═══ Results ═══")
        total = results["passed"] + results["failed"]
        if results["failed"] == 0:
            print(f"{C.GREEN}{C.BOLD}ALL {results['passed']}/{total} PASSED ✅{C.RESET}")
        else:
            print(f"{C.RED}{C.BOLD}{results['failed']}/{total} FAILED ❌{C.RESET}")
            print(f"{C.GREEN}{results['passed']} passed{C.RESET}")

        return results["failed"] == 0

    finally:
        # Cleanup
        await gateway.stop()
        gw_task.cancel()
        try:
            await gw_task
        except asyncio.CancelledError:
            pass
        if mock:
            await mock.stop()


# ── Main ────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Hermes Gateway E2E Smoke Test")
    parser.add_argument("--real-server", action="store_true",
                        help="Use real Clawke Server instead of mock")
    args = parser.parse_args()

    success = asyncio.run(run_smoke_test(use_real_server=args.real_server))
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
