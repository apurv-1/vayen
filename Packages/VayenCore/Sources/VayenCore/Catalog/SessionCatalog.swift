import Foundation

public enum CatalogError: Error, Sendable {
    case unknownSession(SessionIdentity)
    case sessionFileMissing(SessionIdentity)
    case adapterUnavailable(Harness)
}

public enum RefreshOutcome: Sendable {
    case ok(sessions: [SessionSummary], diagnostics: [String])
    /// The configured root does not exist or is not readable.
    case unavailable(reason: String)
}

/// What a poll learned about a session since the last read.
public struct SessionDelta: Sendable {
    public var identity: SessionIdentity
    public var newEvents: [NormalizedEvent]
    public var activity: ActivityEvidence
    /// True when any source file was replaced/truncated and reparsed.
    public var reparsed: Bool
    /// Latest recorded assistant turn end, if the delta carried one.
    public var lastTurnEndAt: Date?

    public init(identity: SessionIdentity, newEvents: [NormalizedEvent], activity: ActivityEvidence, reparsed: Bool, lastTurnEndAt: Date?) {
        self.identity = identity
        self.newEvents = newEvents
        self.activity = activity
        self.reparsed = reparsed
        self.lastTurnEndAt = lastTurnEndAt
    }
}

/// In-memory session catalog: discovery results, list summaries, and fully
/// loaded transcripts for selected sessions. The single owner of tail cursors
/// and evidence-snapshot versions.
public actor SessionCatalog {

    public static let mainFileKey = "main"

    private let adapters: [Harness: any HarnessAdapter]
    private let tailer = TranscriptTailer()

    /// Configured source roots per harness.
    private var sourceRoots: [Harness: URL]

    private var discovered: [SessionIdentity: DiscoveredSessionFile] = [:]
    private var summaries: [SessionIdentity: SessionSummary] = [:]
    private var loadedSessions: [SessionIdentity: LoadedSession] = [:]
    private var cursors: [SessionIdentity: [String: TailCursor]] = [:]
    private var snapshotVersions: [SessionIdentity: Int] = [:]
    private var lastDiagnostics: [String] = []
    private var discoveryState: DiscoveryState = .notRun

    public enum DiscoveryState: Sendable {
        case notRun, available, rootMissing, rootUnreadable
    }

    public init(
        adapters: [any HarnessAdapter] = [ClaudeAdapter()],
        sourceRoots: [Harness: URL]? = nil
    ) {
        var map: [Harness: any HarnessAdapter] = [:]
        for adapter in adapters { map[adapter.harness] = adapter }
        self.adapters = map
        self.sourceRoots = sourceRoots ?? [.claudeCode: ClaudeAdapter.defaultSourceRoot]
    }

    public func setSourceRoot(_ url: URL, for harness: Harness) {
        sourceRoots[harness] = url
    }

    public func sourceRoot(for harness: Harness) -> URL? {
        sourceRoots[harness]
    }

    public var discoveryStateValue: DiscoveryState { discoveryState }
    public var diagnostics: [String] { lastDiagnostics }

    // MARK: - Discovery + list refresh

    /// Re-enumerate configured roots and produce list summaries.
    /// Cheap per session: bounded head/tail reads, no full transcript parse.
    @discardableResult
    public func refresh() async -> RefreshOutcome {
        var all: [SessionSummary] = []
        var diagnostics: [String] = []
        var anyAvailable = false
        var sawMissing = false
        var sawUnreadable = false

        for (harness, root) in sourceRoots {
            guard let adapter = adapters[harness] else { continue }
            let result = await adapter.discover(under: root)
            diagnostics.append(contentsOf: result.diagnostics)
            if !result.rootExists { sawMissing = true; continue }
            if !result.rootAccessible { sawUnreadable = true; continue }
            anyAvailable = true
            for file in result.sessions {
                discovered[file.identity] = file
                let summary = await adapter.digest(file)
                summaries[file.identity] = summary
                all.append(summary)
            }
        }

        // Forget sessions whose files disappeared.
        let seen = Set(all.map(\.identity))
        for key in discovered.keys where !seen.contains(key) {
            discovered.removeValue(forKey: key)
            loadedSessions.removeValue(forKey: key)
            cursors.removeValue(forKey: key)
            snapshotVersions.removeValue(forKey: key)
        }
        for key in summaries.keys where !seen.contains(key) {
            summaries.removeValue(forKey: key)
        }

        lastDiagnostics = diagnostics
        if !anyAvailable {
            discoveryState = sawMissing ? .rootMissing : (sawUnreadable ? .rootUnreadable : .notRun)
            let reason = sawMissing
                ? "No Claude session directory found. Start a Claude Code session or check the configured source root."
                : "The Claude session directory exists but is not readable."
            return .unavailable(reason: reason)
        }
        discoveryState = .available

        all.sort { ($0.activity.lastEventAt ?? $0.fileModifiedAt ?? .distantPast) > ($1.activity.lastEventAt ?? $1.fileModifiedAt ?? .distantPast) }
        return .ok(sessions: all, diagnostics: diagnostics)
    }

    public func summariesSnapshot() -> [SessionSummary] {
        summaries.values.sorted {
            ($0.activity.lastEventAt ?? $0.fileModifiedAt ?? .distantPast)
                > ($1.activity.lastEventAt ?? $1.fileModifiedAt ?? .distantPast)
        }
    }

    // MARK: - Full session loading

    /// Load (or return cached) the complete normalized transcript for a session.
    public func session(_ identity: SessionIdentity) throws -> LoadedSession {
        if let loaded = loadedSessions[identity] { return loaded }
        throw CatalogError.unknownSession(identity)
    }

    /// Fully load a session's transcript. Called when the user selects it.
    @discardableResult
    public func load(_ identity: SessionIdentity) async throws -> LoadedSession {
        guard let discovered = discovered[identity] else {
            throw CatalogError.unknownSession(identity)
        }
        guard let adapter = adapters[identity.harness] else {
            throw CatalogError.adapterUnavailable(identity.harness)
        }
        let load = await adapter.loadSession(discovered, tailer: tailer)
        loadedSessions[identity] = load.session
        cursors[identity] = load.cursors
        summaries[identity] = summaryWithFullLoad(load.session, discovered: discovered)
        return load.session
    }

    /// Merge newly appended records into a loaded session.
    /// Only meaningful after `load(_:)`.
    @discardableResult
    public func poll(_ identity: SessionIdentity) async throws -> SessionDelta {
        guard let existing = discovered[identity],
              var loaded = loadedSessions[identity],
              var fileCursors = cursors[identity] else {
            throw CatalogError.unknownSession(identity)
        }
        guard let adapter = adapters[identity.harness] else {
            throw CatalogError.adapterUnavailable(identity.harness)
        }

        // A session may gain subagent files after discovery; refresh the file list.
        let rediscovery = await adapter.discover(under: URL(fileURLWithPath: identity.sourceRoot))
        if let fresh = rediscovery.sessions.first(where: { $0.identity == identity }) {
            discovered[identity] = fresh
        }
        let current = discovered[identity] ?? existing

        var files: [(key: String, url: URL)] = [(SessionCatalog.mainFileKey, current.mainFileURL)]
        files += current.subagentFileURLs.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }

        var newEvents: [NormalizedEvent] = []
        var lastTurnEndAt = loaded.lastTurnEndAt
        var sawAnyAppend = false

        for (fileKey, url) in files {
            let cursor = fileCursors[fileKey] ?? TailCursor(fileKey: fileKey)
            let read = await tailer.read(url: url, cursor: cursor)
            fileCursors[fileKey] = read.cursor
            if read.status == .reparsed {
                // Events from the old generation are stale; simplest correct
                // behavior for the beta is a full reload on reparse.
                let reload = try await self.load(identity)
                return SessionDelta(
                    identity: identity,
                    newEvents: reload.events,
                    activity: summaries[identity]?.activity ?? loaded.activityPlaceholder,
                    reparsed: true,
                    lastTurnEndAt: reload.lastTurnEndAt
                )
            }
            if read.status == .missing || read.lines.isEmpty { continue }
            sawAnyAppend = true
            var dedup = Set(read.cursor.recentEventIDs)
            for (recordIndex, line) in read.lines {
                let output = adapter.normalize(line: line, fileKey: fileKey, generation: read.generation, recordIndex: recordIndex)
                if !output.lineValid {
                    loaded.parserHealth.invalidRecords += 1
                    continue
                }
                loaded.parserHealth.validRecords += 1
                for event in output.events {
                    if let id = event.eventID {
                        if dedup.contains(id) { continue }
                        dedup.insert(id)
                    }
                    newEvents.append(event)
                }
                if fileKey == SessionCatalog.mainFileKey, let t = output.turnEndAt {
                    lastTurnEndAt = max(lastTurnEndAt ?? .distantPast, t)
                }
            }
            // Keep the dedup set bounded inside the cursor.
            var updated = fileCursors[fileKey] ?? read.cursor
            updated.recentEventIDs = Array(dedup).suffix(512).map { $0 }
            fileCursors[fileKey] = updated
        }

        loaded.events.append(contentsOf: newEvents)
        SessionSummaryAssembler.sortEvents(&loaded.events)
        let timestamps = loaded.events.compactMap(\.timestamp)
        loaded.lastEventAt = timestamps.max()
        loaded.firstEventAt = timestamps.min()
        loaded.lastTurnEndAt = lastTurnEndAt

        loadedSessions[identity] = loaded
        cursors[identity] = fileCursors

        let activity = ActivityEvidence(
            lastEventAt: loaded.lastEventAt,
            observedAt: Date(),
            kind: sawAnyAppend || !newEvents.isEmpty ? .semanticEvent : .none,
            sawTurnEnd: lastTurnEndAt != nil
        )
        if var summary = summaries[identity] {
            summary.activity = activity
            summary.lastEventAt = loaded.lastEventAt
            summary.eventCount = loaded.events.count
            summary.fileModifiedAt = (try? current.mainFileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            summaries[identity] = summary
        }

        return SessionDelta(
            identity: identity,
            newEvents: newEvents,
            activity: activity,
            reparsed: false,
            lastTurnEndAt: lastTurnEndAt
        )
    }

    private func summaryWithFullLoad(_ session: LoadedSession, discovered: DiscoveredSessionFile) -> SessionSummary {
        SessionSummaryAssembler.assemble(
            identity: session.identity,
            events: session.events,
            health: session.parserHealth,
            fileModifiedAt: discovered.fileModifiedAt,
            subagentFileCount: discovered.subagentFileURLs.count,
            lastTurnEndAt: session.lastTurnEndAt,
            readable: true
        )
    }

    // MARK: - Evidence snapshot versions

    /// Next monotonically increasing snapshot version for a session.
    public func nextSnapshotVersion(for identity: SessionIdentity) -> Int {
        let v = (snapshotVersions[identity] ?? 0) + 1
        snapshotVersions[identity] = v
        return v
    }

    public func currentSnapshotVersion(for identity: SessionIdentity) -> Int {
        snapshotVersions[identity] ?? 0
    }
}

extension LoadedSession {
    /// Fallback activity placeholder when no summary exists yet.
    var activityPlaceholder: ActivityEvidence {
        ActivityEvidence(lastEventAt: lastEventAt, observedAt: Date(), kind: lastEventAt != nil ? .semanticEvent : .none, sawTurnEnd: lastTurnEndAt != nil)
    }
}
