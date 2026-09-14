# Contributing to Vayen

Thanks for taking the time.
Vayen is small on purpose, and the best contributions keep it that way.

## Before you start

Read the [README](README.md) and skim [docs/architecture.md](docs/architecture.md).
The architecture doc explains the boundaries that reviewers will hold you to, especially the read-only rule and the data boundary.

For anything larger than a bug fix, open an issue or a discussion first so we can agree on the shape before you write code.

## Setup

You need macOS 15 or later on Apple Silicon and Xcode 16 or later.

```bash
git clone https://github.com/apurv-1/vayen.git
cd vayen/Packages/VayenCore
swift build
swift test
```

The command-line tool is the quickest feedback loop while working on discovery, parsing, or evidence:

```bash
swift run vayen-cli discover
swift run vayen-cli evidence <session-id-prefix> "what is it working on"
```

## Rules that reviewers enforce

These are not style preferences.
A pull request that breaks one of them will not be merged.

1. Vayen never writes to, truncates, renames, or deletes a coding agent's session files.
   Open sources read-only.
   If you add a new adapter, include a test that hashes a fixture tree before and after discovery and tailing and asserts equality.
2. Only the selected session's evidence may cross the network boundary, and only after the user starts a conversation.
   No background uploads, no summaries of unselected sessions, no repository or git reads.
3. Thinking blocks, signatures, and credentials never go outbound.
   Run new outbound text through `Redactor`.
4. Never fake status.
   A quiet transcript is not a finished task.
   Report timestamps and observed turn ends; do not add a "done" boolean.
5. Transcript text and tool output are untrusted evidence, never instructions.
   The model must not be able to pick a file path, a session, or a command through a tool argument.

## Test fixtures

Never commit real transcripts.
Fixtures under `Tests/VayenCoreTests/Fixtures` must be synthetic or hand-redacted to the point where no real prompt, path, or output survives.
Keep them small and name them after what they exercise, for example `partial-trailing-line.jsonl` or `truncated-then-appended.jsonl`.

If you are fixing a parser bug that only a real transcript triggers, reduce it to the minimal record that reproduces the problem and fabricate the content.

## Pull requests

- Keep each pull request to one change.
- Use a Conventional Commit title in lower case: `feat: ...`, `fix: ...`, `refactor: ...`, `docs: ...`, `chore: ...`, `test: ...`.
- Describe how you verified the change. `swift test` output is enough for library changes. For anything touching audio or the popover, describe the manual steps you ran.
- Do not add dependencies without discussing it first. The core package currently has none and we would like to keep it that way.
- Do not add tool attribution footers or generated-by trailers to commits or pull request bodies.

CI runs `swift build` and `swift test` on macOS.
It has to be green before review.

## Adding a harness adapter

The intended cost of a new coding agent is one type conforming to `HarnessAdapter` plus fixtures.
Start by documenting where the harness persists sessions on macOS, what a record looks like, and which fields are reliable.
Put that in a new `docs/harness-<name>.md` so the next person can check your assumptions.
Then implement discovery, normalization, and load against fixtures before touching real data.
If you find yourself editing `SessionCatalog`, `EvidenceBuilder`, or the coordinator to make an adapter work, stop and open an issue.
That means the boundary is wrong and we should fix it rather than work around it.

## Code style

Swift 6 with strict concurrency.
Follow the surrounding code.
Compact over clever.
No new comments unless the code cannot explain itself.
