import Foundation
import Testing
@testable import VayenCore

@Suite("Claude adapter parsing")
struct ClaudeAdapterTests {

    let adapter = ClaudeAdapter()

    private func normalized(_ line: String, index: Int = 0) -> NormalizationOutput {
        adapter.normalize(line: Data(line.utf8), fileKey: "main", generation: 0, recordIndex: index)
    }

    @Test func userPromptBecomesTask() {
        let out = normalized(Fixture.userPrompt(text: "Fix the tokenizer cache", ts: "2026-09-14T10:00:00Z"))
        #expect(out.lineValid)
        #expect(out.events.count == 1)
        let event = out.events[0]
        #expect(event.kind == .userPrompt)
        #expect(event.actor == .user)
        #expect(event.cwd == "/tmp/proj")
        if case .text(let t) = event.content { #expect(t == "Fix the tokenizer cache") } else { Issue.record() }
    }

    @Test func assistantTextAndToolUse() {
        let out = normalized(Fixture.assistant(uuid: "a1", ts: "2026-09-14T10:01:00Z", blocks: [
            Fixture.textBlock("I will read the file."),
            Fixture.toolUseBlock(id: "tu1", name: "Read", input: #"{"file_path":"/tmp/proj/a.swift"}"#),
        ], stop: "end_turn"))
        #expect(out.events.count == 2)
        #expect(out.events[0].kind == .assistantText)
        #expect(out.events[1].kind == .toolUse)
        if case .toolUse(let name, let summary, let id) = out.events[1].content {
            #expect(name == "Read")
            #expect(summary.contains("a.swift"))
            #expect(id == "tu1")
        } else { Issue.record() }
        #expect(out.turnEndAt != nil)
    }

    @Test func toolResultInUserRecord() {
        let out = normalized(Fixture.userBlocks(ts: "2026-09-14T10:02:00Z", blocks:
            Fixture.toolResultBlock(toolUseID: "tu1", text: "file contents", isError: false)))
        #expect(out.events.count == 1)
        let e = out.events[0]
        #expect(e.kind == .toolResult)
        #expect(e.actor == .tool)
        if case .toolResult(let id, let excerpt, let isError, _) = e.content {
            #expect(id == "tu1"); #expect(excerpt == "file contents"); #expect(!isError)
        } else { Issue.record() }
    }

    @Test func thinkingBlockIsNormalizedButMarked() {
        let out = normalized(Fixture.assistant(uuid: "a2", ts: "2026-09-14T10:03:00Z", blocks: [
            Fixture.thinkingBlock("secret reasoning"),
            Fixture.textBlock("visible answer"),
        ]))
        #expect(out.events.count == 2)
        #expect(out.events[0].kind == .thinking)
        #expect(out.events[1].kind == .assistantText)
    }

    @Test func slashCommandIsNotAPrompt() {
        let out = normalized(Fixture.userPrompt(text: "<command-name>/mcp</command-name><command-message>mcp</command-message>", ts: "2026-09-14T10:00:00Z"))
        #expect(out.events[0].kind == .metadata)
    }

    @Test func compactSummaryIsMarkerNotPrompt() {
        let out = normalized(Fixture.compactSummaryUser(ts: "2026-09-14T10:00:00Z", text: "Summary of earlier work…"))
        #expect(out.events[0].kind == .systemMarker)
        if case .marker(let name, _) = out.events[0].content { #expect(name == "compact_summary") } else { Issue.record() }
    }

    @Test func titles() {
        let custom = normalized(Fixture.customTitle("My fix"))
        #expect(custom.events[0].kind == .title)
        if case .marker(let name, let detail) = custom.events[0].content {
            #expect(name == "custom-title"); #expect(detail == "My fix")
        } else { Issue.record() }
        let gen = normalized(Fixture.aiTitle("Generated title"))
        if case .marker(let name, _) = gen.events[0].content { #expect(name == "ai-title") } else { Issue.record() }
    }

    @Test func unknownKindIsTolerated() {
        let out = normalized(Fixture.metadata("some-future-kind"))
        #expect(out.lineValid)
        #expect(out.events.count == 1)
        #expect(out.events[0].kind == .unknown)
    }

    @Test func invalidJSONIsInvalid() {
        let out = normalized("{not json")
        #expect(!out.lineValid)
        #expect(out.events.isEmpty)
    }

    @Test func missingFieldsAreTolerated() {
        // Bare minimum: type only.
        let out = normalized("{\"type\":\"user\"}")
        #expect(out.lineValid)
        #expect(out.events.count == 1)
        #expect(out.events[0].kind == .userMessage)
    }

    @Test func longToolResultIsExcerpted() {
        let big = String(repeating: "x", count: 10_000)
        let out = normalized(Fixture.userBlocks(ts: "2026-09-14T10:02:00Z", blocks:
            Fixture.toolResultBlock(toolUseID: "t", text: big)))
        if case .toolResult(_, let excerpt, _, let truncated) = out.events[0].content {
            #expect(truncated)
            #expect(excerpt.count <= 900)
        } else { Issue.record() }
    }
}

@Suite("Claude discovery and loading")
struct ClaudeDiscoveryTests {

    @Test func discoversOnlyUUIDNamedFiles() async throws {
        let root = try Fixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try Fixture.writeTranscript(lines: [
            Fixture.userPrompt(text: "hello", ts: "2026-09-14T10:00:00Z"),
        ], root: root)
        // Non-UUID file must be ignored.
        let projectDir = root.appendingPathComponent("-tmp-proj", isDirectory: true)
        try "junk".write(to: projectDir.appendingPathComponent("notes.jsonl"), atomically: true, encoding: .utf8)
        // A directory masquerading as transcript must be ignored.
        try FileManager.default.createDirectory(
            at: projectDir.appendingPathComponent("99999999-8888-7777-6666-555555555555.jsonl", isDirectory: true),
            withIntermediateDirectories: false
        )

        let result = await ClaudeAdapter().discover(under: root)
        #expect(result.rootExists && result.rootAccessible)
        #expect(result.sessions.count == 1)
        #expect(result.sessions[0].identity.nativeSessionID == "11111111-2222-3333-4444-555555555555")
        #expect(result.sessions[0].identity.projectKey == "-tmp-proj")
    }

    @Test func subagentsAreAssociatedNotTopLevel() async throws {
        let root = try Fixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try Fixture.writeTranscript(lines: [
            Fixture.userPrompt(text: "task", ts: "2026-09-14T10:00:00Z"),
        ], root: root)
        let sessionID = file.deletingPathExtension().lastPathComponent
        let subDir = root.appendingPathComponent("-tmp-proj")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("subagents", isDirectory: true)
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"sub work\"}}".write(
            to: subDir.appendingPathComponent("agent-abc123.jsonl"), atomically: true, encoding: .utf8
        )

        let result = await ClaudeAdapter().discover(under: root)
        #expect(result.sessions.count == 1)
        #expect(result.sessions[0].subagentFileURLs.count == 1)
        #expect(result.sessions[0].subagentFileURLs.keys.first == "subagent:agent-abc123")
    }

    @Test func missingRootReportsUnavailable() async {
        let root = URL(fileURLWithPath: "/nonexistent-vayen-test-root-\(UUID().uuidString)")
        let result = await ClaudeAdapter().discover(under: root)
        #expect(!result.rootExists)
        #expect(result.sessions.isEmpty)
    }

    @Test func fullLoadMergesSubagentEventsAndExtractsSummary() async throws {
        let root = try Fixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try Fixture.writeTranscript(lines: [
            Fixture.userPrompt(uuid: "p1", text: "Build the thing", ts: "2026-09-14T10:00:00Z"),
            Fixture.assistant(uuid: "a1", ts: "2026-09-14T10:01:00Z", blocks: [Fixture.textBlock("On it.")], stop: "end_turn"),
            Fixture.customTitle("Custom name"),
        ], root: root)
        let sessionID = file.deletingPathExtension().lastPathComponent
        let subDir = root.appendingPathComponent("-tmp-proj").appendingPathComponent(sessionID).appendingPathComponent("subagents")
        try FileManager.default.createDirectory(at: subDir, withIntermediateDirectories: true)
        try ([Fixture.assistant(uuid: "sa1", session: sessionID, ts: "2026-09-14T10:00:30Z", blocks: [Fixture.textBlock("subagent note")])]
            .joined(separator: "\n") + "\n")
            .write(to: subDir.appendingPathComponent("agent-x.jsonl"), atomically: true, encoding: .utf8)

        let result = await ClaudeAdapter().discover(under: root)
        let load = await ClaudeAdapter().loadSession(result.sessions[0], tailer: TranscriptTailer())
        #expect(load.session.events.contains { $0.subagentFileKey == "subagent:agent-x" })
        #expect(load.session.projectPath == "/tmp/proj")
        #expect(load.session.customTitle == "Custom name")
        #expect(load.session.lastTurnEndAt != nil)
        // Cursors are positioned at EOF for each file.
        #expect(load.cursors["main"] != nil)
        #expect(load.cursors["subagent:agent-x"] != nil)
    }

    @Test func sourcesAreNotMutatedByDiscoveryOrLoad() async throws {
        let root = try Fixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try Fixture.writeTranscript(lines: [
            Fixture.userPrompt(text: "do not touch", ts: "2026-09-14T10:00:00Z"),
        ], root: root)
        let before = try Data(contentsOf: file)

        let result = await ClaudeAdapter().discover(under: root)
        _ = await ClaudeAdapter().loadSession(result.sessions[0], tailer: TranscriptTailer())
        _ = await ClaudeAdapter().digest(result.sessions[0])

        let after = try Data(contentsOf: file)
        #expect(before == after)
    }
}
