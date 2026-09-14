import Foundation

/// Codable models for the Deepgram Voice Agent v1 WebSocket protocol.
/// Endpoint: wss://agent.deepgram.com/v1/agent/converse
/// Auth: `Authorization: Token <key>` header, or `token, <key>` subprotocol.
public enum DeepgramAgent {

    // MARK: - Client → server

    public struct Settings: Encodable, Sendable {
        public var type = "Settings"
        public var audio: Audio
        public var agent: Agent
        public var mipOptOut: Bool?

        enum CodingKeys: String, CodingKey {
            case type, audio, agent
            case mipOptOut = "mip_opt_out"
        }

        public struct Audio: Encodable, Sendable {
            public var input: Input
            public var output: Output

            public struct Input: Encodable, Sendable {
                public var encoding: String
                public var sampleRate: Int
                enum CodingKeys: String, CodingKey {
                    case encoding
                    case sampleRate = "sample_rate"
                }
            }
            public struct Output: Encodable, Sendable {
                public var encoding: String
                public var sampleRate: Int
                public var container: String
                enum CodingKeys: String, CodingKey {
                    case encoding
                    case sampleRate = "sample_rate"
                    case container
                }
            }
        }

        public struct Agent: Encodable, Sendable {
            public var listen: Listen
            public var think: Think
            public var speak: Speak
            public var greeting: String?
            public var context: Context?

            public struct Listen: Encodable, Sendable {
                public var provider: ListenProvider
            }
            public struct ListenProvider: Encodable, Sendable {
                public var type = "deepgram"
                public var version: String
                public var model: String
                public var language: String?
                public var smartFormat: Bool?
                enum CodingKeys: String, CodingKey {
                    case type, version, model, language
                    case smartFormat = "smart_format"
                }
            }
            public struct Think: Encodable, Sendable {
                public var provider: ThinkProvider
                public var prompt: String
                public var functions: [Function]?

                public struct ThinkProvider: Encodable, Sendable {
                    public var type: String
                    public var model: String
                    public var temperature: Double?
                }
                public struct Function: Encodable, Sendable {
                    public var name: String
                    public var description: String
                    /// JSON Schema object decoded verbatim into the message.
                    public var parameters: JSONValue?
                }
            }
            public struct Speak: Encodable, Sendable {
                public var provider: SpeakProvider
                public struct SpeakProvider: Encodable, Sendable {
                    public var type = "deepgram"
                    public var version: String?
                    public var model: String
                }
            }
            public struct Context: Encodable, Sendable {
                public var messages: [HistoryMessage]
            }
        }

        public struct HistoryMessage: Encodable, Sendable {
            public var type = "History"
            public var role: String
            public var content: String
        }
    }

    public struct UpdatePrompt: Encodable, Sendable {
        public var type = "UpdatePrompt"
        public var prompt: String
        public init(prompt: String) { self.prompt = prompt }
    }

    public struct InjectUserMessage: Encodable, Sendable {
        public var type = "InjectUserMessage"
        public var content: String
        public init(content: String) { self.content = content }
    }

    public struct FunctionCallResponse: Encodable, Sendable {
        public var type = "FunctionCallResponse"
        public var id: String
        public var name: String
        public var content: String
        public init(id: String, name: String, content: String) {
            self.id = id; self.name = name; self.content = content
        }
    }

    public struct KeepAlive: Encodable, Sendable {
        public var type = "KeepAlive"
        public init() {}
    }

    // MARK: - Server → client

    /// Tagged decode of server JSON messages. Binary frames are audio and are
    /// handled by the transport, not this codec.
    public enum ServerMessage: Sendable {
        case welcome(requestID: String?)
        case settingsApplied
        case conversationText(role: String, content: String)
        case userStartedSpeaking
        case agentThinking(content: String)
        case functionCallRequest(calls: [RequestedFunction])
        case functionCallCancelled(calls: [CancelledFunction])
        case agentStartedSpeaking(totalLatency: Double?, ttsLatency: Double?, thinkLatency: Double?)
        case agentAudioDone
        case injectionRefused
        case error(description: String, code: String?)
        case warning(description: String, code: String?)
        case listenUpdated, thinkUpdated, speakUpdated, promptUpdated
        case history
        case unknown(String)

        public struct RequestedFunction: Sendable {
            public var id: String
            public var name: String
            public var arguments: String
            public var clientSide: Bool
        }
        public struct CancelledFunction: Sendable {
            public var id: String
            public var name: String
        }
    }

    public enum Codec {
        public static func decodeServer(_ text: String) -> ServerMessage {
            guard let data = text.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String else {
                return .unknown("unparseable")
            }
            func str(_ key: String) -> String? { obj[key] as? String }
            func dbl(_ key: String) -> Double? {
                if let s = obj[key] as? String { return Double(s) }
                return obj[key] as? Double
            }
            switch type {
            case "Welcome":
                return .welcome(requestID: str("request_id"))
            case "SettingsApplied":
                return .settingsApplied
            case "ConversationText":
                return .conversationText(role: str("role") ?? "assistant", content: str("content") ?? "")
            case "UserStartedSpeaking":
                return .userStartedSpeaking
            case "AgentThinking":
                return .agentThinking(content: str("content") ?? "")
            case "FunctionCallRequest":
                let rawCalls = (obj["functions"] as? [[String: Any]]) ?? []
                let calls = rawCalls.map { raw in
                    ServerMessage.RequestedFunction(
                        id: raw["id"] as? String ?? "",
                        name: raw["name"] as? String ?? "",
                        arguments: raw["arguments"] as? String ?? "{}",
                        clientSide: raw["client_side"] as? Bool ?? true
                    )
                }
                return .functionCallRequest(calls: calls)
            case "FunctionCallCancelled":
                let rawCalls = (obj["functions"] as? [[String: Any]]) ?? []
                let calls = rawCalls.map { raw in
                    ServerMessage.CancelledFunction(
                        id: raw["id"] as? String ?? "",
                        name: raw["name"] as? String ?? ""
                    )
                }
                return .functionCallCancelled(calls: calls)
            case "AgentStartedSpeaking":
                return .agentStartedSpeaking(
                    totalLatency: dbl("total_latency"),
                    ttsLatency: dbl("tts_latency"),
                    thinkLatency: dbl("ttt_latency")
                )
            case "AgentAudioDone":
                return .agentAudioDone
            case "InjectionRefused":
                return .injectionRefused
            case "Error":
                return .error(description: str("description") ?? "unknown error", code: str("code"))
            case "Warning":
                return .warning(description: str("description") ?? "", code: str("code"))
            case "ListenUpdated": return .listenUpdated
            case "ThinkUpdated": return .thinkUpdated
            case "SpeakUpdated": return .speakUpdated
            case "PromptUpdated": return .promptUpdated
            case "History": return .history
            default:
                return .unknown(type)
            }
        }
    }
}
