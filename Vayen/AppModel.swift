import AppKit
import Foundation
import SwiftUI
import VayenCore

/// One rendered line of the observer conversation.
struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ConversationRole
    var text: String
}

@MainActor
final class AppModel: ObservableObject {

    enum Route {
        case onboarding, sessions, conversation, settings
    }

    enum MenuBarState: String {
        case idle, badge

        var assetName: String { rawValue == "idle" ? "MenuBarIdle" : "MenuBarBadge" }
    }

    // List state
    @Published var route: Route = .sessions
    @Published var sessions: [SessionSummary] = []
    @Published var discoveryError: String?
    @Published var loadingSessions = false

    // Conversation state
    @Published var selected: SessionSummary?
    @Published var convoStatus: ConversationCoordinator.Status = .idle
    @Published var messages: [ChatMessage] = []
    @Published var snapshotVersion: Int?
    @Published var snapshotCutoff: Date?
    @Published var snapshotLimitations: [String] = []
    @Published var newActivityAvailable = false
    @Published var errorBanner: String?
    @Published var micOn = false
    @Published var draft = ""

    /// Badge when a conversation is live or new activity landed; otherwise idle.
    var menuBarState: MenuBarState {
        switch convoStatus {
        case .connecting, .ready, .listening, .thinking, .speaking: return .badge
        default: return newActivityAvailable ? .badge : .idle
        }
    }

    // Settings
    @Published var voiceProvider: VoiceProviderKind {
        didSet { settings.voiceProvider = voiceProvider }
    }
    @Published var hasDeepgramKey: Bool

    let catalog: SessionCatalog
    let settings = SettingsStore.shared
    private var coordinator: ConversationCoordinator?
    private var updateTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    init() {
        let settings = SettingsStore.shared
        let root = settings.claudeSourceRootOverride.map { URL(fileURLWithPath: $0) }
            ?? ClaudeAdapter.defaultSourceRoot
        self.catalog = SessionCatalog(sourceRoots: [.claudeCode: root])
        self.voiceProvider = settings.voiceProvider
        self.hasDeepgramKey = KeychainStore.get(.deepgramAPIKey) != nil
    }

    func onLaunch() {
        if !settings.didCompleteOnboarding {
            route = .onboarding
        }
        Task { await refreshSessions() }
    }

    // MARK: - Popover lifecycle

    func popoverShown() {
        Task { await refreshSessions() }
    }

    /// The one place every dismissal lands. Stops capture, playback, turn,
    /// transport — and keeps only in-memory text.
    func popoverDismissed() {
        micOn = false
        newActivityAvailable = false
        let coordinator = self.coordinator
        self.coordinator = nil
        updateTask?.cancel()
        updateTask = nil
        Task { await coordinator?.popoverDismissed() }
        if route == .conversation { route = .sessions }
        convoStatus = .idle
    }

    // MARK: - Session list

    func refreshSessions() async {
        loadingSessions = sessions.isEmpty
        let outcome = await catalog.refresh()
        switch outcome {
        case .ok(let list, _):
            sessions = list
            discoveryError = nil
        case .unavailable(let reason):
            sessions = []
            discoveryError = reason
        }
        loadingSessions = false
    }

    // MARK: - Conversation

    func openConversation(for summary: SessionSummary) {
        selected = summary
        messages = []
        snapshotVersion = nil
        snapshotCutoff = nil
        snapshotLimitations = []
        errorBanner = nil
        route = .conversation
        startConversation()
    }

    private func makeCoordinator() -> ConversationCoordinator? {
        let makeProvider: @Sendable () -> any VoiceProvider
        switch voiceProvider {
        case .deepgram:
            guard let key = KeychainStore.get(.deepgramAPIKey) else {
                errorBanner = "Add your Deepgram API key in Settings to talk."
                return nil
            }
            let settings = self.settings
            makeProvider = {
                DeepgramVoiceProvider(configuration: .init(
                    apiKey: key,
                    thinkProvider: settings.thinkProvider,
                    thinkModel: settings.thinkModel,
                    speakModel: settings.speakModel
                ))
            }
        case .elevenLabs:
            errorBanner = "ElevenLabs support needs a private agent setup; it is not wired in this build yet."
            return nil
        }
        return ConversationCoordinator(catalog: catalog, makeProvider: makeProvider)
    }

    private func startConversation() {
        guard let identity = selected?.identity else { return }
        guard let coordinator = makeCoordinator() else {
            convoStatus = .failed
            return
        }
        self.coordinator = coordinator
        convoStatus = .connecting

        updateTask?.cancel()
        updateTask = Task { [weak self] in
            for await update in coordinator.updates {
                guard let self else { return }
                self.apply(update)
            }
        }

        Task {
            do {
                try await coordinator.select(identity)
                try await coordinator.connect()
            } catch {
                errorBanner = "Could not start the conversation: \(error.localizedDescription)"
                convoStatus = .failed
            }
        }
    }

    private func apply(_ update: ConversationCoordinator.Update) {
        switch update {
        case .status(let s):
            convoStatus = s
            if s == .listening { micOn = true }
            if s == .ended || s == .failed { micOn = false }
        case .userUtterance(let text):
            messages.append(ChatMessage(role: .user, text: text))
            newActivityAvailable = false
        case .assistantUtterance(let text):
            messages.append(ChatMessage(role: .assistant, text: text))
        case .snapshotApplied(let version, let cutoff, let limitations):
            snapshotVersion = version
            snapshotCutoff = cutoff
            snapshotLimitations = limitations
        case .newActivityAvailable:
            newActivityAvailable = true
        case .failure(let message):
            errorBanner = message
        }
    }

    func micTapped() {
        guard let coordinator else { return }
        if micOn {
            Task { await coordinator.stopListening() }
            micOn = false
        } else {
            Task { await coordinator.startListening() }
        }
    }

    func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let coordinator else { return }
        draft = ""
        Task { await coordinator.sendText(text) }
    }

    func sendFollowUp(_ text: String) {
        guard let coordinator else { return }
        Task { await coordinator.sendText(text) }
    }

    func backToList() {
        let coordinator = self.coordinator
        self.coordinator = nil
        updateTask?.cancel()
        updateTask = nil
        Task { await coordinator?.stop() }
        route = .sessions
        convoStatus = .idle
        micOn = false
        Task { await refreshSessions() }
    }

    // MARK: - Settings & onboarding

    func saveDeepgramKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete(.deepgramAPIKey)
            hasDeepgramKey = false
        } else {
            KeychainStore.set(trimmed, for: .deepgramAPIKey)
            hasDeepgramKey = true
        }
    }

    func setSourceRoot(_ path: String) {
        settings.claudeSourceRootOverride = path.isEmpty ? nil : path
        // Rebuild the catalog root; cheap since summaries are re-digested.
        let url = path.isEmpty ? ClaudeAdapter.defaultSourceRoot : URL(fileURLWithPath: path)
        Task {
            await catalog.setSourceRoot(url, for: .claudeCode)
            await refreshSessions()
        }
    }

    func finishOnboarding() {
        settings.didCompleteOnboarding = true
        route = .sessions
        Task { await refreshSessions() }
    }

    func quit() {
        let coordinator = self.coordinator
        Task { await coordinator?.stop() }
        NSApp.terminate(nil)
    }
}
