# Contributing to Clawke

Thanks for your interest in contributing to Clawke.

Clawke is a native workspace for managing AI agents across mobile and desktop clients. Contributions should keep the project local-first, secure, and compatible with mobile and desktop platforms.

## How to Contribute

1. Fork the repository.
2. Create a feature branch.
3. Make a focused change.
4. Run the relevant tests.
5. Open a pull request with a clear description.

## Development Setup

### Server

```bash
cd server
npm install
npm test
```

### Client

```bash
cd client
flutter pub get
flutter test
```

## Pull Request Guidelines

- Keep changes scoped to one feature, fix, or documentation update.
- Include tests for core logic changes.
- Do not commit secrets, API keys, private logs, or local runtime files.
- For UI changes, include screenshots or a short description of the visible change.
- For protocol or gateway changes, document compatibility impact.

## Reporting Bugs

When filing a bug, include:

- Clawke version or commit hash.
- Platform and OS version.
- Steps to reproduce.
- Expected behavior.
- Actual behavior.
- Relevant logs with secrets removed.

## Code Style

- Prefer simple, focused changes.
- Follow the existing style of the file being changed.
- Keep client-side logic thin; server and gateways own business behavior.
- Gateway-specific behavior should stay in the gateway layer.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
