import Foundation

public enum ConversationRole: String, Sendable {
    case user, assistant
}

/// Events a voice provider surfaces to the conversation coordinator.
/// Provider-agnostic: no Deepgram or ElevenLabs types leak past this enum.
public enum VoiceEvent: Sendable {
    /// Transport connected and session settings accepted.
    case connected
    /// The provider detected the user starting to speak (barge-in signal).
    case userStartedSpeaking
    /// A finalized transcript line for either side of the conversation.
    case conversationText(role: ConversationRole, text: String)
    /// Provider reported intermediate thinking text (not always available).
    case agentThinking(String)
    /// The model asked for a client-side tool. `argumentsJSON` is a raw JSON string.
    case functionCall(id: String, name: String, argumentsJSON: String)
    /// A previously dispatched function call was cancelled (e.g. user barge-in).
    case functionCallCancelled(id: String, name: String)
    /// Agent TTS audio is starting. Carries measured latencies when reported.
    case agentAudioStarted(totalLatency: Double?, ttsLatency: Double?, thinkLatency: Double?)
    /// A chunk of agent audio in `outputFormat`.
    case agentAudio(Data)
    /// Agent finished sending audio for the current response.
    case agentAudioDone
    /// A context/prompt injection was refused by the provider.
    case injectionRefused
    case providerWarning(String)
    /// Terminal provider or transport error.
    case failure(String)
    /// Transport closed.
    case disconnected(reason: String?)
}

/// A client-side function the voice model may invoke.
/// `parametersJSON` is a JSON Schema object serialized to a string.
public struct VoiceFunctionSpec: Sendable {
    public var name: String
    public var description: String
    public var parametersJSON: String

    public init(name: String, description: String, parametersJSON: String) {
        self.name = name
        self.description = description
        self.parametersJSON = parametersJSON
    }
}

/// Prior observer-conversation text carried into a fresh connection.
public struct VoiceContextMessage: Sendable {
    public var role: ConversationRole
    public var content: String

    public init(role: ConversationRole, content: String) {
        self.role = role
        self.content = content
    }
}

/// Everything a provider needs to open one conversation.
public struct VoiceSessionConfig: Sendable {
    public var systemPrompt: String
    public var functions: [VoiceFunctionSpec]
    public var contextMessages: [VoiceContextMessage]
    public var greeting: String?

    public init(
        systemPrompt: String,
        functions: [VoiceFunctionSpec] = [],
        contextMessages: [VoiceContextMessage] = [],
        greeting: String? = nil
    ) {
        self.systemPrompt = systemPrompt
        self.functions = functions
        self.contextMessages = contextMessages
        self.greeting = greeting
    }
}

/// Boundary for a conversational voice transport.
///
/// Implementations own the socket/session only; microphone capture and audio
/// playback live in the app-side audio pipeline. Cancellation must be total:
/// after `disconnect()` no event may reach the coordinator.
public protocol VoiceProvider: Sendable {
    /// Stream of provider events. Ends when the connection closes.
    var events: AsyncStream<VoiceEvent> { get }

    /// Open the transport and apply the session configuration.
    func connect(config: VoiceSessionConfig) async throws

    /// Enqueue one chunk of microphone audio (linear16 PCM at the configured
    /// rate). Synchronous and FIFO-ordered so it is safe to call from an audio
    /// tap callback.
    func sendAudio(_ data: Data)

    /// Send a text turn through the same think pipeline (text fallback / debug).
    func sendUserText(_ text: String) async

    /// Replace the system prompt mid-conversation (freshness hints).
    func updateSystemPrompt(_ prompt: String) async

    /// Return a client-side function result for a pending `functionCall`.
    func sendFunctionResult(id: String, name: String, content: String) async

    /// End the conversation: stop transport and complete the event stream.
    func disconnect() async
}
