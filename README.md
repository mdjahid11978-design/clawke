<p align="center">
  <strong>English</strong>
  ·
  <a href="README_zh.md">简体中文</a>
</p>

<h1 align="center">
  <img src="client/assets/images/logo.png" width="72" alt="Clawke" />
  <br />
  Clawke
</h1>

<h2 align="center">
Native Mobile Workspace for AI Agents
</h2>

<h4 align="center">
Manage OpenClaw, Hermes, Codex and Claude Code from your phone or desktop.
</h4>

<p align="center">
  🖥 <strong>Mac</strong>
  ·
  🪟 <strong>Windows</strong>
  ·
  🐧 <strong>Linux</strong>
  ·
  📱 <strong>iOS</strong>
  ·
  🤖 <strong>Android</strong>
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/readme-hero-dark.png">
  <source media="(prefers-color-scheme: light)" srcset=".github/readme-hero-light.png">
  <img width="1800" alt="Clawke native mobile workspace" src=".github/readme-hero-light.png">
</picture>

## Features

- **Cross-device collaboration** — Supports Mac, Windows, Linux, iOS, and Android, so you can keep working wherever you go
- **CUP Protocol** — Streaming AI responses with thinking blocks, tool calls, and usage tracking
- **SDUI** — Server-driven UI: dashboards, forms, dialogs rendered from server instructions
- **Multi-agent management** — Manage OpenClaw, Hermes, Nanobot, and other AI agents at the same time
- **Media** — Image/PDF/text file upload and inline rendering
- **Relay** — Built-in tunnel for remote access without port forwarding

## Step 1: Install Clawke Server

### Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/clawke/clawke/main/scripts/install.sh | bash
```

Works on macOS, Linux, and WSL2. The installer handles compiling the server, detecting your environment, and setting up the global CLI for you.

> **Windows:** Native Windows is not supported. Please install [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) and run the command above.


### Manual Install

Prerequisites: [Node.js](https://nodejs.org/) >= 18, [Flutter](https://flutter.dev/) >= 3.x (for client)

```bash
git clone https://github.com/clawke/clawke.git
cd clawke/server
npm install                           # Installs dependencies + compiles TypeScript
npx clawke gateway install             # Auto-detect and install gateway plugin
npx clawke server start                # Start Clawke Server
```

The server will:

1. Start WebSocket server on port 8765 (client) and 8766 (upstream)
2. Start HTTP/media server on port 8781

### Common Commands

```bash
clawke --version          # Show installed Clawke version
clawke doctor             # Check local Clawke setup and runtime status
clawke update             # Update Clawke to the latest version
clawke update --check     # Check for updates without installing
clawke gateway install    # Auto-detect and install gateway plugin
clawke server start       # Start Clawke Server
clawke server stop        # Stop Clawke Server
clawke server restart     # Restart Clawke Server
clawke server status      # Check server status
```

## Step 2: Download Client

- **iOS**: Download from the [App Store](https://apps.apple.com/us/app/clawke/id6760453431).
- **Android**: Download the APK directly from the [Releases](https://github.com/clawke/clawke/releases) page.
- **macOS / Windows / Linux**: Download compiled binaries from the [Releases](https://github.com/clawke/clawke/releases) page.

Alternatively, you can build it yourself from source:

```bash
cd client
flutter pub get
flutter build macos  # Or: ios, apk, windows, linux
```

> To run in debug mode, use `flutter run -d macos` (replace `macos` with your target platform).

## Project Structure

```
clawke/
├── client/              # Flutter app (iOS, macOS, Android)
├── server/              # Clawke Server (TypeScript/Node.js)
│   ├── src/             # Source code
│   ├── config/          # Config templates
│   └── test/            # Tests (42 cases)
├── gateways/            # Gateway plugins
│   ├── openclaw/clawke/ # OpenClaw gateway
│   └── hermes/clawke/   # Hermes gateway
└── relay-server/        # Relay server config
```

> 📖 For advanced configuration, see [CONFIGURATION.md](docs/CONFIGURATION.md).  
> 🔌 To build your own gateway, see [GATEWAY_INTEGRATION.md](docs/GATEWAY_INTEGRATION.md).

## Changelog

<!-- README_CHANGELOG_START -->
### v1.1.21 (2026-05-03)

**[Enhancement]** Stabilized runtime path handling and task UI E2E setup for release validation.
**[Architecture]** Renamed upstream listener boundaries to gateway listener and moved private planning docs out of public documentation.

### v1.1.20 (2026-05-02)

**[New Feature]** Added Hermes cron result sync with persistent task delivery tracking and retry handling.
**[Enhancement]** Improved task management delivery status, validation feedback, and gateway alerts.
**[Enhancement]** Updated Hermes media routing and per-session working directory isolation.

### v1.1.17 (2026-04-29)

**[New Feature]** Added `clawke doctor` runtime and gateway diagnostics.
**[Enhancement]** Clarified multi-agent online management across OpenClaw, Hermes, and mobile clients.
**[Bug Fix]** Fixed streamed reply recovery after disconnect so `Thinking`, tool state, and stop button no longer get stuck.

### v1.1.15 (2026-04-29)

**[New Feature]** Hermes gateway support.
**[New Feature]** Native Skills Center and task management pages.
**[Enhancement]** Gateway-backed model, skill, and translation refresh flows.
**[Bug Fix]** OpenClaw model routing and startup configuration fixes.
**[Architecture]** Expanded gateway and UI E2E regression coverage.

### v1.1.5 (2026-04-18)

**[New Feature]** One-click installation and unified CLI commands.  
**[New Feature]** AI typing status indicators.  
**[Enhancement]** Gateway pipeline optimizations.  
**[Bug Fix]** Comprehensive abort (stop generation) pipeline overhaul.  
**[Bug Fix]** Fixed concurrent message and delivery state issues.  

### v1.1.3 (2026-04-15)

**[New Feature]** Multi-session support with per-conversation AI configuration.  
**[New Feature]** Gateway selector for new conversations.  
**[Enhancement]** Complete internationalization (i18n) for all screens.  
**[Enhancement]** Desktop UI polish — unified AppBar styling and spacing.  
**[Bug Fix]** Fix cross-conversation message leakage.  
**[Bug Fix]** Fix port conflict detection on startup.  
**[Architecture]** Server-side conversation auto-creation.  
<!-- README_CHANGELOG_END -->

> [Full Changelog](docs/CHANGELOG.md)

## Contributing

1. Fork this repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

[MIT](LICENSE)
