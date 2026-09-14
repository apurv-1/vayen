import Foundation

/// Converts decoded Claude Code records into normalized events.
/// Pure and deterministic: one record may yield several events (a single
/// assistant record carries text plus tool calls), or none for metadata kinds.
public enum ClaudeNormalizer {

    public struct Result: Sendable {
        public var events: [NormalizedEvent]
        /// Record carried an assistant `stop_reason: end_turn` at this time.
        /// Not task completion.
        public var turnEndAt: Date? = nil

        public init(events: [NormalizedEvent], turnEndAt: Date? = nil) {
            self.events = events
            self.turnEndAt = turnEndAt
        }
    }

    /// Record kinds that are meaningful transcript evidence vs known-ignored metadata.
    /// Anything else is counted as unsupported by the caller.
    public static let knownMetadataKinds: Set<String> = [
        "queue-operation", "last-prompt", "mode", "atis-latch", "permission-mode",
        "cost-state", "file-history-snapshot", "snapshot-link", "hook",
    ]

    public static func normalize(
        record: ClaudeRecord,
        fileKey: String,
        generation: Int,
        recordIndex: Int
    ) -> Result {
        let timestamp = ClaudeRecordDecode.timestamp(record.timestamp)
        let sidechain = record.isSidechain ?? false
        let ref = { (blockIndex: Int?) -> SourceReference in
            SourceReference(
                fileKey: fileKey, generation: generation, recordIndex: recordIndex,
                blockIndex: blockIndex, eventID: record.uuid
            )
        }
        let base = { (actor: EventActor, kind: EventKind, content: EventContent, blockIndex: Int?) -> NormalizedEvent in
            NormalizedEvent(
                source: ref(blockIndex),
                eventID: record.uuid,
                parentID: record.parentUuid,
                timestamp: timestamp,
                actor: actor,
                kind: kind,
                content: content,
                isSidechain: sidechain,
                recordSessionID: record.sessionId,
                cwd: record.cwd,
                isCompactSummary: record.isCompactSummary ?? false
            )
        }

        switch record.type {
        case "user":
            return normalizeUser(record: record, base: base)
        case "assistant":
            return normalizeAssistant(record: record, base: base)
        case "system":
            let name = record.subtype ?? "system"
            return Result(events: [base(.system, .systemMarker, .marker(name: name, detail: nil), nil)])
        case "custom-title":
            // Marker name carries which title kind it was so callers can
            // prefer user-assigned titles over generated ones.
            return Result(events: [base(.system, .title, .marker(name: "custom-title", detail: record.customTitle ?? ""), nil)])
        case "ai-title":
            return Result(events: [base(.system, .title, .marker(name: "ai-title", detail: record.aiTitle ?? ""), nil)])
        case "attachment":
            return Result(events: [base(.user, .attachment, .marker(name: "attachment", detail: nil), nil)])
        default:
            if knownMetadataKinds.contains(record.type) {
                return Result(events: [base(.system, .metadata, .marker(name: record.type, detail: nil), nil)])
            }
            return Result(events: [base(.unknown, .unknown, .marker(name: record.type, detail: nil), nil)])
        }
    }

    private static func normalizeUser(
        record: ClaudeRecord,
        base: (EventActor, EventKind, EventContent, Int?) -> NormalizedEvent
    ) -> Result {
        if record.isMeta == true {
            return Result(events: [base(.system, .metadata, .marker(name: "meta", detail: nil), nil)])
        }

        let sidechain = record.isSidechain ?? false
        let isCompactSummary = record.isCompactSummary ?? false

        guard let content = record.message?.content else {
            return Result(events: [base(.user, .userMessage, .none, nil)])
        }

        switch content {
        case .string(let text):
            return Result(events: [userTextEvent(text, base: base, sidechain: sidechain, isCompactSummary: isCompactSummary, blockIndex: nil)])
        case .blocks(let blocks):
            var events: [NormalizedEvent] = []
            for (index, block) in blocks.enumerated() {
                switch block.type {
                case "tool_result":
                    events.append(base(.tool, .toolResult, toolResultContent(block), index))
                case "text":
                    if let text = block.text {
                        events.append(userTextEvent(text, base: base, sidechain: sidechain, isCompactSummary: isCompactSummary, blockIndex: index))
                    }
                case "image":
                    events.append(base(.user, .attachment, .imageRef(mediaType: block.imageMediaType), index))
                case "thinking":
                    events.append(base(.assistant, .thinking, .thinking, index))
                default:
                    if let text = block.text {
                        events.append(userTextEvent(text, base: base, sidechain: sidechain, isCompactSummary: isCompactSummary, blockIndex: index))
                    }
                }
            }
            if events.isEmpty {
                events.append(base(.user, .userMessage, .none, nil))
            }
            return Result(events: events)
        case .other:
            return Result(events: [base(.user, .userMessage, .none, nil)])
        }
    }

