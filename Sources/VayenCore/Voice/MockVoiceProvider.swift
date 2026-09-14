import Foundation

/// Deterministic in-process voice provider for tests and no-key UI runs.
///
/// `responder` receives the user's text and an async `fetchEvidence` closure it
/// may call to simulate the model invoking the evidence function; calling it
/// emits the same function-call/response path a real provider uses.
public actor MockVoiceProvider: VoiceProvider {

    public nonisolated let events: AsyncStream<VoiceEvent>
    private let eventSink: AsyncStream<VoiceEvent>.Continuation

    private var connected = false
    private var config: VoiceSessionConfig?
    /// In-flight function call ids awaiting results, in order.
    private var pendingCalls: [(id: String, name: String)] = []

    public typealias Responder = @Sendable (String, @Sendable () async -> String) async -> String
    private let responder: Responder

    /// When true, each user turn emits a `get_selected_session_evidence`
    /// function call and the responder receives its result.
    private let callsEvidenceTool: Bool

    public init(
        callsEvidenceTool: Bool = false,
        responder: @escaping Responder = { question, fetch in
            let evidence = await fetch()
            return "I see evidence snapshot data (\(evidence.count) chars) for your question."
        }
    ) {
        self.callsEvidenceTool = callsEvidenceTool
        self.responder = responder
        var sink: AsyncStream<VoiceEvent>.Continuation!
        self.events = AsyncStream { sink = $0 }
        self.eventSink = sink
    }

    public func connect(config: VoiceSessionConfig) async throws {
        self.config = config
        connected = true
        eventSink.yield(.connected)
    }

    public nonisolated func sendAudio(_ data: Data) {}

    public func sendUserText(_ text: String) async {
        guard connected else { return }
        eventSink.yield(.conversationText(role: .user, text: text))
        eventSink.yield(.agentThinking(""))

        let answer = await responder(text) { [weak self] in
            await self?.requestEvidence(question: text) ?? ""
        }
        eventSink.yield(.agentAudioStarted(totalLatency: nil, ttsLatency: nil, thinkLatency: nil))
        eventSink.yield(.conversationText(role: .assistant, text: answer))
        eventSink.yield(.agentAudioDone)
    }

    private func requestEvidence(question: String) async -> String {
        guard connected else { return "" }
        let id = UUID().uuidString
        pendingCalls.append((id, "get_selected_session_evidence"))
        let args = (try? JSONSerialization.data(withJSONObject: ["question": question]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        eventSink.yield(.functionCall(
            id: id,
            name: "get_selected_session_evidence",
            argumentsJSON: args
        ))
        // Wait for the coordinator to answer; tests rely on this being
        // processed before the final assistant text.
        for _ in 0..<200 {
            if !pendingCalls.contains(where: { $0.id == id }) { break }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return lastFunctionResult
    }

    private var lastFunctionResult = ""

    public func sendFunctionResult(id: String, name: String, content: String) async {
        lastFunctionResult = content
        pendingCalls.removeAll { $0.id == id }
    }

    public func updateSystemPrompt(_ prompt: String) async {}

    public func disconnect() async {
        connected = false
        eventSink.finish()
    }
}
