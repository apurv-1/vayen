# Vayen product and design brief

This is a planning brief that distinguishes confirmed direction from proposed details.
The user has fixed the brand name, Mac-only starting point, premium feel, and planning-only scope for this stage.
The user has also confirmed a quiet native Mac utility, the best Mac feel, acceptance of Swift, and a developer beta using users' own API keys.
The user has confirmed that all Vayen interface content stays inside the menu popover, that first-beta answers use transcripts only, and that Vayen explains neutrally without judging the agent's work.
The supplied product brief fixes voice-first observation, ElevenLabs as the voice layer, automatic discovery, read-only source files, and a Claude Code first milestone.
Detailed visual tokens and interaction choices below remain proposed until the user confirms or replaces them.

## Product promise

Get back into the context of a coding session in one conversation.
Vayen observes an existing session and explains what the available evidence supports.
The first beta describes recorded actions, reported rationale, results, and uncertainty without independently assessing code quality or recommending a review verdict.
The first experience should answer “Bro, what are you doing?” without transcript copying, project setup, or a tour of a dashboard.
“Premium” should mean excellent typography, immediate orientation, quiet motion, reliable interaction, and honest answers.
Visual ornament should earn its place by making the session or the conversation easier to understand.

## Confirmed direction and small visual explorations

| Direction | Character | Treatment | Principal tradeoff |
| --- | --- | --- | --- |
| Quiet instrument, confirmed direction | Precise, understated, unmistakably at home on a Mac. | System typography, warm neutral surfaces, hairline separators, a single restrained accent, solid reading surfaces. | Distinction must come from interaction and finishing quality more than a striking visual motif. |
| Warm study | Personal, editorial, calm. | Parchment and charcoal surfaces, a restrained serif only for a short welcome or identity treatment, generous space, warm accents. | Editorial details can distract from dense session labels and may feel less native. |
| Night signal | Focused, technical, expressive. | Ink surfaces, tightly controlled luminous accents, a small voice signal that reacts to actual audio. | A cinematic dark identity can overpower the work and adds complexity if equally polished light mode is required. |

Proceed with Quiet instrument with warmth in color and copy rather than decorative typography.
Warm study and Night signal are reference explorations only, not competing unresolved product directions.
Avoid gradients across primary reading surfaces, glass behind transcripts, glowing panels, heavy card nesting, animated mascots, and dashboards of activity metrics.
The name Vayen should appear as a restrained wordmark inside the popover and its settings view, with a simple monochrome menu-bar mark.
Logo design is a later exercise after the direction is chosen.

## Proposed initial visual system

All values below are starting tokens to validate in the native implementation, not final measurements.

| Element | Proposed rule |
| --- | --- |
| Typography | Use native system text styles and semantic weights; use a monospaced face only for file paths, commands, and evidence excerpts. |
| Type hierarchy | Start at 17 pt semibold for popover identity, 14 pt medium for session titles, 13 pt regular for reading text, and 11-12 pt for secondary metadata; allow text resizing. |
| Layout | Use a 4 pt base rhythm, usually 8 pt within groups, 12-16 pt between related content, and 20 pt at popover edges. |
| Session list | Start with a shared popover width around 420 pt, cap the visible height before scrolling, and prioritize readable two-line titles over more rows. |
| Conversation | Use the same popover shell as the session list, initially up to 600 pt tall with screen-aware bounds and internally scrolling content. |
| Surfaces | Use an opaque reading surface, native popover elevation, and a single separator level. |
| Corners | Follow native popover and control shapes; avoid assigning a different radius to every element. |
| Icons | Prefer familiar system symbols for microphones, settings, evidence, and audio controls. |
| Motion | Use approximately 120-180 ms state transitions; animate only a state change or an active audio signal. |

Light candidates are warm white `#F7F6F2` for the base, `#FFFFFF` for the reading surface, `#20231F` for primary text, and forest `#245F4D` for emphasis.
Dark candidates are `#191C1A` for the base, `#222723` for the reading surface, `#F1F3EE` for primary text, and sage `#A6C6B4` for emphasis.
These are candidates rather than validated accessible pairings.
Use semantic color roles, then verify contrast and increased-contrast behavior before adopting exact values.
Follow the system appearance by default and offer a simple appearance override only if it improves the actual implementation.
State must never be communicated by color alone.

## One popover, focused views

The menu-bar list answers which sessions exist and which one the user means.
The conversation view inside the same popover answers questions about one explicitly selected session.
Use in-popover navigation for the session list, conversation, evidence, and settings.
Do not create a floating panel, detached window, separate settings window, or persistent conversation surface.
Settings should stay secondary and contain only permissions, provider setup, data handling, and appearance if needed.
System-owned permission dialogs and System Settings are external OS surfaces rather than additional Vayen windows.

