# Security policy

## Reporting a vulnerability

Please report security issues through [GitHub private vulnerability reporting](https://github.com/apurv-1/vayen/security/advisories/new).
Do not open a public issue for anything that could expose a user's transcripts, credentials, or audio.

You should get an acknowledgement within a few days.
Vayen is maintained part-time, so please allow reasonable time for a fix before public disclosure.

## What counts

Vayen's security promises are narrow and specific.
A report is in scope if it shows any of these can be broken:

- Vayen writing to, truncating, or deleting a coding agent's session files
- Evidence from an unselected session, another project root, or the user's repository reaching the network
- Thinking blocks, signatures, or credential-shaped strings leaving the machine unredacted
- A transcript or tool output steering the model into reading a path, choosing a session, or running a command
- Microphone capture or playback continuing after the popover is closed
- An API key ending up anywhere other than the macOS Keychain and the auth header to the configured voice provider

## Out of scope

- Retention or handling of data by Deepgram or the model provider you configure in your Deepgram account. Those are governed by your agreements with them.
- Vulnerabilities in Claude Code, Codex, or Cursor themselves.
- Issues that require a compromised local user account.

## Supported versions

There is no release yet.
Until there is, reports against `main` are welcome.
