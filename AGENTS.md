# Vayen agent instructions

Vayen is a read-only macOS menu bar observer for local coding agent sessions.
Read README.md and planning/architecture.md before changing anything.

## Layout

- `Packages/VayenCore` holds all logic and is the only place tests live. Build and test with `swift build` and `swift test` from that directory.
- `Vayen/` and `Vayen.xcodeproj` are the thin SwiftUI app shell. No parsing, evidence, or provider code goes there.
- `planning/` is the decision record. Update `planning/decision-canvas.md` when a product decision changes; do not leave decisions only in chat.

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
