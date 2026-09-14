## What and why

<!-- One or two sentences. Link the issue if there is one. -->

## How

<!-- Approach, and alternatives you ruled out. -->

## Verification

<!-- swift test output, CLI runs, manual steps for audio or popover work. -->

- [ ] `swift build` and `swift test` pass at the repo root
- [ ] No session source is opened for writing
- [ ] No new outbound data path without going through `Redactor` and the selected-session boundary
- [ ] Fixtures are synthetic; no real transcript content
- [ ] Title is a lower-case Conventional Commit
