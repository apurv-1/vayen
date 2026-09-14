import Foundation

/// Read-only adapter for Claude Code's local session persistence.
///
/// Layout observed on macOS (see planning/research-sessions.md):
/// - Main sessions: `<root>/<encoded-project>/<session-uuid>.jsonl`
/// - Subagent transcripts: `<project>/<session-uuid>/subagents/agent-*.jsonl`
/// - Tool-result sidecars: `<project>/<session-uuid>/tool-results/` (not read by default)
/// - `<project>/memory/` directories are not sessions.
///
/// The adapter never writes to, truncates, or deletes any source file.
public struct ClaudeAdapter: HarnessAdapter {
    public let harness: Harness = .claudeCode

    /// Claude's default persistence root. `CLAUDE_CONFIG_DIR` relocates it; the
    /// app exposes the root as a setting for that case.
    public static var defaultSourceRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
    }

    public static let mainFileKey = "main"

    public init() {}

    // MARK: - Discovery

    public func discover(under sourceRoot: URL) async -> AdapterDiscoveryResult {
        var diagnostics: [String] = []
        let fm = FileManager.default

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceRoot.path, isDirectory: &isDir), isDir.boolValue else {
            return AdapterDiscoveryResult(
                sessions: [],
                diagnostics: ["Claude projects root not found at \(sourceRoot.path)"],
                rootExists: false,
                rootAccessible: false
            )
        }

        guard let projectDirs = try? fm.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return AdapterDiscoveryResult(
                sessions: [],
                diagnostics: ["Claude projects root is not readable: \(sourceRoot.path)"],
                rootExists: true,
                rootAccessible: false
            )
        }

        var sessions: [DiscoveredSessionFile] = []
        for projectDir in projectDirs where projectDir.hasDirectoryPath {
            let projectKey = projectDir.lastPathComponent
            guard let entries = try? fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                diagnostics.append("Unreadable project directory: \(projectKey)")
                continue
            }
            for entry in entries {
                guard !entry.hasDirectoryPath,
                      entry.pathExtension == "jsonl",
                      isSessionFileName(entry.deletingPathExtension().lastPathComponent)
                else { continue }

                let sessionID = entry.deletingPathExtension().lastPathComponent
                let values = try? entry.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let subagents = discoverSubagents(sessionID: sessionID, projectDir: projectDir)
                sessions.append(DiscoveredSessionFile(
                    identity: SessionIdentity(
                        harness: harness,
                        nativeSessionID: sessionID,
                        sourceRoot: sourceRoot.path,
                        projectKey: projectKey
                    ),
                    mainFileURL: entry,
                    subagentFileURLs: subagents,
                    fileModifiedAt: values?.contentModificationDate,
                    fileSize: UInt64(values?.fileSize ?? 0)
                ))
            }
        }
        return AdapterDiscoveryResult(
            sessions: sessions,
            diagnostics: diagnostics,
            rootExists: true,
            rootAccessible: true
        )
    }

    /// Claude session files are named by UUID. Anything else directly under a
    /// project directory (scratch files, notes) is not a session transcript.
    private func isSessionFileName(_ stem: String) -> Bool {
        UUID(uuidString: stem) != nil
    }

    private func discoverSubagents(sessionID: String, projectDir: URL) -> [String: URL] {
        let subagentDir = projectDir
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("subagents", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: subagentDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [:] }
        var result: [String: URL] = [:]
        for file in files where !file.hasDirectoryPath && file.pathExtension == "jsonl" {
            let key = "subagent:" + file.deletingPathExtension().lastPathComponent
            result[key] = file
        }
        return result
    }

    // MARK: - Normalization

    public func normalize(line: Data, fileKey: String, generation: Int, recordIndex: Int) -> NormalizationOutput {
        var output = NormalizationOutput()
        guard let record = ClaudeRecordDecode.parse(line: line) else {
            output.lineValid = false
            return output
        }
        output.recordType = record.type
        let result = ClaudeNormalizer.normalize(
            record: record, fileKey: fileKey, generation: generation, recordIndex: recordIndex
        )
        output.events = result.events.map { event in
            var event = event
            if fileKey != Self.mainFileKey && event.subagentFileKey == nil {
                event.subagentFileKey = fileKey
            }
            return event
        }
        output.turnEndAt = result.turnEndAt
        return output
    }

    // MARK: - Loading

    /// Fully parse a discovered session: main file plus subagent transcripts,
    /// merged into one timestamp-ordered event list. The returned cursors sit
    /// at end of file so subsequent tailer reads yield only new records.
    public func loadSession(_ discovered: DiscoveredSessionFile, tailer: TranscriptTailer) async -> SessionLoad {
        var health = ParserHealth()
        var events: [NormalizedEvent] = []
        var cursors: [String: TailCursor] = [:]
        var lastTurnEndAt: Date?

        var files: [(key: String, url: URL)] = [(Self.mainFileKey, discovered.mainFileURL)]
        files += discovered.subagentFileURLs.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }

        for (fileKey, url) in files {
            let read = await tailer.read(url: url, cursor: TailCursor(fileKey: fileKey))
            cursors[fileKey] = read.cursor
            for (recordIndex, line) in read.lines {
                let output = normalize(line: line, fileKey: fileKey, generation: read.generation, recordIndex: recordIndex)
                if !output.lineValid {
                    health.invalidRecords += 1
                    continue
                }
                health.validRecords += 1
                if output.events.isEmpty {
                    health.unsupportedKinds[output.recordType, default: 0] += 1
                }
                if fileKey == Self.mainFileKey, let turnEnd = output.turnEndAt {
                    lastTurnEndAt = max(lastTurnEndAt ?? .distantPast, turnEnd)
                }
                events.append(contentsOf: output.events)
            }
        }

        SessionSummaryAssembler.sortEvents(&events)

        let summary = SessionSummaryAssembler.assemble(
            identity: discovered.identity,
            events: events,
            health: health,
            fileModifiedAt: discovered.fileModifiedAt,
            subagentFileCount: discovered.subagentFileURLs.count,
            lastTurnEndAt: lastTurnEndAt,
            readable: true
        )

        let timestamps = events.compactMap(\.timestamp)
        return SessionLoad(
            session: LoadedSession(
                identity: discovered.identity,
                mainFileKey: Self.mainFileKey,
                events: events,
                parserHealth: health,
                projectPath: summary.projectPath,
                customTitle: summary.titleSource == .userTitle ? summary.title : nil,
                generatedTitle: summary.titleSource == .generatedTitle ? summary.title : nil,
                lastEventAt: timestamps.max(),
                firstEventAt: timestamps.min(),
                lastTurnEndAt: lastTurnEndAt
            ),
            cursors: cursors
        )
    }

    // MARK: - Digest

    /// Cheap summary for the session list: reads a bounded head slice (first
    /// prompt, working directory, early titles) and tail slice (latest
    /// timestamp, late-arriving titles) rather than the whole transcript.
    public func digest(_ discovered: DiscoveredSessionFile) async -> SessionSummary {
        let head = PartialFileReader.headLines(url: discovered.mainFileURL, limit: Self.digestHeadBytes)
        let tail = PartialFileReader.tailLines(url: discovered.mainFileURL, limit: Self.digestTailBytes)

        var health = ParserHealth()
        var events: [NormalizedEvent] = []
        var lastTurnEndAt: Date?
        for (index, line) in (head ?? []).enumerated() {
            let output = normalize(line: line, fileKey: Self.mainFileKey, generation: 0, recordIndex: index)
            accumulate(&events, output: output, health: &health, turnEnd: &lastTurnEndAt)
        }
        for (index, line) in (tail ?? []).enumerated() {
            let output = normalize(line: line, fileKey: Self.mainFileKey, generation: 0, recordIndex: -1 - index)
            accumulate(&events, output: output, health: &health, turnEnd: &lastTurnEndAt)
        }

        return SessionSummaryAssembler.assemble(
            identity: discovered.identity,
            events: events,
            health: health,
            fileModifiedAt: discovered.fileModifiedAt,
            subagentFileCount: discovered.subagentFileURLs.count,
            lastTurnEndAt: lastTurnEndAt,
            readable: head != nil
        )
    }

    static let digestHeadBytes = 128 * 1024
    static let digestTailBytes = 256 * 1024

    private func accumulate(
        _ events: inout [NormalizedEvent],
        output: NormalizationOutput,
        health: inout ParserHealth,
        turnEnd: inout Date?
    ) {
        if !output.lineValid {
            health.invalidRecords += 1
            return
        }
        health.validRecords += 1
        if output.events.isEmpty {
            health.unsupportedKinds[output.recordType, default: 0] += 1
        }
        if let t = output.turnEndAt { turnEnd = max(turnEnd ?? .distantPast, t) }
        events.append(contentsOf: output.events)
    }
}
