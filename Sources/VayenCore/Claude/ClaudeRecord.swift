import Foundation

/// Tolerant decode of one Claude Code JSONL line.
/// Only the fields Vayen consumes are modeled; unknown record kinds and missing
/// optional fields are preserved as provenance, never fatal.
public struct ClaudeRecord: Decodable, Sendable {
    public var type: String
    public var sessionId: String?
    public var timestamp: String?
    public var uuid: String?
    public var parentUuid: String?
    public var cwd: String?
    public var version: String?
    public var isSidechain: Bool?
    public var userType: String?
    public var promptSource: String?
    public var promptId: String?
    public var isMeta: Bool?
    public var isCompactSummary: Bool?
    public var agentId: String?
    public var message: ClaudeMessage?
    public var customTitle: String?
    public var aiTitle: String?
    public var subtype: String?
    public var slug: String?
}

public struct ClaudeMessage: Decodable, Sendable {
    public var role: String?
    public var content: ClaudeContent?
    public var model: String?
    public var stopReason: String?

    enum CodingKeys: String, CodingKey {
        case role, content, model
        case stopReason = "stop_reason"
    }
}

/// `message.content` may be a plain string or an array of typed blocks.
public enum ClaudeContent: Decodable, Sendable {
    case string(String)
    case blocks([ClaudeContentBlock])
    case other

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let blocks = try? container.decode([ClaudeContentBlock].self) {
            self = .blocks(blocks)
        } else {
            _ = try? container.decode(JSONValue.self)
            self = .other
        }
    }
}

/// A typed message block. Fields are optional because each block kind uses a
/// different subset; anything unrecognized survives only as its `type` name.
public struct ClaudeContentBlock: Decodable, Sendable {
    public var type: String?
    public var text: String?
    public var thinking: String?
    public var id: String?
    public var name: String?
    public var input: JSONValue?
    public var toolUseID: String?
    public var content: ClaudeContent?
    public var isError: Bool?
    public var imageMediaType: String?

    enum CodingKeys: String, CodingKey {
        case type, text, thinking, id, name, input, content
        case toolUseID = "tool_use_id"
        case isError = "is_error"
        case imageMediaType = "media_type"
        case source
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        text = try container.decodeIfPresent(String.self, forKey: .text)
        thinking = try container.decodeIfPresent(String.self, forKey: .thinking)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        input = try container.decodeIfPresent(JSONValue.self, forKey: .input)
        toolUseID = try container.decodeIfPresent(String.self, forKey: .toolUseID)
        content = try container.decodeIfPresent(ClaudeContent.self, forKey: .content)
        isError = try container.decodeIfPresent(Bool.self, forKey: .isError)
        imageMediaType = try container.decodeIfPresent(String.self, forKey: .imageMediaType)
        // Image blocks carry source.media_type rather than a top-level media_type.
        if imageMediaType == nil,
           let source = try? container.decodeIfPresent([String: JSONValue].self, forKey: .source),
           case .string(let mt)? = source["media_type"] {
            imageMediaType = mt
        }
    }
}

public enum ClaudeRecordDecode {
    /// Parse one complete JSONL line. Returns nil for blank or invalid JSON lines;
    /// a record with type "unknown" never occurs because `type` is required.
    public static func parse(line: Data) -> ClaudeRecord? {
        guard !line.isEmpty else { return nil }
        let decoder = JSONDecoder()
        return try? decoder.decode(ClaudeRecord.self, from: line)
    }

    /// ISO-8601 with optional fractional seconds, as written by Claude Code.
    /// `Date.ISO8601FormatStyle` is a value type and Sendable-safe.
    public static func timestamp(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let d = try? Date(raw, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return d
        }
        return try? Date(raw, strategy: .iso8601)
    }
}
