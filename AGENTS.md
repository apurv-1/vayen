# Vayen agent instructions

Vayen is a read-only macOS menu bar observer for local coding agent sessions.
Read README.md and docs/architecture.md before changing anything.

## Layout

- The root Swift package (`Package.swift`, `Sources/`, `Tests/`) holds all logic and is the only place tests live. Build and test with `swift build` and `swift test` from the repo root.
- `Vayen/` and `Vayen.xcodeproj` are the thin SwiftUI app shell. No parsing, evidence, or provider code goes there.
- `docs/` holds the public architecture notes. Update `docs/architecture.md` when a boundary or data flow changes; it must describe the code, not the plan.

## Hard rules

- Never open a session source for writing. Read-only handles only.
- Never send unselected sessions, repository contents, thinking blocks, or credentials outbound.
- Never add a "finished" or "done" status. Report timestamps and observed turn ends.
- Never let model tool arguments select a file path, a session, or a command.
- Never commit real transcript content. Fixtures are synthetic.
- Never write to `~/.claude` during tests. Use a temporary directory.

## Working style

- Verify with `swift build` and `swift test`, then targeted CLI runs against real local sessions (read-only). Do not open a browser or take screenshots unless asked.
- Prefer removing code to adding it. Do not add dependencies without an issue.
- Conventional Commit messages, lower-case subject. No agent co-author trailers or tool attribution footers.
- No em dashes in prose or comments. Use a plain dash.
- Do not add comments or docs files explaining a change; put the reasoning in the pull request.