    /// A user-side text record is a real prompt unless it is sidechain traffic,
    /// a compaction summary, or slash-command markup. SDK-sourced prompts still
    /// count as task requests: they are the instruction the agent is executing.
    private static func userTextEvent(
        _ text: String,
        base: (EventActor, EventKind, EventContent, Int?) -> NormalizedEvent,
        sidechain: Bool,
        isCompactSummary: Bool,
        blockIndex: Int?
    ) -> NormalizedEvent {
        if isCompactSummary {
            return base(.system, .systemMarker, .marker(name: "compact_summary", detail: text), blockIndex)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<command-name>") || trimmed.hasPrefix("<local-command") || trimmed.hasPrefix("<command-message>") {
            // Slash-command envelope, e.g. `<command-name>/mcp</command-name>`.
            // Extract the command for display; never treat it as the task.
            let command = extractCommandName(trimmed)
            return base(.system, .metadata, .marker(name: "command", detail: command), blockIndex)
        }
        if sidechain {
            return base(.user, .userMessage, .text(text), blockIndex)
        }
        return base(.user, .userPrompt, .text(text), blockIndex)
    }

    private static func extractCommandName(_ text: String) -> String? {
        guard let start = text.range(of: "<command-name>"),
              let end = text.range(of: "</command-name>", range: start.upperBound..<text.endIndex)
        else { return nil }
        return String(text[start.upperBound..<end.lowerBound])
    }

    private static func normalizeAssistant(
        record: ClaudeRecord,
        base: (EventActor, EventKind, EventContent, Int?) -> NormalizedEvent
    ) -> Result {
        let turnEnd: Date? = record.message?.stopReason == "end_turn"
            ? ClaudeRecordDecode.timestamp(record.timestamp)
            : nil
        guard case .blocks(let blocks)? = record.message?.content else {
            if case .string(let text)? = record.message?.content {
                return Result(events: [base(.assistant, .assistantText, .text(text), nil)], turnEndAt: turnEnd)
            }
            return Result(events: [], turnEndAt: turnEnd)
        }

        var events: [NormalizedEvent] = []
        for (index, block) in blocks.enumerated() {
            switch block.type {
            case "text":
                if let text = block.text, !text.isEmpty {
                    events.append(base(.assistant, .assistantText, .text(text), index))
                }
            case "tool_use":
                let summary = summarizeToolInput(name: block.name ?? "tool", input: block.input)
                events.append(base(.assistant, .toolUse, .toolUse(name: block.name ?? "tool", summary: summary, toolUseID: block.id), index))
            case "thinking":
                events.append(base(.assistant, .thinking, .thinking, index))
            default:
                break
            }
        }
        return Result(events: events, turnEndAt: turnEnd)
    }

    private static func toolResultContent(_ block: ClaudeContentBlock) -> EventContent {
        let (excerpt, truncated) = boundedToolResultText(block.content)
        return .toolResult(
            toolUseID: block.toolUseID,
            excerpt: excerpt,
            isError: block.isError ?? false,
            truncated: truncated
        )
    }

    /// Tool results can be huge. Keep a bounded excerpt; the snapshot layer does
    /// its own budget enforcement on top.
    static let toolResultExcerptLimit = 800

    private static func boundedToolResultText(_ content: ClaudeContent?) -> (String, Bool) {
        let full: String
        switch content {
        case .string(let s): full = s
        case .blocks(let blocks):
            full = blocks.compactMap { $0.type == "text" ? $0.text : nil }.joined(separator: "\n")
        case .other, .none: full = ""
        }
        if full.count > toolResultExcerptLimit {
            return (String(full.prefix(toolResultExcerptLimit)) + "…", true)
        }
        return (full, false)
    }

    /// Short human-readable description of what a tool call was about.
    /// Reads only well-known scalar fields; never renders the full input.
    static func summarizeToolInput(name: String, input: JSONValue?) -> String {
        guard case .object(let object)? = input else { return "" }

        func scalar(_ key: String) -> String? {
            guard let value = object[key] else { return nil }
            switch value {
            case .string(let s): return s
            case .number, .bool: return value.compactDescription
            default: return nil
            }
        }

        // Highest-signal fields first, across the tools Claude Code emits most.
        for key in ["file_path", "path", "command", "pattern", "url", "description", "prompt", "query", "notebook_path", "skill"] {
            if let value = scalar(key), !value.isEmpty {
                return truncate(value, to: 160)
            }
        }
        // Fall back to the first scalar field for unfamiliar tools (e.g. MCP).
        for (key, value) in object.sorted(by: { $0.key < $1.key }) {
            switch value {
            case .string(let s) where !s.isEmpty:
                return truncate("\(key): \(s)", to: 160)
            case .number, .bool:
                return truncate("\(key): \(value.compactDescription)", to: 160)
            default:
                continue
            }
        }
        return ""
    }

    private static func truncate(_ s: String, to limit: Int) -> String {
        s.count > limit ? String(s.prefix(limit)) + "…" : s
    }
}
