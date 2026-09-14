import Foundation

public struct EvidenceBudget: Sendable {
    /// Rough cap on total evidence characters (~4 chars/token estimate).
    public var maxCharacters: Int
    /// Maximum per-item characters before truncation.
    public var maxItemCharacters: Int
    /// Minimum items always taken from the recency tail regardless of question.
    public var recentFloor: Int

    public init(maxCharacters: Int = 80_000, maxItemCharacters: Int = 1_600, recentFloor: Int = 30) {
        self.maxCharacters = maxCharacters
        self.maxItemCharacters = maxItemCharacters
        self.recentFloor = recentFloor
    }

    public static let standard = EvidenceBudget()
}

/// Builds immutable evidence snapshots for the selected session.
///
/// Rules (see planning/architecture.md):
/// - Only evidence kinds are eligible: user prompts/messages, assistant text,
///   tool calls and their results. Thinking blocks, titles, attachments and
///   metadata never leave the machine.
/// - The original task is always preserved when present.
/// - When the question is supplied, high-relevance older records are pulled in
///   alongside the recency tail.
/// - Everything emitted is redacted and carries a source reference.
public struct EvidenceBuilder: Sendable {

    public init() {}

    /// Kinds eligible for outbound evidence.
    static let eligibleKinds: Set<EventKind> = [.userPrompt, .userMessage, .assistantText, .toolUse, .toolResult, .systemMarker]

    public func snapshot(
        session: LoadedSession,
        version: Int,
        question: String? = nil,
        budget: EvidenceBudget = .standard,
        now: Date = Date()
    ) -> EvidenceSnapshot {
        var limitations: [String] = []
        var items: [EvidenceItem] = []
        var characters = 0

        // 1. Original task: the earliest real user prompt on the main file.
        var originalTask: OriginalTaskEvidence?
        if let task = session.events.first(where: {
            $0.kind == .userPrompt && $0.subagentFileKey == nil
        }), case .text(let raw) = task.content {
            let (text, truncated) = Self.clip(Redactor.redact(raw), to: min(2_000, budget.maxItemCharacters))
            originalTask = OriginalTaskEvidence(
                text: text, source: task.source, timestamp: task.timestamp, truncated: truncated
            )
            characters += text.count
        } else {
            limitations.append("No original user request is present in the transcript; the session may have been compacted, imported, or started before history was kept.")
        }

        // 2. Eligible conversational/tool events, main file first-class and
        //    subagent events marked as such.
        let eligible = session.events.filter { Self.eligibleKinds.contains($0.kind) }

        // Candidate pool: recency tail plus question-relevant older records.
        let recencyTail = Array(eligible.suffix(budget.recentFloor * 2))
        var pool = recencyTail
        if let question, !question.isEmpty {
            let scored = Self.score(eligible: eligible, question: question)
            for event in scored.prefix(budget.recentFloor) {
                if !pool.contains(where: { $0.source == event.source }) {
                    pool.append(event)
                }
            }
        }

        // Preserve chronological order in the emitted snapshot.
        pool.sort { lhs, rhs in
            switch (lhs.timestamp, rhs.timestamp) {
            case let (l?, r?): return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            case (nil, nil): return lhs.source.recordIndex < rhs.source.recordIndex
            }
        }

        var includedSources = Set<SourceReference>()
        for event in pool {
            guard let text = Self.render(event) else { continue }
            let clipped = Self.clip(text, to: budget.maxItemCharacters)
            let cost = clipped.0.count
            if characters + cost > budget.maxCharacters { continue }
            if includedSources.contains(event.source) { continue }
            includedSources.insert(event.source)
            characters += cost
            items.append(EvidenceItem(
                source: event.source,
                timestamp: event.timestamp,
                actor: event.actor,
                kind: event.kind,
                text: clipped.0,
                truncated: clipped.1
            ))
        }

        let omitted = max(0, eligible.count - items.count)
        if omitted > 0 {
            limitations.append("\(omitted) transcript records are not in this snapshot due to the context budget; ask a more specific question or wait for a newer snapshot.")
        }
        if session.events.contains(where: { $0.kind == .thinking }) {
            limitations.append("Assistant reasoning blocks are present in the transcript but never leave this device.")
        }
        if let path = session.projectPath {
            _ = path // project path stays local by design
        }

        return EvidenceSnapshot(
            identity: session.identity,
            version: version,
            createdAt: now,
            sourceCutoff: session.lastEventAt,
            originalTask: originalTask,
            items: items,
            omittedEventCount: omitted,
            estimatedTokens: characters / 4,
            limitations: limitations
        )
    }

    /// Render an event into bounded, redacted, provenance-safe text.
    /// Returns nil for events with nothing worth sending.
    public static func render(_ event: NormalizedEvent) -> String? {
        let raw: String
        switch event.content {
        case .text(let t): raw = t
        case .toolUse(let name, let summary, let id):
            var s = "Tool call: \(name)"
            if !summary.isEmpty { s += " — \(summary)" }
            if let id { s += " [\(id)]" }
            raw = s
        case .toolResult(let id, let excerpt, let isError, let truncated):
            var s = isError ? "Tool result (error)" : "Tool result"
            if let id { s += " [\(id)]" }
            if !excerpt.isEmpty { s += ": \(excerpt)" }
            if truncated { s += " (excerpt)" }
            raw = s
        case .marker(let name, let detail):
            raw = detail.map { "\(name): \($0)" } ?? name
        case .thinking, .imageRef, .none:
            return nil
        }
        let redacted = Redactor.redact(raw)
        return redacted.isEmpty ? nil : redacted
    }

    static func clip(_ text: String, to limit: Int) -> (String, Bool) {
        text.count > limit ? (String(text.prefix(limit)) + "…", true) : (text, false)
    }

    // MARK: - Query-directed selection

    private static let stopwords: Set<String> = [
        "the", "a", "an", "is", "it", "to", "in", "on", "of", "for", "and",
        "or", "what", "why", "how", "did", "does", "do", "was", "were", "are",
        "this", "that", "you", "your", "its", "his", "her", "their", "with",
        "about", "when", "which", "who", "whom", "be", "been", "has", "have",
        "had", "not", "but", "if", "at", "by", "from", "as", "so", "such",
        "agent", "claude", "session", "working", "work",
    ]

    /// Score eligible events by distinct question-term overlap.
    /// Returns events sorted by descending score; zero-score events are dropped.
    static func score(eligible: [NormalizedEvent], question: String) -> [NormalizedEvent] {
        let terms = Set(
            question.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { $0.count >= 3 && !stopwords.contains($0) }
        )
        guard !terms.isEmpty else { return [] }
        return eligible
            .map { event -> (NormalizedEvent, Int) in
                guard let text = render(event)?.lowercased() else { return (event, 0) }
                var hits = 0
                for term in terms where text.contains(term) { hits += 1 }
                return (event, hits)
            }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}
