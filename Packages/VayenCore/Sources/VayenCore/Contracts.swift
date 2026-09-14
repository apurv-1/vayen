import Foundation

/// Coding-agent harness a session was produced by.
public enum Harness: String, Sendable, Codable, Hashable {
    case claudeCode = "claude-code"
    case codex
    case cursor

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }
}

/// Stable identity of one coding-agent session. Display titles are never identity.
public struct SessionIdentity: Hashable, Sendable, Codable {
    public var harness: Harness
    /// Session id assigned by the harness (e.g. the JSONL filename UUID for Claude Code).
    public var nativeSessionID: String
    /// The configured source root this session was discovered under.
    public var sourceRoot: String
    /// Harness-specific locator component (Claude: the encoded project directory name).
    public var projectKey: String

    public init(harness: Harness, nativeSessionID: String, sourceRoot: String, projectKey: String) {
        self.harness = harness
        self.nativeSessionID = nativeSessionID
        self.sourceRoot = sourceRoot
        self.projectKey = projectKey
    }
}

/// Provenance pointer into a local transcript source.
/// Does not contain an absolute path so it is safe to include in outbound evidence.
public struct SourceReference: Hashable, Sendable, Codable {
    /// Stable file identity within the session (e.g. "main" or "subagent:agent-abc").
    public var fileKey: String
    /// File generation; increments when the source is replaced or truncated and reparsed.
    public var generation: Int
    /// 0-based index of the complete record within the file generation.
    public var recordIndex: Int
    /// Index of the content block inside the record when one record yields
    /// several events (assistant text plus tool calls); nil for whole-record events.
    public var blockIndex: Int?
    /// Native event id (Claude `uuid`) when the record carries one.
    public var eventID: String?

    public init(fileKey: String, generation: Int, recordIndex: Int, blockIndex: Int? = nil, eventID: String? = nil) {
        self.fileKey = fileKey
        self.generation = generation
        self.recordIndex = recordIndex
        self.blockIndex = blockIndex
        self.eventID = eventID
    }
}

public enum EventActor: String, Sendable, Codable {
    case user, assistant, tool, system, unknown
}

public enum EventKind: String, Sendable, Codable {
    /// A direct human request to the coding agent.
    case userPrompt
    /// Any other user-side record: SDK input, tool-result carrier, injected metadata.
    case userMessage
    case assistantText
    case toolUse
    case toolResult
    /// Opaque reasoning material. Normalized for completeness but never sent outbound.
    case thinking
    case attachment
    case title
    /// compact_boundary, turn_duration, stop_hook_summary, informational, etc.
    case systemMarker
    /// queue-operation, mode, last-prompt, permission-mode, cost-state, ...
    case metadata
    case unknown
}

public enum EventContent: Sendable, Codable, Equatable {
    case text(String)
    case toolUse(name: String, summary: String, toolUseID: String?)
    case toolResult(toolUseID: String?, excerpt: String, isError: Bool, truncated: Bool)
    case thinking
    case imageRef(mediaType: String?)
    case marker(name: String, detail: String?)
    case none
}

/// One normalized record from any harness transcript.
public struct NormalizedEvent: Sendable, Identifiable {
    public var id: SourceReference { source }
    public var source: SourceReference
    public var eventID: String?
    public var parentID: String?
    public var timestamp: Date?
    public var actor: EventActor
    public var kind: EventKind
    public var content: EventContent
    /// Claude `isSidechain` / subagent-origin marker.
    public var isSidechain: Bool
    /// Subagent file key when the event came from a nested subagent transcript.
    public var subagentFileKey: String?
    /// Session id recorded on the record itself; used to detect identity conflicts.
    public var recordSessionID: String?
    /// Working directory recorded on the record, when present.
    public var cwd: String?
    /// True when the record carries a compacted/summary marker rather than primary history.
    public var isCompactSummary: Bool

