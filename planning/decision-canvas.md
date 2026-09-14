# Vayen decision canvas

Updated: 2026-09-14.
This is the durable decision record for the next agent.
An option shown in the interactive concept is an exploration, not a confirmed product decision.
Update this file when Apurv answers, and keep the architecture and handoff consistent with it.

## Product promise

Return to a coding session after half an hour, ask what happened, and understand its purpose and recorded progress without reading its transcript.

## Confirmed by Apurv

| Decision | Choice | Implication |
| --- | --- | --- |
| Brand | Vayen | Use this name throughout the app and handoff. |
| Platform | Mac only to start | Optimize the actual Mac experience. |
| Design | Quiet native Mac utility | Precise type, restrained surfaces, subtle motion, no dashboard. |
| Stack priority | Best possible Mac feel; Swift is fine | Propose SwiftUI with AppKit where window behavior needs it. |
| Audience | Developer beta | Include setup, diagnosable failures, and distribution in the plan. |
| Credentials | Users' own keys | No shared developer secret or bundled production key. |
| Voice | ElevenLabs | Keep voice integration behind a small boundary. |
| First proof | One Claude Code session | Defer production Codex and Cursor adapters. |
| Current work | Planning only, using a small parallel swarm | Save agent-ready contracts and acceptance criteria; do not build the app yet. |
| Conversation surface | Everything inside the menu popover | No detached or persistent floating conversation window. |
| Beta evidence | Transcript only | No current repository reads, git commands, or issue fetches. |
| Voice posture | Neutral explainer | Describe recorded evidence without judging the implementation. |

## Proposed interaction defaults

| Question | Proposed default | What changes |
| --- | --- | --- |
| When does the mic start? | Talk opens the conversation inside the popover; explicit mic start. | Microphone permission timing and activation behavior. |
| What happens when the popover closes? | Stop capture and playback; cancel the turn and disconnect. | Clicking into an editor ends the voice conversation; do not create a hidden call. |
| Is observer conversation history retained? | Memory only until app exit, per session. | No persistent personal conversation store in the first beta. |

## Recommended decisions, not yet commitments

| Decision | Recommendation | Reason or gate |
| --- | --- | --- |
| App structure | One native process with small module boundaries | Avoid a sidecar before a concrete need is demonstrated. |
| Distribution | Signed and notarized direct download for beta | Verify permissions and signing setup in a clean install spike. |
| Discovery | Automatic discovery inside permitted harness locations | Folder permission is setup, not manual transcript import. |
| Status | Activity with evidence and freshness | Silence does not prove a task is finished. |
| Grounding | Selected-session evidence with source references and snapshot watermark | Keep changing sessions coherent during each answer. |
| Index | Small rebuildable local index; no vector database initially | Select bounded evidence without copying every transcript to the cloud. |
| Voice transport | Decide after native macOS spike | Do not assume that an iOS Swift SDK runs on macOS. |
| Persistence | Do not persist raw microphone audio by default | Session observer history and coding-agent history are separate data. |

## Questions for the next design discussion

1. What should feel premium after the hundredth use: speed, voice naturalness, visual restraint, or confidence in the answers?
2. Should a spoken answer be short enough to finish in ten seconds, with details only when asked?
3. When evidence is incomplete, is stating the missing evidence enough, or should it also offer a relevant follow-up question?
4. What would make you uninstall it immediately: setup friction, wrong answers, background resource use, or accidental audio capture?
5. Should a conversation remember your previous review questions after restart, and for how long?

These questions are sequenced discussion prompts, not a blocking questionnaire for the first implementation agent.

## Change log for decisions

- 2026-09-14: Apurv selected quiet native Mac design, Mac quality with Swift, and developer beta with users' own keys.
- 2026-09-14: Apurv selected a menu-popover-only conversation, transcript-only beta evidence, and a neutral explainer voice.
