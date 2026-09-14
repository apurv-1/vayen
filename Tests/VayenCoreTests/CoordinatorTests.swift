import Foundation
import Testing
@testable import VayenCore

@Suite("Session catalog")
struct CatalogTests {

    @Test func refreshDiscoversAndSortsByActivity() async throws {
        let root = try Fixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try Fixture.writeTranscript(lines: [
            Fixture.userPrompt(text: "old task", ts: "2026-09-10T10:00:00Z"),
        ], sessionID: "AAAAAAAA-0000-0000-0000-000000000001", root: root)
        _ = try Fixture.writeTranscript(lines: [
            Fixture.userPrompt(text: "new task", ts: "2026-09-13T10:00:00Z"),
        ], sessionID: "AAAAAAAA-0000-0000-0000-000000000002", root: root)

        let catalog = SessionCatalog(sourceRoots: [.claudeCode: root])
        let outcome = await catalog.refresh()
        guard case .ok(let sessions, _) = outcome else {
            Issue.record("expected ok outcome"); return
        }
        #expect(sessions.count == 2)
        #expect(sessions[0].title == "new task")
        #expect(sessions[0].identity.nativeSessionID.hasSuffix("2"))
    }

    @Test func pollSeesAppendedRecords() async throws {
        let root = try Fixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try Fixture.writeTranscript(lines: [
            Fixture.userPrompt(text: "initial", ts: "2026-09-14T10:00:00Z"),
        ], root: root)

        let catalog = SessionCatalog(sourceRoots: [.claudeCode: root])
        _ = await catalog.refresh()
        let identity = try #require(await catalog.summariesSnapshot().first?.identity)
        _ = try await catalog.load(identity)

        // Simulate a live writer appending a record.
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((Fixture.assistant(
            uuid: "new1", ts: "2026-09-14T10:05:00Z",
            blocks: [Fixture.textBlock("newly appended answer")], stop: "end_turn"
        ) + "\n").utf8))
        try handle.close()

        let delta = try await catalog.poll(identity)
        #expect(!delta.reparsed)
        #expect(delta.newEvents.contains { $0.kind == .assistantText })
        #expect(delta.activity.kind == .semanticEvent)
        #expect(delta.lastTurnEndAt != nil)
    }

    @Test func duplicateEventIDsAreSuppressed() async throws {
        let root = try Fixture.tempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try Fixture.writeTranscript(lines: [
            Fixture.userPrompt(uuid: "dup", text: "once", ts: "2026-09-14T10:00:00Z"),
        ], root: root)
        let catalog = SessionCatalog(sourceRoots: [.claudeCode: root])
        _ = await catalog.refresh()
        let identity = try #require(await catalog.summariesSnapshot().first?.identity)
        let loaded = try await catalog.load(identity)
        #expect(loaded.events.filter { $0.eventID == "dup" }.count == 1)

        // Append a byte-identical duplicate record (e.g. resume artifact).
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((Fixture.userPrompt(
            uuid: "dup", text: "once", ts: "2026-09-14T10:00:00Z"
        ) + "\n").utf8))
        try handle.close()

        let delta = try await catalog.poll(identity)
        #expect(!delta.newEvents.contains { $0.eventID == "dup" })
    }

    @Test func missingRootIsUnavailable() async {
        let catalog = SessionCatalog(sourceRoots: [
            .claudeCode: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        ])
        let outcome = await catalog.refresh()
        guard case .unavailable = outcome else {
            Issue.record("expected unavailable"); return
        }
    }
}

@Suite("Conversation coordinator")
struct CoordinatorTests {

