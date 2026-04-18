# Hermes Gateway for Clawke

Connects [Hermes AI Agent](https://github.com/hermes-ai/hermes-agent) to Clawke Server, enabling Hermes's full AI capabilities (streaming, reasoning, tool calls, skills) through the Clawke client.

## Architecture

```
Flutter Client ←CUP/WS 8765→ Clawke Server ←WS 8766→ This Gateway → AIAgent → LLM
```

The gateway runs as a **standalone Python process** sharing the same Hermes Python environment — the same approach used by Hermes WebUI (`hermes webui`). It directly imports and calls `AIAgent` with zero IPC overhead.

## Prerequisites

- **Hermes** installed and configured (`pip install hermes-agent` or cloned repo)
- **Clawke Server** running with upstream port 8766 open
- **Python 3.11+**

## Installation

### Option 1: Auto-install via Clawke CLI

```bash
clawke gateway install --hermes
```

### Option 2: Manual

```bash
# Install dependencies
cd gateways/hermes/clawke
pip install -r requirements.txt

# Configure account in ~/.clawke/clawke.json
# (see Configuration section below)
```

## Usage

```bash
# Start the gateway
cd gateways/hermes/clawke
python3 run.py

# Or with custom server URL
CLAWKE_WS_URL=ws://your-server:8766 python3 run.py
```

## Configuration

### Via ~/.clawke/clawke.json

Add a `hermes` entry to the `accounts` section:

```json
{
  "accounts": {
    "hermes": {
      "url": "ws://127.0.0.1:8766",
      "account_id": "hermes",
      "model": "",
      "provider": "",
      "toolsets": []
    }
  }
}
```

| Field | Description | Default |
|-------|-------------|---------|
| `url` | Clawke Server upstream WebSocket URL | `ws://127.0.0.1:8766` |
| `account_id` | Account identifier for this gateway | `hermes` |
| `model` | LLM model name (empty = Hermes default) | `""` |
| `provider` | LLM provider (empty = Hermes default) | `""` |
| `toolsets` | Enabled Hermes toolsets | `[]` (all) |

### Via Environment Variables

| Variable | Description |
|----------|-------------|
| `CLAWKE_WS_URL` | Override WebSocket URL |
| `CLAWKE_ACCOUNT_ID` | Override account ID |
| `CLAWKE_MODEL` | Override model |
| `CLAWKE_PROVIDER` | Override provider |

## Features

| Feature | Status |
|---------|--------|
| Streaming text output | ✅ |
| Thinking/reasoning blocks | ✅ |
| Tool call tracking | ✅ |
| Abort/cancel | ✅ |
| Auto-reconnect (exponential backoff) | ✅ |
| Per-session serial execution | ✅ |
| Model/skills query | ✅ |
| Approval (command review) | 🔜 Phase 3 |
| Clarify (disambiguation) | 🔜 Phase 3 |
| Media file handling | 🔜 Phase 2 |

## Protocol

This gateway implements the CUP (Clawke Upstream Protocol) over WebSocket. See `docs/GATEWAY_INTEGRATION.md` for the full protocol specification.

### Callback Mapping

| Hermes AIAgent Callback | CUP Message Type |
|------------------------|------------------|
| `stream_delta_callback` | `agent_text_delta` |
| `reasoning_callback` | `agent_thinking_delta` / `agent_thinking_done` |
| `tool_progress_callback` (started) | `agent_tool_call` |
| `tool_progress_callback` (completed) | `agent_tool_result` |
| *(completion)* | `agent_text_done` |
