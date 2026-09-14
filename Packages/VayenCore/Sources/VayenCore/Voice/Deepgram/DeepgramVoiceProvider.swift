import Foundation

public enum VoiceProviderError: Error, Sendable {
    case missingAPIKey
    case connectionFailed(String)
    case notConnected
    case sendFailed(String)
}

/// Deepgram Voice Agent v1 over a bare WebSocket.
///
/// One socket carries control JSON both ways, linear16 microphone audio out,
/// and linear16 agent audio back. Client-side function calls arrive as
/// `FunctionCallRequest` and block the model until `FunctionCallResponse`.
///
/// Threading: the provider is an actor for connection state; `sendAudio` is
/// deliberately nonisolated so the AVAudioEngine tap can feed it without
/// spawning a task per chunk. Ordering is preserved by the FIFO audio stream.
public actor DeepgramVoiceProvider: VoiceProvider {

    public struct Configuration: Sendable {
        public var apiKey: String
        public var endpoint: URL
        /// Deepgram listen (STT) model. v1 nova-3 or v2 flux-general-en.
        public var listenModel: String
        public var listenVersion: String
        /// Think provider + model billed through the user's Deepgram account.
        public var thinkProvider: String
        public var thinkModel: String
        public var temperature: Double?
        /// Deepgram TTS voice (aura-*/flux-*).
        public var speakModel: String
        public var speakVersion: String?
        public var inputSampleRate: Int
        public var outputSampleRate: Int

        public init(
            apiKey: String,
            endpoint: URL = URL(string: "wss://agent.deepgram.com/v1/agent/converse")!,
            listenModel: String = "nova-3",
            listenVersion: String = "v1",
            thinkProvider: String = "open_ai",
            thinkModel: String = "gpt-4.1-mini",
            temperature: Double? = nil,
            speakModel: String = "aura-2-thalia-en",
            speakVersion: String? = "v1",
            inputSampleRate: Int = 16_000,
            outputSampleRate: Int = 24_000
        ) {
            self.apiKey = apiKey
            self.endpoint = endpoint
            self.listenModel = listenModel
            self.listenVersion = listenVersion
            self.thinkProvider = thinkProvider
            self.thinkModel = thinkModel
            self.temperature = temperature
            self.speakModel = speakModel
            self.speakVersion = speakVersion
            self.inputSampleRate = inputSampleRate
            self.outputSampleRate = outputSampleRate
        }
    }

    private let configuration: Configuration

    // nonisolated: continuation-yield is thread-safe and ordering is FIFO.
    nonisolated public let events: AsyncStream<VoiceEvent>
    private let eventSink: AsyncStream<VoiceEvent>.Continuation

    private let audioOutStream: AsyncStream<Data>
    private let audioOutSink: AsyncStream<Data>.Continuation

    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var receiveLoop: Task<Void, Never>?
    private var sendLoop: Task<Void, Never>?
    private var keepAliveLoop: Task<Void, Never>?
    private var connected = false

    public init(configuration: Configuration) {
        self.configuration = configuration
        var sink: AsyncStream<VoiceEvent>.Continuation!
        self.events = AsyncStream { sink = $0 }
        self.eventSink = sink
        var audioSink: AsyncStream<Data>.Continuation!
        self.audioOutStream = AsyncStream { audioSink = $0 }
        self.audioOutSink = audioSink
    }

    /// FIFO enqueue for microphone audio. Safe from realtime audio threads.
    nonisolated public func sendAudio(_ data: Data) {
        audioOutSink.yield(data)
    }

    public func connect(config: VoiceSessionConfig) async throws {
        guard !configuration.apiKey.isEmpty else { throw VoiceProviderError.missingAPIKey }

        var request = URLRequest(url: configuration.endpoint)
        request.setValue("Token \(configuration.apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .ephemeral)
        let task = session.webSocketTask(with: request)
        self.session = session
        self.task = task
        task.resume()

        sendLoop = Task { [weak self, audioOutStream] in
            for await chunk in audioOutStream {
                guard let self else { return }
                guard await self.sendAudioChunk(chunk) else { return }
            }
        }

        receiveLoop = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoopBody()
        }

        try await sendSettings(config: config)

        keepAliveLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(8))
                guard !Task.isCancelled else { return }
                await self?.sendKeepAlive()
            }
        }
        connected = true
    }

    private func sendSettings(config: VoiceSessionConfig) async throws {
        var think = DeepgramAgent.Settings.Agent.Think(
            provider: .init(
                type: configuration.thinkProvider,
                model: configuration.thinkModel,
                temperature: configuration.temperature
            ),
            prompt: config.systemPrompt,
            functions: nil
        )
        if !config.functions.isEmpty {
            think.functions = config.functions.map { spec in
                DeepgramAgent.Settings.Agent.Think.Function(
                    name: spec.name,
                    description: spec.description,
                    parameters: (try? JSONDecoder().decode(JSONValue.self, from: Data(spec.parametersJSON.utf8)))
                )
            }
        }

        let context: DeepgramAgent.Settings.Agent.Context? = config.contextMessages.isEmpty ? nil : .init(
            messages: config.contextMessages.map {
                .init(role: $0.role.rawValue, content: $0.content)
            }
        )

        let settings = DeepgramAgent.Settings(
            audio: .init(
                input: .init(encoding: "linear16", sampleRate: configuration.inputSampleRate),
                output: .init(encoding: "linear16", sampleRate: configuration.outputSampleRate, container: "none")
            ),
            agent: .init(
                listen: .init(provider: .init(
                    version: configuration.listenVersion,
                    model: configuration.listenModel,
                    language: "en",
                    smartFormat: true
                )),
                think: think,
                speak: .init(provider: .init(
                    version: configuration.speakVersion,
                    model: configuration.speakModel
                )),
                greeting: config.greeting,
                context: context
            ),
            mipOptOut: true
        )

        let data = try JSONEncoder().encode(settings)
        guard let text = String(data: data, encoding: .utf8) else {
            throw VoiceProviderError.sendFailed("settings encode")
        }
        try await task?.send(.string(text))
    }

    private func receiveLoopBody() async {
        while !Task.isCancelled {
            guard let task else { return }
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    handle(text: text)
                case .data(let data):
                    eventSink.yield(.agentAudio(data))
                @unknown default:
                    break
                }
            } catch {
                if !Task.isCancelled {
                    eventSink.yield(.disconnected(reason: error.localizedDescription))
                    finish()
                }
                return
            }
        }
    }

    private func handle(text: String) {
        switch DeepgramAgent.Codec.decodeServer(text) {
        case .welcome:
            break
        case .settingsApplied:
            eventSink.yield(.connected)
        case .conversationText(let role, let content):
            eventSink.yield(.conversationText(
                role: role == "user" ? .user : .assistant, text: content
            ))
        case .userStartedSpeaking:
            eventSink.yield(.userStartedSpeaking)
        case .agentThinking(let content):
            eventSink.yield(.agentThinking(content))
        case .functionCallRequest(let calls):
            for call in calls where call.clientSide {
                eventSink.yield(.functionCall(id: call.id, name: call.name, argumentsJSON: call.arguments))
            }
        case .functionCallCancelled(let calls):
            for call in calls {
                eventSink.yield(.functionCallCancelled(id: call.id, name: call.name))
            }
        case .agentStartedSpeaking(let total, let tts, let think):
            eventSink.yield(.agentAudioStarted(totalLatency: total, ttsLatency: tts, thinkLatency: think))
        case .agentAudioDone:
            eventSink.yield(.agentAudioDone)
        case .injectionRefused:
            eventSink.yield(.injectionRefused)
        case .error(let description, let code):
            eventSink.yield(.failure("\(code ?? "error"): \(description)"))
        case .warning(let description, _):
            eventSink.yield(.providerWarning(description))
        case .listenUpdated, .thinkUpdated, .speakUpdated, .promptUpdated, .history:
            break
        case .unknown(let type):
            eventSink.yield(.providerWarning("unhandled server message: \(type)"))
        }
    }

    public func sendUserText(_ text: String) async {
        await send(DeepgramAgent.InjectUserMessage(content: text))
    }

    public func updateSystemPrompt(_ prompt: String) async {
        await send(DeepgramAgent.UpdatePrompt(prompt: prompt))
    }

    public func sendFunctionResult(id: String, name: String, content: String) async {
        await send(DeepgramAgent.FunctionCallResponse(id: id, name: name, content: content))
    }

    private func sendKeepAlive() async {
        await send(DeepgramAgent.KeepAlive())
    }

    private func send<T: Encodable>(_ message: T) async {
        guard connected, let task else { return }
        guard let data = try? JSONEncoder().encode(message),
              let text = String(data: data, encoding: .utf8) else { return }
        try? await task.send(.string(text))
    }

    /// Actor-isolated send for FIFO audio chunks from the send loop.
    private func sendAudioChunk(_ data: Data) async -> Bool {
        guard let task else { return false }
        do {
            try await task.send(.data(data))
            return true
        } catch {
            return false
        }
    }

    /// Total teardown: no event may reach the stream after this returns.
    public func disconnect() async {
        connected = false
        keepAliveLoop?.cancel()
        sendLoop?.cancel()
        receiveLoop?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        finish()
    }

    private func finish() {
        eventSink.finish()
        audioOutSink.finish()
    }
}
