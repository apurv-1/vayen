import Foundation
import Testing
@testable import VayenCore

@Suite("Deepgram agent protocol codec")
struct DeepgramCodecTests {

    @Test func settingsEncodesProvidersAndFunctions() throws {
        let settings = DeepgramAgent.Settings(
            audio: .init(
                input: .init(encoding: "linear16", sampleRate: 16000),
                output: .init(encoding: "linear16", sampleRate: 24000, container: "none")
            ),
            agent: .init(
                listen: .init(provider: .init(version: "v1", model: "nova-3", language: "en", smartFormat: true)),
                think: .init(
                    provider: .init(type: "open_ai", model: "gpt-4.1-mini", temperature: nil),
                    prompt: "prompt",
                    functions: [.init(
                        name: "get_selected_session_evidence",
                        description: "d",
                        parameters: .object(["type": .string("object")])
                    )]
                ),
                speak: .init(provider: .init(version: "v1", model: "aura-2-thalia-en")),
                greeting: nil,
                context: nil
            ),
            mipOptOut: true
        )
        let data = try JSONEncoder().encode(settings)
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["type"] as? String == "Settings")
        let audio = try #require(obj["audio"] as? [String: Any])
        #expect((audio["input"] as? [String: Any])?["sample_rate"] as? Int == 16000)
        let agent = try #require(obj["agent"] as? [String: Any])
        let think = try #require(agent["think"] as? [String: Any])
        let provider = try #require(think["provider"] as? [String: Any])
        #expect(provider["type"] as? String == "open_ai")
        let functions = try #require(think["functions"] as? [[String: Any]])
        #expect(functions[0]["name"] as? String == "get_selected_session_evidence")
        #expect(obj["mip_opt_out"] as? Bool == true)
    }

    @Test func decodesConversationText() {
        let msg = DeepgramAgent.Codec.decodeServer(#"{"type":"ConversationText","role":"user","content":"what are you doing"}"#)
        guard case .conversationText(let role, let content) = msg else { Issue.record(); return }
        #expect(role == "user")
        #expect(content == "what are you doing")
    }

    @Test func decodesFunctionCallRequest() {
        let msg = DeepgramAgent.Codec.decodeServer(#"""
        {"type":"FunctionCallRequest","functions":[{"id":"f1","name":"get_selected_session_evidence","arguments":"{\"question\":\"files\"}","client_side":true}]}
        """#)
        guard case .functionCallRequest(let calls) = msg else { Issue.record(); return }
        #expect(calls.count == 1)
        #expect(calls[0].id == "f1")
        #expect(calls[0].clientSide)
        #expect(calls[0].arguments.contains("files"))
    }

    @Test func decodesAgentStartedSpeakingLatencies() {
        let msg = DeepgramAgent.Codec.decodeServer(#"{"type":"AgentStartedSpeaking","total_latency":"1.23","tts_latency":"0.4","ttt_latency":"0.5"}"#)
        guard case .agentStartedSpeaking(let total, let tts, let think) = msg else { Issue.record(); return }
        #expect(total == 1.23); #expect(tts == 0.4); #expect(think == 0.5)
    }

    @Test func decodesErrorAndCancel() {
        guard case .error(let d, let code) = DeepgramAgent.Codec.decodeServer(#"{"type":"Error","description":"bad","code":"E_X"}"#) else {
            Issue.record(); return
        }
        #expect(d == "bad"); #expect(code == "E_X")

        guard case .functionCallCancelled(let calls) = DeepgramAgent.Codec.decodeServer(#"{"type":"FunctionCallCancelled","functions":[{"id":"f9","name":"get_selected_session_evidence"}]}"#) else {
            Issue.record(); return
        }
        #expect(calls[0].id == "f9")
    }

    @Test func decodesUserStartedSpeakingAndAudioDone() {
        guard case .userStartedSpeaking = DeepgramAgent.Codec.decodeServer(#"{"type":"UserStartedSpeaking"}"#) else {
            Issue.record(); return
        }
        guard case .agentAudioDone = DeepgramAgent.Codec.decodeServer(#"{"type":"AgentAudioDone"}"#) else {
            Issue.record(); return
        }
        guard case .unknown = DeepgramAgent.Codec.decodeServer(#"{"type":"SomeFutureMessage"}"#) else {
            Issue.record(); return
        }
    }
}