    public init(
        source: SourceReference,
        eventID: String? = nil,
        parentID: String? = nil,
        timestamp: Date? = nil,
        actor: EventActor,
        kind: EventKind,
        content: EventContent = .none,
        isSidechain: Bool = false,
        subagentFileKey: String? = nil,
        recordSessionID: String? = nil,
        cwd: String? = nil,
        isCompactSummary: Bool = false
    ) {
        self.source = source
        self.eventID = eventID
        self.parentID = parentID
        self.timestamp = timestamp
        self.actor = actor
        self.kind = kind
        self.content = content
        self.isSidechain = isSidechain
        self.subagentFileKey = subagentFileKey
        self.recordSessionID = recordSessionID
        self.cwd = cwd
        self.isCompactSummary = isCompactSummary
    }
}

/// What the adapter can honestly say about recent activity.
/// Silence never maps to finished.
public struct ActivityEvidence: Sendable, Codable, Equatable {
    public enum Kind: String, Sendable, Codable {
        /// A new conversational or tool record was parsed.
        case semanticEvent
        /// File changed without a parseable semantic event.
        case sourceChanged
        case none
    }
    public var lastEventAt: Date?
    public var observedAt: Date
    public var kind: Kind
    /// A recorded assistant turn end was seen. Not task completion.
    public var sawTurnEnd: Bool

    public init(lastEventAt: Date?, observedAt: Date, kind: Kind, sawTurnEnd: Bool) {
        self.lastEventAt = lastEventAt
        self.observedAt = observedAt
        self.kind = kind
        self.sawTurnEnd = sawTurnEnd
    }
}

public struct ParserHealth: Sendable, Codable, Equatable {
    public var validRecords: Int = 0
    public var invalidRecords: Int = 0
    public var unsupportedKinds: [String: Int] = [:]
    public var notes: [String] = []

    public init() {}
    public init(validRecords: Int, invalidRecords: Int, unsupportedKinds: [String: Int], notes: [String]) {
        self.validRecords = validRecords
        self.invalidRecords = invalidRecords
        self.unsupportedKinds = unsupportedKinds
        self.notes = notes
    }
}

public enum TitleSource: String, Sendable, Codable {
    /// User-assigned `custom-title`.
    case userTitle
    /// Harness-generated title; a display hint, not task evidence.
    case generatedTitle
    /// Derived from the first real user prompt.
    case firstPrompt
    case fallback
}

/// Catalog row for one discovered session.
public struct SessionSummary: Sendable, Identifiable {
    public var id: SessionIdentity { identity }
    public var identity: SessionIdentity
    public var projectPath: String?
    public var title: String
    public var titleSource: TitleSource
    public var firstObservedAt: Date?
    public var lastEventAt: Date?
    public var fileModifiedAt: Date?
    public var activity: ActivityEvidence
    public var parserHealth: ParserHealth
    public var subagentFileCount: Int
    public var eventCount: Int
    /// True when a transcript file currently exists and was readable.
    public var readable: Bool

    public init(
        identity: SessionIdentity,
        projectPath: String?,
        title: String,
        titleSource: TitleSource,
        firstObservedAt: Date?,
        lastEventAt: Date?,
        fileModifiedAt: Date?,
        activity: ActivityEvidence,
        parserHealth: ParserHealth,
        subagentFileCount: Int,
        eventCount: Int,
        readable: Bool
    ) {
        self.identity = identity
        self.projectPath = projectPath
        self.title = title
        self.titleSource = titleSource
        self.firstObservedAt = firstObservedAt
        self.lastEventAt = lastEventAt
        self.fileModifiedAt = fileModifiedAt
        self.activity = activity
        self.parserHealth = parserHealth
        self.subagentFileCount = subagentFileCount
        self.eventCount = eventCount
        self.readable = readable
    }
}

