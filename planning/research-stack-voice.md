# Vayen: native stack and voice architecture research

Verified on 2026-09-14 against public primary documentation and source.
This is a planning artifact, not implemented or empirically verified application behavior.
No voice API calls, account changes, transcript uploads, browser sessions, or screenshots were performed.
The treg discovery skill was read and a free catalog search attempted; its CLI could not resolve the service, so research used public official web documentation.

## Recommendation

Use Swift with SwiftUI views and a small AppKit shell for the Mac-only developer beta.
Each beta user supplies their own ElevenLabs account credentials and uses a private agent in their own account.
Use ElevenLabs Agents for the initial conversational loop, with an app-local evidence service that exposes only the selected coding session.
Do not introduce a Vayen cloud backend, inbound localhost bridge, embedded browser, vector database, or general-purpose agent framework for the first milestone.
Keep the existing coding agent independent and read its session state without modifying it.

Recommend macOS 14 as the initial deployment target, subject to the beta audience and pinned SDK build spike.
This is a product-support recommendation, not ElevenLabs' technical minimum.
Propose a Developer ID signed and notarized direct-download beta with hardened runtime.
Resolve App Sandbox in a scoped file-access spike before fixing the entitlement strategy; an unsandboxed direct-download build is an alternative if scoped access cannot support discovery.
Still restrict application reads to configured harness transcript roots.
The first beta does not inspect repositories, source files, or git diffs.
Do not request Full Disk Access by default or claim that unsandboxed distribution bypasses macOS privacy controls.
Apple documents the direct distribution workflow and the separate file-access limitations of sandboxing. [Apple distribution](https://help.apple.com/xcode/mac/current/en.lproj/dev033e997ca.html), [Apple file access](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)

## Verified facts and their limits

| Topic | Verified fact | What this does not establish |
| --- | --- | --- |
| Native menu UI | SwiftUI `MenuBarExtra` supports menu-bar-only apps and a window style for richer content; `LSUIElement` removes the Dock/application-switcher presence. [Apple](https://developer.apple.com/documentation/swiftui/menubarextra) | It does not prove Vayen's desired panel focus and dismissal behavior. |
| Popover lifecycle | SwiftUI offers a window-style menu extra; AppKit remains available for precise hosting and dismissal behavior. [Apple](https://developer.apple.com/documentation/swiftui/menubarextra) | Reliable disappearance-to-audio-cancellation behavior requires a spike. |
| Swift voice SDK | The official SDK describes macOS support and uses LiveKit WebRTC; the package manifest declares macOS 10.15 and a LiveKit Swift dependency. [SDK](https://github.com/elevenlabs/elevenlabs-swift-sdk), [manifest](https://raw.githubusercontent.com/elevenlabs/elevenlabs-swift-sdk/main/Package.swift) | A declared deployment target is not proof that a resolved release builds or that all audio paths work on every Mac. |
| SDK version | The README observed during research suggests package version 3.3.1. [SDK](https://github.com/elevenlabs/elevenlabs-swift-sdk) | This is moving main-branch documentation, not a version pinned or compiled by this research. |
| Runtime evidence delivery | ElevenLabs supports non-interrupting contextual updates; its Swift usage guide exposes `conversation.updateContext(...)`. [Events](https://elevenlabs.io/docs/eleven-agents/customization/events/client-to-server-events), [Swift usage](https://github.com/elevenlabs/elevenlabs-swift-sdk/blob/main/Documentation/Usage.md) | Documentation does not promise that sending an update creates an atomic acknowledgement barrier before the next model turn. |
| Local evidence tools | Client tools execute in the client; enabling Wait for response causes the returned result to be appended to conversation context. [Client tools](https://elevenlabs.io/docs/eleven-agents/customization/tools/client-tools) | A prompt asking the model to call a tool does not itself guarantee invocation on every factual answer. |
| Private conversations | The Swift SDK supports temporary conversation tokens for private WebRTC conversations, and ElevenLabs documents a token endpoint. [SDK](https://github.com/elevenlabs/elevenlabs-swift-sdk), [token API](https://elevenlabs.io/docs/eleven-agents/api-reference/conversations/get-webrtc-token) | Exact token scope, expiry behavior, and minimal API-key permissions must be verified for the pinned integration. |
| Filesystem updates | FSEvents watches directory hierarchies; events can be coalesced or dropped and require rescanning. [Apple API](https://developer.apple.com/documentation/coreservices/file_system_events), [Apple guide](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html) | A filesystem event is not a complete transcript record or reliable proof that an agent is working. |
| Credential storage | Keychain Services stores small secrets in an encrypted keychain. [Apple](https://developer.apple.com/documentation/security/keychain-services) | Keychain storage does not make a shared application-owner key safe to ship in a binary. |

## Smallest component layout

Use one macOS app target and one independently testable local core package.
These boundaries can begin as folders and Swift protocols rather than separately deployed services.

| Component | Responsibility | Boundary |
| --- | --- | --- |
| App shell | Menu icon and one popover containing discovery, conversation, settings and onboarding states. | Own dismissal behavior on the main actor. |
| Session adapter | Discover and normalize Claude sessions first. | Never expose raw harness parsing to UI or voice code. |
| Session index | Maintain metadata and incremental transcript offsets; reconcile changes. | No network calls. |
| Evidence service | Build versioned evidence snapshots and bounded evidence lookups for the selected session. | No arbitrary filesystem paths accepted from the model. |
| Conversation coordinator | Bind one voice conversation to one session and control freshness, cancellation, and reconnect state. | Own session identity and context authorization. |
| VoiceProvider | Start/end/mute, text debug input, context updates, tool requests/results, transcripts, connection/audio state. | ElevenLabs types do not leak into adapters or evidence storage. |
| Settings and credentials | Local preferences, configured roots, private agent identity, Keychain references. | Never put keys in logs, transcript context, UserDefaults, or source control. |

Use Foundation file I/O and Swift concurrency for parsing and indexing away from the main actor.
Begin with an in-memory metadata index and small local checkpoints; add SQLite only if measured session counts or restart performance justify it.
An FSEvents watcher should trigger incremental reads and reconciliation, including partial trailing JSONL records, truncation, rename, and missed-event recovery.
The adapter research defines actual file locations and parser semantics separately.

Use SwiftUI for presentation and system controls.
Start the picker with `MenuBarExtra(.window)`.
Keep the conversation, transcript, settings and setup inside that same popover, as requested.
Propose that clicking away or pressing Escape ends microphone capture, playback, active turn and the voice connection immediately.
Do not allow hidden background recording after dismissal.
If reliable dismissal handling or keyboard control cannot be achieved cleanly, replace only the menu shell with `NSStatusItem` and `NSPopover` hosting the same SwiftUI views.
No separate conversation window is part of this beta.
Premium feel comes from typography, spacing, interaction, accessibility, and predictable window behavior, not an elaborate rendering stack.

## Beta credentials and setup

Default onboarding needs an ElevenLabs API key and a private Vayen agent in that user's ElevenLabs account.
It does not need a second model-provider key.
Supported model usage can be billed through ElevenLabs, separately from voice usage. [ElevenAgents pricing](https://elevenlabs.io/pricing/agents)
Do not present a hardcoded price estimate as a billing cap.

ElevenLabs also documents optional model BYOK by storing a provider key as a secret in the user's ElevenLabs account and configuring Custom LLM. [Custom model integration](https://elevenlabs.io/docs/eleven-agents/customization/llm/custom-llm)
That advanced option should not make Vayen collect another key during default onboarding.
It changes the trust boundary because ElevenLabs holds the model credential.

The intended onboarding sequence is:

1. Explain that local coding history will be read and that Talk shares selected evidence and microphone audio with ElevenLabs and the configured model service.
2. Let the user connect their own ElevenLabs account using a key saved in their Mac Keychain.
3. Show a concrete private-agent template and the settings it will create, including voice, model, read-only tools, and retention.
4. Create that private agent only after the user chooses the setup action, or accept an existing compatible private agent after validating its configuration.
5. Validate authentication and configuration without starting a charged audio conversation.
6. Request microphone permission at the first explicit mic action in the Talk view, then start a clearly indicated, billable conversation.

The product setup action is future consent for that user's cloud configuration, not authorization for research agents to create cloud resources now.
No API setup or key collection was performed during this planning task.
Avoid modifying unrelated agents or enabling broad tools on a user's existing agent.

Mint short-lived conversation credentials directly from the user's Mac using their own account key, then pass only the temporary credential to the voice SDK.
This is an architecture inference for a user-owned desktop client, not the SDK's standard recommended backend pattern.
The SDK explicitly warns against embedding a developer's API key in distributed client apps and recommends backend-issued credentials. [SDK authentication](https://github.com/elevenlabs/elevenlabs-swift-sdk)
The BYOK beta must never bundle Apurv's key, a common public agent, or a shared paid account.
If Vayen later owns the service credentials, introduce an authenticated backend token broker then.
Treat short-lived tokens and signed URLs as secrets too.

## Grounding a live call

At Talk, bind the connection to an immutable session identity and create a local `EvidenceSnapshot` with snapshot version, latest observed source timestamp, bounded source records, evidence IDs, and coverage limitations.
Use a small initial packet covering the original request, latest activity, changes described in the transcript and recorded test output.
The app does not inspect current repository state to confirm these claims.
Preserve raw evidence references so cross-questions can retrieve details instead of relying only on a lossy summary.
Use the selected transcript directly when it fits the configured budget; do not add embedding infrastructure preemptively.

Expose one narrow client tool, conceptually `get_selected_session_evidence`, with bounded query and evidence-ID arguments.
Its implementation resolves the current selected session locally; the model cannot choose a different session, an arbitrary path, or a shell command.
Enable Wait for response and instruct the agent to obtain current evidence before factual answers.
Include version and observation time in every tool result.
Return explicit unavailable or truncated coverage instead of guessing.

On local transcript append, batch relevant changes into a context update during the active call.
Use context updates to hint that newer evidence exists; use the evidence tool to fetch authoritative current details.
Do not stream every tool-output byte into the voice call.
Do not confuse a locally observed version, a version transmitted, and a version actually used by the answering model.
An `updateContext` completion must not be called "model is up to date" without a tested acknowledgement contract.

This design targets answers grounded in the latest snapshot obtained for a turn, not impossible zero-staleness while a writer continues changing files.
The agent may say "As of the latest entry I can see" when freshness matters.
If appends happen during speech, the next answer can use the newer snapshot without rewriting speech already played.
If tool invocation or context ordering cannot be made reliable in the SDK/platform, fail the grounding spike and revisit the conversation loop rather than claim a hard guarantee.

Treat transcript instructions and tool outputs as untrusted evidence, including any requests to reveal keys or examine other projects.
Limit the voice agent to neutral explanation of transcript observations; it has no write, shell, MCP, repository-reading, or coding-agent control capabilities.
Describe recorded actions and stated reasoning without judging whether the implementation is good or satisfies the issue.
A source record claiming tests passed is an observed claim until the actual test result is available.
A question requiring current repository state receives a clear limitation: this beta can explain only what the transcript records.

Ending or changing the selected session cancels pending tool work, disconnects the old call, stops capture/playback, and discards its in-memory context before a fresh conversation starts.
A reconnect builds fresh session evidence and explicitly marks any missing conversation continuity.

## Privacy data flow

```text
Read-only harness files
    -> local adapter and index
    -> local selected-session EvidenceSnapshot
    -> bounded context/tool responses -> ElevenLabs conversation service
                                           -> configured model execution service
Microphone audio ----------------------> ElevenLabs voice transport/service
Spoken answer <------------------------- ElevenLabs speech synthesis
```

The app sends selected prompts, relevant assistant/tool records, file names or snippets already present in those records, evidence identifiers, and the active voice conversation.
It does not fetch additional source files or git diffs.
Unselected session contents remain local and are not uploaded for background summaries or cloud search.
Do not upload a whole transcript archive to ElevenLabs knowledge-base storage as a shortcut.
Configured third-party model services may process conversation text and evidence.
Some models explicitly designated Hosted by ElevenLabs run on its infrastructure, with no input/output sent to the original model vendor; the disclosure must match the chosen execution route and fallbacks. [Model routing](https://elevenlabs.io/docs/eleven-agents/customization/llm)
The SDK also depends on LiveKit transport, so provider/subprocessor statements need review before a public privacy claim.

"Local-first" must mean local discovery and storage with explicit selected-context transmission.
It must not imply that cloud providers never store received content.
ElevenLabs currently documents a default two-year conversation retention period, separate transcript/audio retention settings, and retention value zero as scheduled deletion. [Retention](https://elevenlabs.io/docs/eleven-agents/customization/privacy/retention)
Its enterprise Zero Retention Mode is a separate setting and should not be promised for ordinary beta accounts. [Zero Retention Mode](https://elevenlabs.io/docs/eleven-agents/customization/privacy/zrm)
Configure and display the effective account settings before real transcript use, preferably audio saving off and the shortest supported transcript retention.
Redaction of recognizable secret patterns is defense in depth, not proof that arbitrary source code contains no secrets.

## Alternatives

| Option | Why consider it | Decision for this beta |
| --- | --- | --- |
| Native SwiftUI/AppKit + ElevenLabs Agents | Direct Mac window, audio, Keychain, accessibility and filesystem integration. | Recommended, conditional on live grounding and audio spikes. |
| Tauri + Rust + web UI | Rust core and system webview are viable for cross-platform desktop products; macOS uses WKWebView. [Tauri](https://v2.tauri.app/concept/process-model/) | No clear advantage for the confirmed Mac-first native feel; browser microphone/WebRTC behavior would need its own spike. |
| Electron + TypeScript | Bundles Chromium and Node.js with mature browser APIs. [Electron](https://www.electronjs.org/docs/latest/why-electron) | Useful if a shared web UI becomes strategic; adds a browser runtime to a deliberately small native utility. |
| ElevenLabs + hosted custom LLM endpoint | More control over evidence enforcement and model orchestration. | Not the smallest beta: adds a server, authentication, remote evidence flow, and another latency-sensitive dependency. |
| Local app orchestrates separate STT, model, TTS APIs | Can own per-turn evidence and model credentials entirely on the Mac. | Conditional fallback if Agents cannot meet grounding requirements; first verify current ElevenLabs streaming speech capabilities and own interruption/turn-taking costs. |

ElevenLabs Custom LLM expects a reachable compatible streaming endpoint; its documentation demonstrates exposing a local server using a public tunnel. [Custom model integration](https://elevenlabs.io/docs/eleven-agents/customization/llm/custom-llm)
A desktop localhost endpoint alone is therefore not a viable hosted-model callback destination.
Do not quietly add a tunnel, public inbound server, or relay for beta users.

## Decisive spikes before product implementation

All latency numbers below are proposed acceptance targets, not measured performance or vendor guarantees.
Record machine, OS, pinned dependencies, audio device, network, model, evidence size, and sample count.

| Spike | Pass criteria | Failure response |
| --- | --- | --- |
| Native dependency and audio | Pinned SDK resolves and builds on target Macs; microphone permission, start/end/mute, interruption, sleep/wake, device disconnect and network loss behave correctly; 20 repeated calls leave no microphone capture after End. | Isolate SDK issue before choosing a fallback; do not replace the native stack solely from documentation uncertainty. |
| Per-user private setup | Two beta accounts each connect only to their own private agent; unauthenticated access fails; revocation fails safely; no owner key, public fallback, or cross-account conversation is used. | Block beta distribution until ownership/authentication is fixed. |
| Evidence correctness | Across at least 20 question/answer cases including missing information and conflicting outputs, factual answers have actual supporting evidence and unknowns are acknowledged. | Adjust evidence packaging and evaluate again; no completion claims from activity timestamps. |
| Mid-call freshness | Append decisive new evidence before, during and after a user turn; tool response identifies its snapshot; next eligible answer uses that snapshot; ordered append races do not silently claim fresh coverage. | Treat updates as best effort or change orchestration; no hard freshness guarantee without proof. |
| Isolation and injection | Session A/B contain distinct canary strings; B canaries never appear in A outbound data; injected transcript requests cannot read another root or execute a command. | Fail closed and fix the application boundary rather than only adding prompt text. |
| Useful voice latency | On the target network, median end-of-user-speech to first useful answer audio under 2 seconds across 30 warm turns; record p95 and cold connection separately, with a stretch goal of 3 seconds for each. | Find whether delay is turn detection, tool round trip, model or TTS; shorten context or change the allowed model before adding infrastructure. |
| Context budget | Representative long sessions stay within provider limits; bounded tools retain cross-question accuracy; omitted evidence is reported. | Add selective retrieval and coverage markers before embedding/RAG infrastructure. |
| Privacy and retention | Outbound inspection contains only selected authorized evidence; keys/tokens never enter logs; effective provider retention and model route are visible; no content telemetry is enabled. | Block real-session beta testing until corrected. |
| Signed distribution | Fresh Mac launch succeeds through normal Gatekeeper flow; known harness roots can be read or a scoped access recovery path works; no blanket Full Disk Access requirement appears. | Resolve signing/permissions before inviting beta users. |

Do not start paid spikes or cloud provisioning merely because this document exists.
The next implementation agent should first pin dependencies, implement synthetic local fixtures, and present the precise credential/setup action needed for the authorized beta implementation stage.

## Remaining decisions

- Confirm minimum macOS version and whether the first beta must support Intel Macs as well as Apple silicon.
- Choose the actual voice/model pair after measuring coding vocabulary, interruption quality, evidence accuracy and latency.
- Validate the proposed popover dismissal behavior: clicking away or pressing Escape ends the active call and stops capture immediately.
- Accept the user-account retention behavior or require stronger provider settings that may exclude ordinary beta plans.
- Choose the default bounded transcript context budget and how omitted transcript coverage appears in the neutral explanation.

These choices refine an already selected native Mac developer-beta direction with a single popover, transcript-only evidence, and a neutral explainer voice.
They should not reopen orchestration, team features, or cross-platform architecture in the first milestone.