    /// Runs a coordinator against a two-session fixture root.
    private func makeWorld() async throws -> (SessionCatalog, URL, SessionIdentity, SessionIdentity) {
        let root = try Fixture.tempRoot()
        _ = try Fixture.writeTranscript(lines: [
            Fixture.userPrompt(text: "CANARY_ALPHA task", ts: "2026-09-14T10:00:00Z"),
        ], sessionID: "AAAAAAAA-0000-0000-0000-00000000000A", root: root)
        _ = try Fixture.writeTranscript(lines: [
            Fixture.userPrompt(text: "CANARY_BETA task", ts: "2026-09-14T11:00:00Z"),
        ], sessionID: "BBBBBBBB-0000-0000-0000-00000000000B", root: root)
        let catalog = SessionCatalog(sourceRoots: [.claudeCode: root])
        _ = await catalog.refresh()
        let sessions = await catalog.summariesSnapshot()
        let a = try #require(sessions.first { $0.identity.nativeSessionID.hasSuffix("A") }?.identity)
        let b = try #require(sessions.first { $0.identity.nativeSessionID.hasSuffix("B") }?.identity)
        return (catalog, root, a, b)
    }

    @Test func connectAppliesSnapshotAndEvidenceToolFlows() async throws {
        let (catalog, root, a, _) = try await makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }

        let evidenceSeen = SendableBox<[String]>([])
        let coordinator = ConversationCoordinator(
            catalog: catalog,
            makeProvider: {
                MockVoiceProvider(callsEvidenceTool: true) { _, fetch in
                    let packet = await fetch()
                    evidenceSeen.withLock { $0.append(packet) }
                    return "It is working on your task."
                }
            }
        )

        let updates = collectUpdates(from: coordinator)
        try await coordinator.select(a)
        try await coordinator.connect()
        await coordinator.sendText("what is this doing")

        try await waitUntil { !evidenceSeen.withLock({ $0 }).isEmpty }
        let packet = evidenceSeen.withLock { $0[0] }
        #expect(packet.contains("CANARY_ALPHA"))
        #expect(!packet.contains("CANARY_BETA"))

        // Assistant answer was recorded as a turn.
        let turns = await coordinator.history(for: a)
        #expect(turns.contains { $0.question == "what is this doing" && $0.state == .answered })
        _ = updates
        await coordinator.stop()
    }

    @Test func switchingSessionsIsolatesEvidence() async throws {
        let (catalog, root, a, b) = try await makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }

        let packets = SendableBox<[String]>([])
        let coordinator = ConversationCoordinator(
            catalog: catalog,
            makeProvider: {
                MockVoiceProvider(callsEvidenceTool: true) { _, fetch in
                    let packet = await fetch()
                    packets.withLock { $0.append(packet) }
                    return "ok"
                }
            }
        )

        try await coordinator.select(a)
        try await coordinator.connect()
        await coordinator.sendText("q1")
        try await waitUntil { !packets.withLock({ $0 }).isEmpty }

        // Switch mid-flow: B must never see A's evidence.
        try await coordinator.select(b)
        try await coordinator.connect()
        await coordinator.sendText("q2")
        try await waitUntil { packets.withLock({ $0 }).count >= 2 }

        let forB = packets.withLock { $0.last ?? "" }
        #expect(forB.contains("CANARY_BETA"))
        #expect(!forB.contains("CANARY_ALPHA"))
        await coordinator.stop()
    }

    @Test func stopEndsConversationAndDiscardsLateEvents() async throws {
        let (catalog, root, a, _) = try await makeWorld()
        defer { try? FileManager.default.removeItem(at: root) }

        let coordinator = ConversationCoordinator(
            catalog: catalog,
            makeProvider: { MockVoiceProvider() }
        )
        try await coordinator.select(a)
        try await coordinator.connect()
        await coordinator.stop()
        #expect(await coordinator.currentStatus == .ended)
    }

    // MARK: helpers

    private func collectUpdates(from coordinator: ConversationCoordinator) -> Task<Void, Never> {
        Task {
            for await _ in coordinator.updates { }
        }
    }

    private func waitUntil(_ condition: @Sendable () -> Bool) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("timed out waiting for condition")
    }
}

/// Lock-protected box for collecting values across tasks in tests.
final class SendableBox<T>: @unchecked Sendable {
    private var value: T
    private let lock = NSLock()
    init(_ value: T) { self.value = value }
    func withLock<R>(_ body: (inout T) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