### Menu-bar list

Show a compact header, discovered session rows, and a quiet settings entry.
Each row should contain a readable session title, harness name, abbreviated project path, a truthful activity label, and a clear Talk action.
Use the original user prompt as the initial title source, normalized only for whitespace and safe truncation; a generated title must not invent an issue or outcome.
Disambiguate similar sessions with the repository or worktree path and a timestamp rather than decorative badges.
Order by recent recorded activity for the first milestone.
Do not imply that activity order is a judgment of importance.
Keyboard selection and Return should perform the same action as Talk.
Do not require a search box, filters, or a project sidebar to prove the first session workflow.

### Conversation view

Talk should navigate to the selected session's conversation inside the existing popover.
Provide a clear back action to the session list and keep evidence drilldown in the same popover navigation.
Clicking away dismisses the popover; the active voice turn must end safely when that happens.
The top area should always identify the session and project and show the latest context freshness.
The center should present a readable text record of the spoken conversation, with evidence available beside the answer.
The bottom should contain one primary microphone control, a listening or speaking state label, and a stop-audio control when relevant.
A small text input can provide a fallback without competing with the microphone.
The first assistant answer should begin with the original task and present state, usually in two to three short sentences.
Offer at most three unobtrusive follow-up prompts after an answer, such as “Why this approach?”, “What changed?”, and “What remains?”
Explain reported rationale only where the transcript supports it, and distinguish an agent's own concern from an independent critique by Vayen.
Use the coding session's voice only as quoted evidence; Vayen should not pretend to be the coding agent itself.
For example, “The agent is tracing the cache invalidation path” is clearer than claiming “I am fixing the cache.”

### Proposed microphone behavior

The proposed sequence is click Talk to open a session, click the microphone to begin, and click away to end.
This sequence is a proposed default, not an explicitly confirmed user choice about microphone initiation.
Complete permission and provider setup before the first listening turn and explain the activation behavior inline.
The popover should make listening unmistakable through both a text label and a mic indicator.
Every dismissal path must stop microphone capture and current playback, cancel the active turn, and prevent late provider events from resuming audio or updating the wrong session.
Switching sessions or returning to the list must end the active voice turn before changing the visible context.
Reopening the popover may restore the selected session and completed conversation text, but must never resume capture or playback automatically.
There is no background voice conversation in the first-beta design.
Push-to-talk remains an alternative worth deciding early because it changes the core rhythm and interruption design.
Automatic interruption of spoken output when the user speaks is a desired behavior to validate against the selected voice integration, not an assumed capability.

### Required popover lifecycle spike

Before polishing the interface, validate the full voice lifecycle in a small native popover experiment.
Exercise outside clicks, Escape, menu-bar icon toggling, app switching, session navigation, first-use microphone permission, and provider callbacks arriving after cancellation.
For every dismissal, verify that capture stops, playback stops, the active turn is invalidated, and reopening leaves the microphone off.
Verify that an OS permission dialog cannot create hidden capture or unexpectedly restart a dismissed conversation.
Use lifecycle logs and targeted native integration checks to establish behavior without assuming a popover dismissal is equivalent to a view disappearing.
Treat failure to stop audio on any dismissal path as a blocker for the voice demo.

## Evidence without making the user read a transcript

Keep the main answer concise and put expandable evidence directly beside it.
An evidence entry should name its type, source session, relevant time or sequence, and a short readable excerpt.
File references should show the path and the observed action without implying that a tool request necessarily succeeded.
Examples of useful distinctions are “The agent reported tests passed,” “The recorded command returned exit code 0,” and “No test result is present in this snapshot.”
For the first beta, evidence comes only from the selected coding-session transcript and its recorded tool results.
Do not inspect repository files, run git, read diffs directly, fetch issue bodies, or imply that Vayen independently verified a recorded claim.
Paths, diffs, commands, and test results can be explained only when they already appear in the transcript.
A spoken response should mention uncertainty when material, while detailed source links remain visual.
If the original issue body is absent, say that only the recorded prompt is available rather than claiming to have read the issue.
When asked for a quality verdict, explain what the transcript records and what it does not establish, without adding Vayen's own judgment.
Missing evidence should produce a useful limitation, such as “I can see the edit request, but no result has been recorded yet.”

## Honest activity and freshness

