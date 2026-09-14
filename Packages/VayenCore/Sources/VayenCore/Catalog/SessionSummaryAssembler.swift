import Foundation

/// Assembles a SessionSummary from normalized events. Shared by adapters
/// (digest + full load) and the catalog so list rows and loaded sessions
/// derive identical titles, activity, and project paths.
public enum SessionSummaryAssembler {

    public static func assemble(
        identity: SessionIdentity,
        events: [NormalizedEvent],
        health: ParserHealth,
        fileModifiedAt: Date?,
        subagentFileCount: Int,
        lastTurnEndAt: Date?,
        readable: Bool
    ) -> SessionSummary {
        var cwdCounts: [String: Int] = [:]
        var customTitle: String?
        var generatedTitle: String?
        var firstPrompt: String?

        for event in events {
            if let cwd = event.cwd, !cwd.isEmpty {
                cwdCounts[cwd, default: 0] += 1
            }
            if event.kind == .title, case .marker(let name, let detail) = event.content {
                if name == "custom-title", let detail, !detail.isEmpty {
                    customTitle = detail
                } else if name == "ai-title", let detail, !detail.isEmpty, generatedTitle == nil {
                    generatedTitle = detail
                }
            }
            if firstPrompt == nil, event.kind == .userPrompt, case .text(let text) = event.content {
                firstPrompt = text
            }
        }

        let (title, titleSource): (String, TitleSource) = {
            if let customTitle { return (customTitle, .userTitle) }
            if let generatedTitle { return (generatedTitle, .generatedTitle) }
            if let firstPrompt { return (sanitizeTitle(firstPrompt), .firstPrompt) }
            return ("Session " + identity.nativeSessionID.prefix(8), .fallback)
        }()

        let timestamps = events.compactMap(\.timestamp)
        let lastEventAt = timestamps.max()
        let activity = ActivityEvidence(
            lastEventAt: lastEventAt,
            observedAt: Date(),
            kind: lastEventAt != nil ? .semanticEvent : (fileModifiedAt != nil ? .sourceChanged : .none),
            sawTurnEnd: lastTurnEndAt != nil
        )

        return SessionSummary(
            identity: identity,
            projectPath: cwdCounts.max(by: { $0.value < $1.value })?.key,
            title: title,
            titleSource: titleSource,
            firstObservedAt: timestamps.min(),
            lastEventAt: lastEventAt,
            fileModifiedAt: fileModifiedAt,
            activity: activity,
            parserHealth: health,
            subagentFileCount: subagentFileCount,
            eventCount: events.count,
            readable: readable
        )
    }

    /// Timestamp-ordered event sort with deterministic fallbacks.
    public static func sortEvents(_ events: inout [NormalizedEvent]) {
        events.sort { lhs, rhs in
            switch (lhs.timestamp, rhs.timestamp) {
            case let (l?, r?): return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil):
                if lhs.source.fileKey == rhs.source.fileKey {
                    return lhs.source.recordIndex < rhs.source.recordIndex
                }
                return lhs.source.fileKey < rhs.source.fileKey
            }
        }
    }

    public static func sanitizeTitle(_ raw: String) -> String {
        let squashed = raw.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        if squashed.isEmpty { return "Untitled session" }
        return squashed.count > 80 ? String(squashed.prefix(80)) + "…" : squashed
    }
}
