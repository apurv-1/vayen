import Foundation
import VayenCore

/// Stage 0 validation tool. Read-only against all session sources.
///
///   vayen-cli discover [--root PATH]      list sessions the catalog can see
///   vayen-cli tail <session-id-prefix>    follow appended records live
///   vayen-cli evidence <id> [question]    print the model-facing packet
///   vayen-cli talk <id>                   text-mode conversation (mock voice)
@main
struct VayenCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            print(usage)
            return
        }

        var root = ClaudeAdapter.defaultSourceRoot
        var rest = Array(args.dropFirst())
        if let i = rest.firstIndex(of: "--root"), rest.indices.contains(i + 1) {
            root = URL(fileURLWithPath: rest[i + 1])
            rest.removeSubrange(i...i + 1)
        }

        let catalog = SessionCatalog(sourceRoots: [.claudeCode: root])

        switch command {
        case "discover":
            await discover(catalog: catalog)
        case "tail":
            guard let prefix = rest.first else { return print("tail needs a session id prefix") }
            await tail(catalog: catalog, prefix: prefix)
        case "evidence":
            guard let prefix = rest.first else { return print("evidence needs a session id prefix") }
            let question = rest.dropFirst().joined(separator: " ")
            await evidence(catalog: catalog, prefix: prefix, question: question.isEmpty ? nil : question)
        case "talk":
            guard let prefix = rest.first else { return print("talk needs a session id prefix") }
            await talk(catalog: catalog, prefix: prefix)
        default:
            print(usage)
        }
    }

    static let usage = """
        vayen-cli - Vayen Stage 0 validation tool
          discover [--root PATH]     list discovered sessions
          tail <id-prefix>           follow new transcript records live
          evidence <id> [question]   print the evidence packet the model would see
          talk <id>                  text-mode conversation via mock voice provider
        """

    static func discover(catalog: SessionCatalog) async {
        let started = ContinuousClock.now
        let outcome = await catalog.refresh()
        let elapsed = ContinuousClock.now - started
        switch outcome {
        case .unavailable(let reason):
            print("Discovery unavailable: \(reason)")
        case .ok(let sessions, let diagnostics):
            print("Discovered \(sessions.count) session(s) in \(elapsed)")
            for s in sessions {
                let project = s.projectPath.map { abbreviate($0) } ?? "(no cwd)"
                let when = s.lastEventAt.map { reltime($0) } ?? "no timestamps"
                print("• \(s.identity.nativeSessionID.prefix(8))  \(s.title)")
                print("    \(s.identity.harness.displayName)  \(project)  \(when)  events:\(s.eventCount) subagents:\(s.subagentFileCount)")
            }
            for d in diagnostics { print("  diag: \(d)") }
        }
    }

    static func findSession(catalog: SessionCatalog, prefix: String) async -> SessionIdentity? {
        _ = await catalog.refresh()
        let matches = await catalog.summariesSnapshot().filter {
            $0.identity.nativeSessionID.hasPrefix(prefix)
        }
        if matches.isEmpty {
            print("No session matching '\(prefix)'")
            return nil
        }
        if matches.count > 1 {
            print("Ambiguous prefix '\(prefix)': \(matches.map { $0.identity.nativeSessionID.prefix(8) })")
            return nil
        }
        return matches[0].identity
    }

    static func tail(catalog: SessionCatalog, prefix: String) async {
        guard let identity = await findSession(catalog: catalog, prefix: prefix) else { return }
        do {
            let session = try await catalog.load(identity)
            print("Loaded \(session.events.count) events. Watching for appends (Ctrl-C to stop)…")
            while true {
                try? await Task.sleep(for: .milliseconds(500))
                guard let delta = try? await catalog.poll(identity) else { continue }
                if delta.reparsed {
                    print("== source replaced/truncated; reparsed ==")
                }
                for event in delta.newEvents {
                    let time = event.timestamp.map { ISO8601DateFormatter().string(from: $0) } ?? "--:--:--"
                    let text = EvidenceBuilder.render(event) ?? "(no text)"
                    print("[\(time)] \(event.kind.rawValue): \(text.prefix(200))")
                }
            }
        } catch {
            print("Load failed: \(error)")
        }
    }

    static func evidence(catalog: SessionCatalog, prefix: String, question: String?) async {
        guard let identity = await findSession(catalog: catalog, prefix: prefix) else { return }
        do {
            let session = try await catalog.load(identity)
            let version = await catalog.nextSnapshotVersion(for: identity)
            let snapshot = EvidenceBuilder().snapshot(session: session, version: version, question: question)
            print(ExplainerPrompt.packet(from: snapshot))
        } catch {
            print("Load failed: \(error)")
        }
    }

    static func talk(catalog: SessionCatalog, prefix: String) async {
        guard let identity = await findSession(catalog: catalog, prefix: prefix) else { return }

        let coordinator = ConversationCoordinator(
            catalog: catalog,
            audio: AgentAudioPipeline(),
            makeProvider: {
                MockVoiceProvider(callsEvidenceTool: true) { question, fetch in
                    _ = question
                    return await fetch()
                }
            }
        )

        do {
            try await coordinator.select(identity)
            try await coordinator.connect()
        } catch {
            print("Connect failed: \(error)")
            return
        }

        let updates = coordinator.updates
        let printer = Task {
            for await update in updates {
                switch update {
                case .status(let s): print("[status: \(s.rawValue)]")
                case .userUtterance(let t): print("you: \(t)")
                case .assistantUtterance(let t): print("vayen: \(t)")
                case .snapshotApplied(let v, let cutoff, _):
                    print("[evidence snapshot v\(v), cutoff \(cutoff.map { reltime($0) } ?? "none")]")
                case .newActivityAvailable: print("[new transcript activity]")
                case .failure(let m): print("[error: \(m)]")
                }
            }
        }

        print("Text mode (mock provider, evidence tool active). Type a question, 'quit' to exit.")
        while let line = readLine(strippingNewline: true) {
            if line == "quit" { break }
            if line.isEmpty { continue }
            await coordinator.sendText(line)
        }
        await coordinator.stop()
        printer.cancel()
    }

    static func abbreviate(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    static func reltime(_ date: Date) -> String {
        let delta = Date().timeIntervalSince(date)
        if delta < 60 { return "just now" }
        if delta < 3600 { return "\(Int(delta / 60))m ago" }
        if delta < 86400 { return "\(Int(delta / 3600))h ago" }
        return "\(Int(delta / 86400))d ago"
    }
}