Use a separate display concept for observed activity, explicit completion, and context freshness.
“Updated 2m ago” is a reliable statement when supported by the source timestamp; it is not proof the process is running or finished.
Use “Activity detected” for recent transcript writes; the transcript-only beta should not display “Working” based on inference.
Use “Agent reported completion” for a transcript completion claim; do not translate that into independently verified task success.
Use “No recent activity” or “State unknown” when the evidence cannot distinguish waiting, stopped, finished, or disconnected.
Keep the reason available in a concise detail view, for example “Latest transcript entry at 14:32; current running state is unknown.”
Answers should use a stable context snapshot for each turn.
If the source changes during an answer, show a quiet “New session activity available” indication and incorporate the new snapshot into the next turn.
Do not interrupt spoken output with background update announcements.

## Required experience states

| State | User-facing treatment |
| --- | --- |
| First launch | Explain the observer role, automatic discovery, microphone use, and provider-bound selected context in a short setup flow; let developer-beta users enter and validate their own required API keys. |
| No sessions found | Explain what Vayen can currently discover and suggest starting a Claude Code session, without a fake empty conversation. |
| Discovery unavailable | Distinguish missing installation, inaccessible source files, and unsupported source format where the adapter can identify them. |
| Session selected | Show session identity immediately, followed by real preparation progress without an invented completion percentage. |
| Microphone denied | Provide a direct route to the relevant permission settings and keep text fallback usable. |
| Listening | Show “Listening” with a stable mic affordance and a signal only when actual audio levels are available. |
| Preparing answer | Show one calm state label and allow cancel; do not display simulated token or waveform activity. |
| Speaking | Show the answer text as supported by the integration and make stopping audio immediate. |
| Popover dismissed | Stop capture and playback, cancel the active turn, and ignore its late events; retain completed text only according to the conversation-retention policy. |
| Popover reopened | Restore readable context where available with the microphone off and no automatic audio resumption. |
| Connection or provider failure | Preserve the conversation and offer a clear retry without implying that a failed request was answered. |
| Transcript unreadable or partial | Explain which portion is unavailable and avoid silently omitting the limitation from an affected answer. |
| Context limit reached | Explain that the current evidence does not cover the whole session rather than presenting a partial view as complete. |
| Session disappears | Preserve already captured evidence as a dated snapshot and identify that live updates are unavailable. |

All primary actions need keyboard access, visible focus, descriptive accessibility labels, and a predictable focus order.
Screen readers should announce meaningful transitions without narrating every file update or audio sample.
Respect reduced motion, increased contrast, and text sizing, and keep the spoken conversation available as readable text.
Use a real keyboard shortcut for stopping speech and document it in the interface.
Do not use silent microphone activation, continuously pulsing decoration, hidden hover-only actions, or status dots without text.

## Decisions that deserve the user's attention

The quiet native direction, Swift acceptance, own-key developer beta, popover-only interface, transcript-only evidence, and neutral explanation are settled and should not be re-asked.

1. Should the microphone use a click to start and stop, or require holding a key while speaking?
   The proposed default is a separate microphone click after Talk, with all audio ending when the popover closes.
2. How much proof do you want visible by default: a clean spoken answer with an Evidence control, or a few source excerpts immediately below it?
   This trades visual calm against immediate verifiability.
3. Is sending selected transcript context to configured voice and model providers acceptable after a clear initial explanation, or do you want to approve the exact outbound context per conversation?
   This affects latency and the number of steps between Talk and the first answer.
4. If Claude support is excellent but Codex and Cursor remain unavailable, is that a successful first release for you?
   This confirms whether the stated first milestone is a demo boundary or a release boundary.
5. Should completed Vayen conversation text survive app restarts, or remain only for the current app session?
   This determines local retention separately from the coding agent's untouched transcript.

## Design acceptance for the implementation handoff

The first demonstration should use a real Claude session and complete the brief's discover, Talk, answer, cross-question loop.
The user should recognize the selected session from its title and path without opening a transcript.
The first answer should identify the original task, the latest supported activity, and any material uncertainty.
Every substantive explanation about an agent's actions should be traceable to captured evidence.
The user should always know whether the microphone is active, whether audio is playing, and which session supplies the context.
Every Vayen view must stay inside the menu popover, and dismissal must leave no active capture, playback, or resumable live turn.
Every explanation must remain neutral and use transcript evidence without inspecting repository state.
An idle or stale source must never be represented as successful completion without supporting evidence.
The product must remain useful in text when voice setup or connectivity fails.
Validate visual fidelity with native layout checks, build checks, and targeted review; browser or screenshot verification requires Apurv's explicit request.
No task creation, write-back, orchestration, Kanban, analytics dashboard, or team features belong in this milestone.
