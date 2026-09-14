# Vayen session evidence research

Verified on 2026-09-14 against this Mac and fetched vendor documentation.
This is planning evidence, not a compatibility guarantee or an implemented adapter.
No private prompt, transcript text, credential, repository name, or session identifier is reproduced here.
Local inspection opened transcript files for reading and SQLite connections in read-only, query-only mode.
No private transcript was uploaded to an external service.

## Decision

Build only the Claude Code adapter for milestone 1.
Local files provide enough evidence to discover real sessions and explain their recorded work.
They do not provide a trustworthy universal running/finished flag.
Use honest activity labels and preserve the evidence timestamp.
Keep Claude-specific JSON decoding behind an adapter boundary.
The confirmed beta scope is a neutral explainer inside the menu popover, using transcript evidence only.
Do not scan repositories or read git diffs, commits, or working-tree files for beta answers.

## Environment observed

| Harness | Installed version | Local persistence observed | Scope of verification |
| --- | --- | --- | --- |
| Claude Code | 2.1.267 | 175 JSONL files under `~/.claude/projects/`, including 56 direct project session files and 31 nested subagent files. | Keys and content-block types from ten recent files, followed by eight direct main-session files. |
| Codex | `codex-cli 0.154.0-alpha.6.2` bundled with the installed ChatGPT app. | 59 JSONL rollout files under `~/.codex/sessions/`. | Record types and payload keys from bounded portions of three recent files. |
| Cursor | 3.18.9 from the application plist. | 514 JSONL files under `~/.cursor/projects/*/agent-transcripts/`, plus workspace and global SQLite state. | Structure from two recent transcript files and schema/key-prefix counts from one workspace database and the global database. |

Counts are a point-in-time inventory and include auxiliary files, so they are not UI session counts.
The sampled Claude files contain records written by several CLI versions, including 2.1.197, 2.1.259, 2.1.260, 2.1.263, and 2.1.267.
Installing one current CLI version does not make every stored transcript use that version's format.
The Codex version command emitted a sandbox warning about creating PATH aliases but still returned its version.
No session was started or resumed as part of this inspection.

## Claude Code discovery

