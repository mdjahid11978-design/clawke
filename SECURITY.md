# Security Policy

## Supported Versions

Security fixes are handled on the latest released version of Clawke.

Please update to the latest release before reporting an issue, unless the vulnerability prevents updating or affects the update process itself.

## Reporting a Vulnerability

Please do not disclose security vulnerabilities in public issues, pull requests, or discussions.

Use GitHub's private vulnerability reporting for this repository if it is available. If private reporting is not available, open a public issue with only a minimal request for a private security contact. Do not include exploit details, secrets, tokens, private URLs, database contents, or reproduction payloads in the public issue.

Helpful information for a private report:

- Affected version or commit hash.
- Affected platform.
- Clear reproduction steps.
- Impact and expected attacker capability.
- Logs or screenshots with secrets removed.
- Suggested fix, if known.

## Scope

Security-sensitive areas include:

- Authentication and authorization.
- Gateway communication.
- Local server exposure.
- Relay and remote access behavior.
- File upload, media handling, and path validation.
- Client-side handling of secrets, tokens, local files, or sandboxed WebView content.

## Response Expectations

We will review valid reports, assess impact, and coordinate a fix before public disclosure when appropriate.

Please avoid testing against systems you do not own or do not have explicit permission to test.