/// Resume position for incremental transcript reads.
public struct TailCursor: Sendable, Codable, Equatable {
    public var fileKey: String
    public var generation: Int
    public var byteOffset: UInt64
    /// Complete records consumed so far in this generation.
    public var recordIndex: Int
    /// Incomplete trailing bytes retained until a terminating newline arrives.
    public var pendingBytes: Data
    /// Recently consumed event ids for duplicate suppression (bounded).
    public var recentEventIDs: [String]

    public init(
        fileKey: String,
        generation: Int = 0,
        byteOffset: UInt64 = 0,
        recordIndex: Int = 0,
        pendingBytes: Data = Data(),
        recentEventIDs: [String] = []
    ) {
        self.fileKey = fileKey
        self.generation = generation
        self.byteOffset = byteOffset
        self.recordIndex = recordIndex
        self.pendingBytes = pendingBytes
        self.recentEventIDs = recentEventIDs
    }
}

public enum EvidenceAvailability: String, Sendable, Codable {
    case present, truncated, missing
}

/// One bounded piece of evidence selected for a snapshot, with provenance.
public struct EvidenceItem: Sendable, Identifiable {
    public var id: SourceReference { source }
    public var source: SourceReference
    public var timestamp: Date?
    public var actor: EventActor
    public var kind: EventKind
    /// Redacted, budget-trimmed text ready for the model.
    public var text: String
    public var truncated: Bool

    public init(source: SourceReference, timestamp: Date?, actor: EventActor, kind: EventKind, text: String, truncated: Bool) {
        self.source = source
        self.timestamp = timestamp
        self.actor = actor
        self.kind = kind
        self.text = text
        self.truncated = truncated
    }
}

public struct OriginalTaskEvidence: Sendable {
    public var text: String
    public var source: SourceReference
    public var timestamp: Date?
    public var truncated: Bool

    public init(text: String, source: SourceReference, timestamp: Date?, truncated: Bool) {
        self.text = text
        self.source = source
        self.timestamp = timestamp
        self.truncated = truncated
    }
}

/// Immutable evidence bound to one conversational turn.
public struct EvidenceSnapshot: Sendable {
    public var identity: SessionIdentity
    /// Per-session monotonically increasing snapshot version.
    public var version: Int
    public var createdAt: Date
    /// Latest source timestamp covered by this snapshot.
    public var sourceCutoff: Date?
    public var originalTask: OriginalTaskEvidence?
    public var items: [EvidenceItem]
    /// Count of records intentionally omitted from this snapshot.
    public var omittedEventCount: Int
    public var estimatedTokens: Int
    /// Human-readable coverage caveats, e.g. "history before compaction is unavailable".
    public var limitations: [String]

    public init(
        identity: SessionIdentity,
        version: Int,
        createdAt: Date,
        sourceCutoff: Date?,
        originalTask: OriginalTaskEvidence?,
        items: [EvidenceItem],
        omittedEventCount: Int,
        estimatedTokens: Int,
        limitations: [String]
    ) {
        self.identity = identity
        self.version = version
        self.createdAt = createdAt
        self.sourceCutoff = sourceCutoff
        self.originalTask = originalTask
        self.items = items
        self.omittedEventCount = omittedEventCount
        self.estimatedTokens = estimatedTokens
        self.limitations = limitations
    }
}

public enum TurnState: String, Sendable {
    case pending, answering, answered, cancelled, failed
}

/// One question/answer turn inside a voice conversation.
public struct ObserverTurn: Identifiable, Sendable {
    public var id: UUID
    public var conversationID: UUID
    public var session: SessionIdentity
    public var question: String
    public var snapshotVersion: Int
    public var response: String
    public var state: TurnState

    public init(
        id: UUID = UUID(),
        conversationID: UUID,
        session: SessionIdentity,
        question: String,
        snapshotVersion: Int,
        response: String = "",
        state: TurnState = .pending
    ) {
        self.id = id
        self.conversationID = conversationID
        self.session = session
        self.question = question
        self.snapshotVersion = snapshotVersion
        self.response = response
        self.state = state
    }
}