The documented default is `~/.claude/projects/<project>/<session-id>.jsonl`.
`CLAUDE_CONFIG_DIR` moves the root.
Persistence can be disabled, and old files can be cleaned up after the configured retention period.
A missing transcript therefore does not prove that no agent is running. [Claude session documentation](https://code.claude.com/docs/en/sessions)

The current Agent SDK documents `listSessions()` and `getSessionMessages()` as read helpers.
Project directory encoding can involve truncation, hashing, or `CLAUDE_CODE_PROJECT_DIR_NAME`.
Do not reverse an encoded folder name to recover the project path; prefer the record's `cwd`.
An SDK-read-helper spike is a useful compatibility reference even if the app uses a native Swift decoder. [Agent SDK sessions](https://code.claude.com/docs/en/agent-sdk/sessions)

The initial scan should enumerate main JSONLs directly below each project directory.
Nested subagent files are evidence attached to their parent, not automatically separate cards in the menu.
Other nested JSONLs must be classified before counting them as sessions.
Use `(harness, configuredSourceRoot, sessionId)` as source identity, and retain transcript file identity separately.
Do not collapse sessions merely because they share a repository or worktree.
A Finder-launched app may not inherit terminal environment variables, so provide a source-root setting when the default root is insufficient.

## Minimum Claude fields

These are locally observed keys, not a promised public schema.
Unknown record kinds and missing optional fields must be tolerated.

| Normalized concept | Observed source | Interpretation |
| --- | --- | --- |
| Session identifier | `sessionId` on message records. | Cross-check the filename; do not silently merge conflicting identities. |
| Working directory | `cwd` on user/assistant records. | Preserve per-event values if the working directory changes. |
| Observed start | Earliest valid message `timestamp`. | Label internally as first observed; imported or truncated history may omit the true start. |
| Latest evidence | Latest valid event `timestamp`, plus file modification time. | Keep these separate because metadata writes need not mean coding activity. |
| Message identity and lineage | `uuid`, `parentUuid`. | Needed for duplicates, branches, and compacted history. |
| Author and body | Record `type`, `message.role`, `message.content`. | User bodies can be strings or typed blocks. |
| Tool invocation | `tool_use` block with `id`, `name`, `input`. | Records intent to invoke a tool, not proof that it succeeded. |
| Tool result | `tool_result` block with `tool_use_id`, `content`, optional `is_error`. | Join to the invocation; retain missing and failed outcomes explicitly. |
| Title | `custom-title.customTitle`, `ai-title.aiTitle`, optional `slug`. | Prefer a user title; generated title is a display hint, not original task evidence. |
| Version | `version` on message records. | Track mixed-version files and report unsupported structures. |
| Subagent/metadata flags | `isSidechain`, `agentId`, `isMeta`, `isCompactSummary`. | Helps avoid presenting injected context or compact summaries as a new human request. |

Also observed: `attachment`, `queue-operation`, `last-prompt`, `system`, `file-history-snapshot`, `mode`, `permission-mode`, `cost-state`, and additional metadata kinds.
The decoder should preserve unsupported-event provenance locally while excluding irrelevant metadata from model context.
The sampled typed message blocks include `text`, `tool_use`, `tool_result`, `image`, and `thinking`.
Do not transmit thinking blocks, signatures, or opaque reasoning material in the MVP context packet.
Ground explanations of decisions in visible assistant statements, actual tool actions, and results.

Extract an original prompt only after distinguishing a direct human request from a tool result, injected metadata, and a compact summary.
Keep its evidence reference and a nullable value rather than inventing a task when the original request is absent.
A compacted or forked session needs a current-branch view plus preserved references to earlier evidence.
`parentUuid` is a lineage input, not by itself a fully validated reconstruction algorithm.

Large tool outputs may live beside the JSONL in `tool-results/`, and pre-edit file snapshots exist separately.
These files can contain sensitive source and command output. [Claude directory documentation](https://code.claude.com/docs/en/claude-directory)
Treat transcript-owned tool-result sidecars as a separately gated evidence capability; beta support must be explicitly decided before reading them.
If enabled, only resolve a needed sidecar within the explicitly selected session's allowed directory, accounting for symlinks.
Do not indiscriminately ingest debug logs, credential files, or all repository contents.

## Status and live updates

The direct main-session sample contained assistant `stop_reason` values of `tool_use` and `end_turn`.
It also contained system subtypes `stop_hook_summary`, `compact_boundary`, `turn_duration`, and `informational`.
An `end_turn` marker means a recorded assistant turn ended; it does not prove the requested work succeeded, the process exited, or the session will never resume.

| Evidence | Safe UI claim | Claim it cannot establish |
| --- | --- | --- |
| Newly parsed conversational or tool event. | Updated just now. | The agent is still executing now. |
| Recent file modification without a semantic event. | Source changed. | Coding progress occurred. |
| Recorded assistant turn end. | Last response completed. | Task finished successfully. |
| No new events for a while. | Last updated N minutes ago. | Idle, blocked, or exited. |
| A process name matching Claude. | A Claude process exists. | Which session it owns or whether it is working. |
| A verified process-to-transcript association. | Process present for this session. | Task correctness or absence of permission waits. |

Start with `Recently updated` and `Last updated` wording rather than a green `Working` indicator backed only by mtime.
Represent activity evidence as a source, observation timestamp, and confidence separately from any product label.
Process inspection and PID association remain an experiment; no live process correlation was established in this research.
Do not collect or log full process command lines, which may contain user prompts.

Claude hooks document session lifecycle events and a transcript path, including `SessionEnd` and subagent transcript locations. [Hooks reference](https://code.claude.com/docs/en/hooks)
Hooks are a possible later opt-in source of stronger lifecycle evidence.
Installing hooks would change harness configuration, so they are not part of the default read-only observer architecture.

Use a filesystem event stream as an invalidation signal, then reconcile changed files.
Tail from a stored byte offset and retain an incomplete final line until its terminating newline arrives.
Track file identity, size, and modification time so replacement or truncation triggers a bounded reparse.
Debounce bursts, coalesce changes, and reconcile on app activation or wake to recover missed notifications.
This is an implementation recommendation; filesystem latency and Claude write behavior were not benchmarked here.
Freeze a context revision for each spoken answer so a mid-answer update cannot silently change its evidentiary basis.
Incorporate newly parsed records at the next conversational turn and make freshness inspectable.

## Context size and grounding implications

The Claude inventory's median raw JSONL size was 190,030 bytes and its maximum was 8,314,537 bytes.
Seven files exceeded 1 MiB.
These raw-byte measurements are not token counts, and include auxiliary transcripts.
They establish that blindly submitting the entire selected raw file is not a robust default.

Normalize first, omit duplicated and irrelevant metadata, and use the full relevant transcript when it fits the chosen model budget.
For larger sessions, build a compact evidence ledger with stable references and expand only the material needed for the question.
Do not require an embedding database to prove milestone 1.
Surface missing original prompts, unavailable sidecars, stale snapshots, truncation, and unobserved test outcomes as evidence gaps.
Repository and git evidence are explicitly deferred beyond the confirmed transcript-only beta.
If considered later, a git diff would establish repository state, not attribution to one concurrent agent.

## Codex feasibility, deferred

The official configuration documentation places local state under `CODEX_HOME`, defaulting to `~/.codex`. [Codex advanced configuration](https://learn.chatgpt.com/docs/config-file/config-advanced)
Local rollout inspection found envelopes with `type` and `payload`.
Observed types included `session_meta`, `response_item`, `event_msg`, `turn_context`, `world_state`, and token/agent metadata.
`session_meta` contains `id`, `cwd`, `timestamp`, `cli_version`, and source/parent metadata in the sampled files.
`response_item` supports role/content records and call identifiers, function names, arguments, and outputs.
Do not infer the full transcript format from the separate `history.jsonl` file.
Do not expose `base_instructions`, encrypted content, or unrelated internal metadata by default.

Official app-server documentation offers `thread/read` without resuming and `thread/list` for stored history.
It also says listing defaults can scan and repair metadata, and runtime status includes `notLoaded`.
Consequently, an app-server adapter requires a strict no-mutation and cross-process-status spike before adoption; starting a second server is not automatically a passive observation of an already-running CLI. [Codex app-server documentation](https://learn.chatgpt.com/docs/app-server)
Prefer planning for a read-only rollout adapter initially, then compare its maintenance burden with a verified safe API route when Codex enters scope.

## Cursor feasibility, deferred

The current installed version has both transcript files and databases.
The two sampled JSONL files have top-level `message`, `role`, `status`, and `type`, with `message.content` blocks containing `text` and `tool_use`.
This small sample does not establish timestamps, project identity, complete tool results, or robust live-session status.
The observed generic transcript location is `~/.cursor/projects/<project>/agent-transcripts/**/*.jsonl`.

Observed macOS database locations are `~/Library/Application Support/Cursor/User/workspaceStorage/<workspace>/state.vscdb` and `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`.
Both inspected databases expose `ItemTable`, `cursorDiskKV`, and `composerHeaders` tables.
The global `cursorDiskKV` contains `composerData:*`, `bubbleId:*`, and `agentKv:*` key families.
The inspected workspace `cursorDiskKV` was empty, so workspace SQLite alone would miss relevant data on this installation.
No private database values were emitted or copied.

The previously published chat-history documentation URL now redirects to the agent overview and does not establish the local schema. [Fetched Cursor documentation](https://cursor.com/docs/agent/overview)
Treat the local findings as version-scoped observations, and defer a compatibility contract until a dedicated spike.
If SQLite is needed later, use read-only connections, handle WAL consistency, avoid repair/checkpoint/write operations, and verify whether transcript-only ingestion meets the actual product needs first.

## Implementation spikes required before claiming milestone 1

1. Start a disposable real Claude session and compare the visible original request, tool invocation, result, assistant reply, and adapter output without altering source files.
2. Verify discovery from a Finder-launched app, nondefault source roots, worktrees, long encoded paths, persistence disabled, and missing directory permissions.
3. Exercise partial JSONL writes, repeated events, compacted history, forks, resumed sessions, subagents, missing sidecars, and file replacement.
4. Demonstrate that `end_turn`, permission waits, cancellation, and process exit are not misrepresented as task completion.
5. Measure source-write-to-visible-update delay and end-of-question-to-first-audio latency with recorded conditions.
6. Inspect a selected context packet locally and prove that unrelated sessions and hidden reasoning material are absent.
7. Ask contradictory and unsupported questions and confirm the answer names the evidence gap instead of guessing.

No demo, adapter, filesystem watcher, process mapper, or voice integration was implemented by this research.
