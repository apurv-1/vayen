import Foundation

/// A transcript file discovered under a configured source root.
public struct DiscoveredSessionFile: Sendable {
    public var identity: SessionIdentity
    /// The main transcript file (e.g. `<project>/<session>.jsonl`).
    public var mainFileURL: URL
    /// Subagent transcript files keyed by fileKey (e.g. "subagent:agent-abc").
    public var subagentFileURLs: [String: URL]
    public var fileModifiedAt: Date?
    public var fileSize: UInt64

    public init(
        identity: SessionIdentity,
        mainFileURL: URL,
        subagentFileURLs: [String: URL],
        fileModifiedAt: Date?,
        fileSize: UInt64
    ) {
        self.identity = identity
        self.mainFileURL = mainFileURL
        self.subagentFileURLs = subagentFileURLs
        self.fileModifiedAt = fileModifiedAt
        self.fileSize = fileSize
    }
}

public struct AdapterDiscoveryResult: Sendable {
    public var sessions: [DiscoveredSessionFile]
    public var diagnostics: [String]
    public var rootExists: Bool
    public var rootAccessible: Bool

    public init(sessions: [DiscoveredSessionFile], diagnostics: [String], rootExists: Bool, rootAccessible: Bool) {
        self.sessions = sessions
        self.diagnostics = diagnostics
        self.rootExists = rootExists
        self.rootAccessible = rootAccessible
    }
}

/// Output of normalizing one complete JSONL line.
public struct NormalizationOutput: Sendable {
    public var events: [NormalizedEvent] = []
    /// Line decoded to a structurally valid record.
    public var lineValid = true
    /// Raw record `type`, for parser-health accounting.
    public var recordType = "unknown"
    /// Record marked an assistant turn end (Claude `stop_reason == end_turn`)
    /// at this timestamp. Honest meaning: a recorded assistant turn ended.
    /// Never task completion.
    public var turnEndAt: Date?

    public init() {}
}

/// Boundary between harness-specific storage and the rest of the app.
/// Implementations must never mutate the sources they read.
public protocol HarnessAdapter: Sendable {
    var harness: Harness { get }

    /// Enumerate session transcript files under a configured root.
    /// Read-only: directory listing and file metadata only.
    func discover(under sourceRoot: URL) async -> AdapterDiscoveryResult

    /// Normalize one complete JSONL line into zero or more events.
    func normalize(line: Data, fileKey: String, generation: Int, recordIndex: Int) -> NormalizationOutput

    /// Fully parse a discovered session (main file plus subagent transcripts).
    /// Returns the normalized session and the tail cursors positioned at end of
    /// file so later reads only yield new records.
    func loadSession(_ discovered: DiscoveredSessionFile, tailer: TranscriptTailer) async -> SessionLoad

    /// Cheap list-row summary: reads bounded head and tail slices only.
    func digest(_ discovered: DiscoveredSessionFile) async -> SessionSummary
}

/// Result of a full session load plus resume positions for tailing.
public struct SessionLoad: Sendable {
    public var session: LoadedSession
    public var cursors: [String: TailCursor]

    public init(session: LoadedSession, cursors: [String: TailCursor]) {
        self.session = session
        self.cursors = cursors
    }
}

/// A fully parsed session transcript, ready for evidence building.
public struct LoadedSession: Sendable {
    public var identity: SessionIdentity
    public var mainFileKey: String
    /// All normalized events from the main file and subagent files,
    /// ordered by timestamp where available, else by discovery order.
    public var events: [NormalizedEvent]
    public var parserHealth: ParserHealth
    /// Most common `cwd` across message records.
    public var projectPath: String?
    public var customTitle: String?
    public var generatedTitle: String?
    /// Timestamp of the newest event with a timestamp.
    public var lastEventAt: Date?
    public var firstEventAt: Date?
    /// A recorded assistant `end_turn` was seen at this time, if any.
    public var lastTurnEndAt: Date?

    public init(
        identity: SessionIdentity,
        mainFileKey: String,
        events: [NormalizedEvent],
        parserHealth: ParserHealth,
        projectPath: String?,
        customTitle: String?,
        generatedTitle: String?,
        lastEventAt: Date?,
        firstEventAt: Date?,
        lastTurnEndAt: Date?
    ) {
        self.identity = identity
        self.mainFileKey = mainFileKey
        self.events = events
        self.parserHealth = parserHealth
        self.projectPath = projectPath
        self.customTitle = customTitle
        self.generatedTitle = generatedTitle
        self.lastEventAt = lastEventAt
        self.firstEventAt = firstEventAt
        self.lastTurnEndAt = lastTurnEndAt
    }
}
