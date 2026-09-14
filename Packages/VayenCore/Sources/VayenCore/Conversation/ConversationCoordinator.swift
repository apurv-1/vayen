import Foundation

/// Owns one voice conversation bound to one selected coding session.
///
/// Responsibilities (see planning/architecture.md):
/// - One immutable evidence snapshot per turn; appends mint new versions.
/// - Total cancellation: popover dismissal, session switch, or Stop tears down
///   capture, playback, the transport, and discards late events via a
///   generation counter.
/// - Freshness is honest: mid-call appends produce an `updateSystemPrompt`
///   hint and the model refreshes through `get_selected_session_evidence`,
///   whose result reports the snapshot version it saw.
public enum CoordinatorError: Error, Sendable {
    case noSessionSelected
}

public actor ConversationCoordinator {

    public enum Status: String, Sendable {
        case idle, connecting, ready, listening, thinking, speaking, ended, failed
    }

    /// Everything the UI needs, in order.
    public enum Update: Sendable {
        case status(Status)
        case userUtterance(String)
        case assistantUtterance(String)
        /// A new evidence snapshot was bound (connect or evidence refresh).
        case snapshotApplied(version: Int, cutoff: Date?, limitations: [String])
        /// Quiet "new session activity" indicator; details come on next turn.
        case newActivityAvailable
        case failure(String)
    }

    private let catalog: SessionCatalog
    private let makeProvider: @Sendable () -> any VoiceProvider
    private let audio: AgentAudioPipeline
    private let evidenceBuilder = EvidenceBuilder()
    /// Poll interval for transcript growth during a live conversation.
    private let pollInterval: Duration = .seconds(2)

    public nonisolated let updates: AsyncStream<Update>
    private let updateSink: AsyncStream<Update>.Continuation

    private var provider: (any VoiceProvider)?
    private var providerPump: Task<Void, Never>?
    private var pollLoop: Task<Void, Never>?

    private var selectedSession: SessionIdentity?
    private var conversationID: UUID?
    private var generation = 0
    private var status: Status = .idle
    /// In-memory observer history, per session, until app exit.
    private var turns: [SessionIdentity: [ObserverTurn]] = [:]
    /// The turn currently being answered, for streaming text into it.
    private var openTurnID: UUID?
    /// Latest evidence snapshot version applied to this conversation, mirrored
    /// locally so turn accounting stays synchronous.
    private var pendingSnapshotVersion = 0
    private var micActive = false

    public init(
        catalog: SessionCatalog,
        audio: AgentAudioPipeline = AgentAudioPipeline(),
        makeProvider: @escaping @Sendable () -> any VoiceProvider
    ) {
        self.catalog = catalog
        self.audio = audio
        self.makeProvider = makeProvider
        var sink: AsyncStream<Update>.Continuation!
        self.updates = AsyncStream { sink = $0 }
        self.updateSink = sink
    }

    public var currentStatus: Status { status }
    public var selectedSessionID: SessionIdentity? { selectedSession }

    public func history(for identity: SessionIdentity) -> [ObserverTurn] {
        turns[identity] ?? []
    }

    // MARK: - Session selection

    /// Bind the conversation to a session. If a conversation is live it is
    /// fully torn down first; no audio or event can cross sessions.
    public func select(_ identity: SessionIdentity) async throws {
        if selectedSession != identity {
            await stop()
            selectedSession = identity
        }
        _ = try await catalog.load(identity)
    }

    // MARK: - Conversation lifecycle

    /// Connect the voice transport for the selected session.
    /// The microphone stays off until `startListening()`.
    public func connect() async throws {
        guard let identity = selectedSession else { throw CoordinatorError.noSessionSelected }
        generation += 1
        let gen = generation
        setStatus(.connecting)

        // Fresh tail before building the packet.
        _ = try? await catalog.poll(identity)
        let loaded = try await catalog.session(identity)
        let snapshot = evidenceBuilder.snapshot(
            session: loaded,
            version: await catalog.nextSnapshotVersion(for: identity)
        )
        let packet = ExplainerPrompt.packet(from: snapshot)
        let config = VoiceSessionConfig(
            systemPrompt: ExplainerPrompt.systemPrompt(with: packet),
            functions: [ExplainerPrompt.evidenceTool],
            contextMessages: contextMessages(for: identity),
            greeting: nil
        )

        let provider = makeProvider()
        self.provider = provider
        do {
            try await provider.connect(config: config)
        } catch {
            setStatus(.failed)
            updateSink.yield(.failure("Voice connection failed: \(error.localizedDescription)"))
            throw error
        }
        guard gen == generation else { await provider.disconnect(); return }

        conversationID = UUID()
        pendingSnapshotVersion = snapshot.version
        updateSink.yield(.snapshotApplied(
            version: snapshot.version,
            cutoff: snapshot.sourceCutoff,
            limitations: snapshot.limitations
        ))
        setStatus(.ready)
        startPump(provider: provider, generation: gen)
        startPollLoop(generation: gen)
    }

    /// Start microphone capture. Requests permission on first use.
    public func startListening() async {
        guard status == .ready || status == .listening || status == .speaking || status == .thinking else { return }
        if MicrophonePermission.status == .notDetermined {
            let granted = await MicrophonePermission.request()
            guard granted else {
                updateSink.yield(.failure("Microphone access was denied. Text input still works."))
                return
            }
        } else if MicrophonePermission.status != .authorized {
            updateSink.yield(.failure("Microphone access is off. Enable it in System Settings to talk."))
            return
        }
        do {
            try audio.startEngine()
            let provider = self.provider
            try audio.startCapture { data in
                provider?.sendAudio(data)
            }
            micActive = true
            setStatus(.listening)
        } catch {
            updateSink.yield(.failure("Could not start the microphone: \(error.localizedDescription)"))
        }
    }

    /// Stop capture but keep the conversation connected (text still works).
    public func stopListening() {
        audio.stopCapture()
        micActive = false
        if status == .listening { setStatus(.ready) }
    }

    /// User typed a question (text fallback). Goes through the same pipeline.
    public func sendText(_ text: String) async {
        guard let provider else { return }
        recordUserTurn(question: text)
        setStatus(.thinking)
        await provider.sendUserText(text)
    }

    /// Full teardown: capture off, playback flushed, transport disconnected,
    /// pumps cancelled, late events discarded. Idempotent.
    public func stop() async {
        generation += 1
        pollLoop?.cancel(); pollLoop = nil
        providerPump?.cancel(); providerPump = nil
        audio.shutdown()
        micActive = false
        if let provider {
            await provider.disconnect()
            self.provider = nil
        }
        openTurnID = nil
        if status != .idle && status != .ended {
            setStatus(.ended)
        }
        conversationID = nil
    }

    /// Called when the popover is dismissed: same as stop().
    public func popoverDismissed() async {
        await stop()
    }

    // MARK: - Provider event pump

    private func startPump(provider: any VoiceProvider, generation gen: Int) {
        providerPump = Task { [weak self] in
            for await event in provider.events {
                guard let self, await self.isCurrent(gen) else { return }
                await self.handle(event)
            }
            // Stream finished (disconnect or failure).
            await self?.streamEnded(generation: gen)
        }
    }

    private func isCurrent(_ gen: Int) -> Bool {
        gen == generation && provider != nil
    }

    private func streamEnded(generation gen: Int) {
        guard gen == generation else { return }
        if status != .ended && status != .failed {
            setStatus(.ended)
        }
    }

    private func handle(_ event: VoiceEvent) async {
        guard let identity = selectedSession else { return }
        switch event {
        case .connected:
            if status == .connecting { setStatus(.ready) }
        case .userStartedSpeaking:
            // Barge-in: drop queued agent audio immediately.
            audio.flushPlayback()
            if status == .speaking { setStatus(.listening) }
        case .conversationText(let role, let text):
            switch role {
            case .user:
                recordUserTurn(question: text)
                setStatus(.thinking)
                updateSink.yield(.userUtterance(text))
            case .assistant:
                recordAssistantAnswer(text)
                updateSink.yield(.assistantUtterance(text))
            }
        case .agentThinking:
            setStatus(.thinking)
        case .functionCall(let id, let name, let argumentsJSON):
            await handleFunctionCall(id: id, name: name, argumentsJSON: argumentsJSON, identity: identity)
        case .functionCallCancelled(let id, _):
            // Provider discarded the call; nothing to clean up beyond the
            // pending marker, which sendFunctionResult would have cleared.
            _ = id
        case .agentAudioStarted(let total, _, _):
            setStatus(.speaking)
            _ = total
        case .agentAudio(let data):
            audio.play(data)
        case .agentAudioDone:
            if status == .speaking { setStatus(micActive ? .listening : .ready) }
        case .injectionRefused:
            break
        case .providerWarning(let message):
            updateSink.yield(.failure("Provider warning: \(message)"))
        case .failure(let message):
            setStatus(.failed)
            updateSink.yield(.failure(message))
        case .disconnected(let reason):
            if status != .ended {
                setStatus(.ended)
                if let reason, !reason.isEmpty {
                    updateSink.yield(.failure("Connection closed: \(reason)"))
                }
            }
        }
    }

    // MARK: - Evidence tool

    /// The single client tool. The model cannot pick a session, path, or
    /// command: the coordinator resolves the already-selected session.
    private func handleFunctionCall(id: String, name: String, argumentsJSON: String, identity: SessionIdentity) async {
        guard name == ExplainerPrompt.evidenceToolName else {
            await provider?.sendFunctionResult(
                id: id, name: name,
                content: "Error: unsupported function."
            )
            return
        }
        var question: String? = nil
        if let data = argumentsJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            question = obj["question"] as? String
        }

        // Always refresh from disk before answering so the snapshot is as new
        // as the tail allows.
        _ = try? await catalog.poll(identity)
        guard let loaded = try? await catalog.session(identity) else {
            await provider?.sendFunctionResult(
                id: id, name: name,
                content: "Error: session evidence is unavailable."
            )
            return
        }
        let snapshot = evidenceBuilder.snapshot(
            session: loaded,
            version: await catalog.nextSnapshotVersion(for: identity),
            question: question
        )
        let packet = ExplainerPrompt.packet(from: snapshot)
        await provider?.sendFunctionResult(id: id, name: name, content: packet)
        pendingSnapshotVersion = snapshot.version
        updateSink.yield(.snapshotApplied(
            version: snapshot.version,
            cutoff: snapshot.sourceCutoff,
            limitations: snapshot.limitations
        ))
    }

    // MARK: - Transcript polling

    private func startPollLoop(generation gen: Int) {
        pollLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(2))
                guard let self, !Task.isCancelled, await self.isCurrent(gen) else { return }
                await self.pollOnce()
            }
        }
    }

    private func pollOnce() async {
        guard let identity = selectedSession else { return }
        guard let delta = try? await catalog.poll(identity) else { return }
        if delta.reparsed {
            updateSink.yield(.newActivityAvailable)
            return
        }
        guard !delta.newEvents.isEmpty else { return }
        // Tell the model newer evidence exists; the tool call carries truth.
        await provider?.updateSystemPrompt(ExplainerPrompt.freshnessNote(
            cutoff: delta.activity.lastEventAt
        ))
        updateSink.yield(.newActivityAvailable)
    }

    // MARK: - Turn accounting

    private func recordUserTurn(question: String) {
        guard let identity = selectedSession, let conversationID else { return }
        let turn = ObserverTurn(
            conversationID: conversationID,
            session: identity,
            question: question,
            snapshotVersion: pendingSnapshotVersion,
            state: .answering
        )
        turns[identity, default: []].append(turn)
        openTurnID = turn.id
    }

    private func recordAssistantAnswer(_ text: String) {
        guard let identity = selectedSession,
              let id = openTurnID,
              var list = turns[identity],
              let idx = list.lastIndex(where: { $0.id == id }) else { return }
        list[idx].response = text
        list[idx].state = .answered
        // The answer's evidence basis is the newest snapshot actually applied,
        // which may be newer than the version bound when the question started.
        list[idx].snapshotVersion = pendingSnapshotVersion
        turns[identity] = list
    }

    private func contextMessages(for identity: SessionIdentity) -> [VoiceContextMessage] {
        Array(
            (turns[identity] ?? [])
                .filter { $0.state == .answered }
                .flatMap { [
                    VoiceContextMessage(role: .user, content: $0.question),
                    VoiceContextMessage(role: .assistant, content: $0.response),
                ] }
                .suffix(12)
        )
    }

    private func setStatus(_ new: Status) {
        guard status != new else { return }
        status = new
        updateSink.yield(.status(new))
    }
}
