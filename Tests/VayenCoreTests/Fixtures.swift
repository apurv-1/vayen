import Foundation
@testable import VayenCore

/// Synthetic Claude Code transcript records. Entirely fabricated; no real
/// session content is ever used as a fixture.
enum Fixture {

    static func userPrompt(uuid: String = "u1", text: String, session: String = "s1", ts: String, cwd: String = "/tmp/proj") -> String {
        """
        {"type":"user","sessionId":"\(session)","uuid":"\(uuid)","parentUuid":null,"cwd":"\(cwd)","timestamp":"\(ts)","userType":"external","isSidechain":false,"version":"2.1.267","message":{"role":"user","content":\(jsonString(text))}}
        """
    }

    static func userBlocks(uuid: String = "u2", session: String = "s1", ts: String, blocks: String) -> String {
        """
        {"type":"user","sessionId":"\(session)","uuid":"\(uuid)","cwd":"/tmp/proj","timestamp":"\(ts)","userType":"external","isSidechain":false,"version":"2.1.267","message":{"role":"user","content":[\(blocks)]}}
        """
    }

    static func toolResultBlock(toolUseID: String, text: String, isError: Bool = false) -> String {
        """
        {"type":"tool_result","tool_use_id":"\(toolUseID)","content":\(jsonString(text)),"is_error":\(isError)}
        """
    }

    static func assistant(uuid: String, session: String = "s1", ts: String, blocks: [String], stop: String? = nil) -> String {
        let stopField = stop.map { ",\"stop_reason\":\"\($0)\"" } ?? ""
        return """
        {"type":"assistant","sessionId":"\(session)","uuid":"\(uuid)","cwd":"/tmp/proj","timestamp":"\(ts)","isSidechain":false,"version":"2.1.267","message":{"role":"assistant","content":[\(blocks.joined(separator: ","))],"model":"claude-opus"\(stopField)}}
        """
    }

    static func textBlock(_ text: String) -> String {
        "{\"type\":\"text\",\"text\":\(jsonString(text))}"
    }

    static func thinkingBlock(_ text: String) -> String {
        "{\"type\":\"thinking\",\"thinking\":\(jsonString(text)),\"signature\":\"sig\"}"
    }

    static func toolUseBlock(id: String, name: String, input: String) -> String {
        "{\"type\":\"tool_use\",\"id\":\"\(id)\",\"name\":\"\(name)\",\"input\":\(input)}"
    }

    static func system(subtype: String, session: String = "s1", ts: String) -> String {
        "{\"type\":\"system\",\"subtype\":\"\(subtype)\",\"sessionId\":\"\(session)\",\"timestamp\":\"\(ts)\"}"
    }

    static func customTitle(_ title: String, session: String = "s1") -> String {
        "{\"type\":\"custom-title\",\"sessionId\":\"\(session)\",\"customTitle\":\(jsonString(title))}"
    }

    static func aiTitle(_ title: String, session: String = "s1") -> String {
        "{\"type\":\"ai-title\",\"sessionId\":\"\(session)\",\"aiTitle\":\(jsonString(title))}"
    }

    static func metadata(_ type: String) -> String {
        "{\"type\":\"\(type)\",\"sessionId\":\"s1\",\"timestamp\":\"2026-09-14T10:00:00.000Z\"}"
    }

    static func compactSummaryUser(uuid: String = "uc", session: String = "s1", ts: String, text: String) -> String {
        """
        {"type":"user","sessionId":"\(session)","uuid":"\(uuid)","cwd":"/tmp/proj","timestamp":"\(ts)","isCompactSummary":true,"isSidechain":false,"version":"2.1.267","message":{"role":"user","content":\(jsonString(text))}}
        """
    }

    static func jsonString(_ s: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["v": s])
        let obj = String(data: data, encoding: .utf8)!
        // Extract just the encoded string literal.
        let start = obj.index(obj.firstIndex(of: ":")!, offsetBy: 1)
        let end = obj.index(before: obj.endIndex)
        return String(obj[start..<end])
    }

    /// Writes lines to a temp JSONL file under a `<root>/<project>/` layout and
    /// returns its URL.
    static func writeTranscript(
        lines: [String],
        project: String = "-tmp-proj",
        sessionID: String = "11111111-2222-3333-4444-555555555555",
        root: URL
    ) throws -> URL {
        let dir = root.appendingPathComponent(project, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(sessionID).jsonl")
        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    static func tempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vayen-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
