[中文文档](CONFIGURATION_zh.md)

# Advanced Configuration & Development

This document covers server configuration, Mock Mode for offline development, and testing.

## Configuration

Server config is stored at `~/.clawke/clawke.json`, auto-created from template on first run.

```json
{
  "server": {
    "mode": "openclaw",
    "clientPort": 8765,
    "upstreamPort": 8766,
    "mediaPort": 8781,
    "fastMode": false,
    "logLevel": "info"
  },
  "openclaw": {
    "sharedFs": false,
    "mediaBaseUrl": "http://127.0.0.1:8781"
  },
  "relay": {
    "enable": true,
    "serverAddr": "relay.clawke.ai",
    "serverPort": 7000
  }
}
```

| Field | Description | Default |
|-------|-------------|---------|
| `server.mode` | `openclaw` (production) or `mock` (offline dev) | `openclaw` |
| `server.clientPort` | WebSocket port for Flutter client | `8765` |
| `server.upstreamPort` | WebSocket port for OpenClaw gateway | `8766` |
| `server.mediaPort` | HTTP port for media/file serving | `8781` |
| `server.fastMode` | Skip thinking blocks for faster responses | `false` |
| `server.logLevel` | Log verbosity: `debug`, `info`, `warn`, `error` | `info` |
| `openclaw.sharedFs` | Whether server and OpenClaw share filesystem | `false` |
| `openclaw.mediaBaseUrl` | Base URL for media file access | `http://127.0.0.1:8781` |
| `relay.enable` | Enable built-in relay tunnel | `true` |
| `relay.serverAddr` | Relay server address | `relay.clawke.ai` |
| `relay.serverPort` | Relay server port | `7000` |

### Environment Variables

| Variable | Description |
|----------|-------------|
| `MODE` | Override server mode (`mock` for offline development) |
| `CLAWKE_DATA_DIR` | Override data directory (default: `~/.clawke/`) |

## Mock Mode

Run the server without an AI provider. Useful for client UI development and testing.

```bash
cd server
MODE=mock npm start
```

Mock mode simulates:
- Streaming AI text responses
- Thinking blocks
- Tool calls
- File upload handling

## Testing

```bash
cd server
npm test                 # Run all 42 test cases
```

Test coverage includes:
- CUP v2 protocol encoding/decoding
- Authentication middleware
- Media upload and resolution
- TypeScript integration verification

## iOS / macOS Build

1. Copy `client/ios/ExportOptions.plist.example` to `client/ios/ExportOptions.plist`
2. Replace `YOUR_TEAM_ID` with your Apple Developer Team ID
3. For Android, copy `client/android/key.properties.example` to `client/android/key.properties`

## Data Directory

All runtime data lives in `~/.clawke/` (overridable via `CLAWKE_DATA_DIR`):

```
~/.clawke/
├── clawke.json            # User config
├── data/clawke.db         # SQLite database
├── uploads/               # User-uploaded files
├── bin/                   # frpc binary (auto-downloaded)
├── frpc.toml              # Auto-generated relay config
└── frpc.pid               # frpc process PID
```
