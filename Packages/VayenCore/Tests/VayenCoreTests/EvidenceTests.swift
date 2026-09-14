import Foundation
import Testing
@testable import VayenCore

@Suite("Evidence builder")
struct EvidenceTests {

    private func session(events: [NormalizedEvent], id: String = "s") -> LoadedSession {
        LoadedSession(
            identity: SessionIdentity(harness: .claudeCode, nativeSessionID: id, sourceRoot: "/r", projectKey: "p"),
            mainFileKey: "main",
            events: events,
            parserHealth: ParserHealth(),
            projectPath: "/tmp/proj",
            customTitle: nil,
            generatedTitle: nil,
            lastEventAt: events.compactMap(\.timestamp).max(),
            firstEventAt: events.compactMap(\.timestamp).min(),
            lastTurnEndAt: nil
        )
    }

    private func event(_ kind: EventKind, _ content: EventContent, idx: Int, ts: Date? = nil) -> NormalizedEvent {
        NormalizedEvent(
            source: SourceReference(fileKey: "main", generation: 0, recordIndex: idx),
            timestamp: ts ?? Date(timeIntervalSince1970: 1_700_000_000 + Double(idx)),
            actor: kind == .toolResult ? .tool : (kind == .assistantText || kind == .toolUse ? .assistant : .user),
            kind: kind,
            content: content
        )
    }

    @Test func originalTaskComesFromFirstUserPrompt() {
        let s = session(events: [
            event(.userPrompt, .text("Fix the cache eviction bug"), idx: 0),
            event(.assistantText, .text("Looking."), idx: 1),
        ])
        let snap = EvidenceBuilder().snapshot(session: s, version: 1)
        #expect(snap.originalTask?.text == "Fix the cache eviction bug")
        #expect(snap.version == 1)
    }

    @Test func missingOriginalPromptIsALimitationNotAFabrication() {
        let s = session(events: [
            event(.assistantText, .text("Continuing work."), idx: 0),
        ])
        let snap = EvidenceBuilder().snapshot(session: s, version: 1)
        #expect(snap.originalTask == nil)
        #expect(snap.limitations.contains { $0.contains("No original user request") })
    }

    @Test func thinkingAndMetadataNeverEnterEvidence() {
        let s = session(events: [
            event(.userPrompt, .text("task"), idx: 0),
            event(.thinking, .thinking, idx: 1),
            event(.metadata, .marker(name: "mode", detail: nil), idx: 2),
            event(.assistantText, .text("done"), idx: 3),
        ])
        let snap = EvidenceBuilder().snapshot(session: s, version: 1)
        #expect(!snap.items.contains { $0.kind == .thinking || $0.kind == .metadata })
        #expect(snap.limitations.contains { $0.contains("reasoning") })
    }

    @Test func budgetCapsItemsAndCountsOmitted() {
        var events = [event(.userPrompt, .text("task"), idx: 0)]
        for i in 1...200 {
            events.append(event(.assistantText, .text("step \(i) \(String(repeating: "y", count: 300))"), idx: i))
        }
        let s = session(events: events)
        let snap = EvidenceBuilder().snapshot(session: s, version: 1, budget: EvidenceBudget(maxCharacters: 4_000, maxItemCharacters: 500, recentFloor: 5))
        #expect(snap.omittedEventCount > 0)
        #expect(snap.items.count < 200)
        #expect(snap.estimatedTokens <= 1_100)
    }

    @Test func secretsAreRedacted() {
        let s = session(events: [
            event(.userPrompt, .text("use key sk-ant-abc1234567890xyz ok"), idx: 0),
            event(.assistantText, .text("token ghp_0123456789abcdefghij worked"), idx: 1),
        ])
        let snap = EvidenceBuilder().snapshot(session: s, version: 1)
        let all = ([snap.originalTask?.text ?? ""] + snap.items.map(\.text)).joined()
        #expect(!all.contains("sk-ant-abc1234567890xyz"))
        #expect(!all.contains("ghp_0123456789abcdefghij"))
        #expect(all.contains("[redacted"))
    }

    @Test func questionDirectedSelectionPullsRelevantOldEvents() {
        var events = [event(.userPrompt, .text("Investigate tokenizer bug"), idx: 0)]
        // A relevant old event mentioning parser.swift
        events.append(event(.toolUse, .toolUse(name: "Edit", summary: "/tmp/proj/parser.swift", toolUseID: "t1"), idx: 1))
        // Many irrelevant newer events
        for i in 2...80 {
            events.append(event(.assistantText, .text("unrelated step \(i)"), idx: i))
        }
        let s = session(events: events)
        let snap = EvidenceBuilder().snapshot(
            session: s, version: 1, question: "why did it edit parser.swift",
            budget: EvidenceBudget(maxCharacters: 20_000, maxItemCharacters: 400, recentFloor: 5)
        )
        #expect(snap.items.contains { $0.text.contains("parser.swift") })
    }

    @Test func snapshotPacketNamesCoverageAndCutoff() {
        let s = session(events: [
            event(.userPrompt, .text("task one"), idx: 0),
            event(.assistantText, .text("worked on it"), idx: 1),
        ])
        let snap = EvidenceBuilder().snapshot(session: s, version: 7)
        let packet = ExplainerPrompt.packet(from: snap)
        #expect(packet.contains("v7"))
        #expect(packet.contains("task one"))
        #expect(packet.contains("Recorded events"))
    }

    @Test func sessionIsolationInPackets() {
        // Session B canary must not appear in session A's packet.
        let a = session(events: [event(.userPrompt, .text("alpha task"), idx: 0)], id: "A")
        let b = session(events: [event(.userPrompt, .text("CANARY_B_SECRET"), idx: 0)], id: "B")
        let snapA = EvidenceBuilder().snapshot(session: a, version: 1)
        _ = b
        let packet = ExplainerPrompt.packet(from: snapA)
        #expect(!packet.contains("CANARY_B_SECRET"))
    }
}
