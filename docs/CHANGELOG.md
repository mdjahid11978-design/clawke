# Changelog

> Full version history of the Clawke project. The README shows only the latest month.

<!-- CHANGELOG_START -->

## v1.1.3 (2026-04-15)

**[New Feature]** Multi-session support with per-conversation AI configuration.
- Each conversation can now be configured with its own AI gateway, model, system prompt, and temperature
- New conversation settings panel accessible from the chat screen
- Server-side conversation config storage with REST API (`/api/conversations/:id/config`)
- Gateway-authoritative model and skill queries — available models are fetched directly from the connected AI backend

**[New Feature]** Gateway selector for new conversations.
- Card-style UI with guided text for choosing which AI backend to use
- Displays connected account IDs with visual indicators

**[Enhancement]** Complete internationalization (i18n) for all screens.
- Full English/Chinese localization for settings, password change, and edge-case pages
- Global AppBar title centering and consistent font sizing (18sp)

**[Enhancement]** Desktop UI polish.
- Conversation list header alignment and spacing adjustments
- Unified AppBar actions padding across all screens
- Conversation settings sheet with full-screen system prompt editor

**[Bug Fix]** Fix cross-conversation message leakage — thinking blocks and messages now correctly route by `conversation_id`.

**[Bug Fix]** Fix port conflict detection on startup to prevent multiple frpc instances from spawning.

**[Bug Fix]** Fix Android 11+ unable to open privacy policy and terms of service links.

**[Architecture]** Server-side conversation auto-creation — conversations are now created server-side when a new `account_id` is first seen, removing client-side race conditions.

<!-- CHANGELOG_END -->
