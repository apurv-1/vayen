import Foundation

/// Non-secret preferences. Secrets never live here; they go to Keychain.
public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "ai.vayen.settings")

    public static let shared = SettingsStore()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private enum Key: String {
        case voiceProvider = "vayen.voiceProvider"
        case sourceRootOverride = "vayen.sourceRoot.claude"
        case thinkModel = "vayen.thinkModel"
        case thinkProvider = "vayen.thinkProvider"
        case speakModel = "vayen.speakModel"
        case didCompleteOnboarding = "vayen.didCompleteOnboarding"
    }

    public var voiceProvider: VoiceProviderKind {
        get { queue.sync { VoiceProviderKind(rawValue: defaults.string(forKey: Key.voiceProvider.rawValue) ?? "") ?? .deepgram } }
        set { queue.sync { defaults.set(newValue.rawValue, forKey: Key.voiceProvider.rawValue) } }
    }

    /// Override for Claude's projects root (e.g. a nonstandard CLAUDE_CONFIG_DIR).
    /// nil means the default `~/.claude/projects`.
    public var claudeSourceRootOverride: String? {
        get { queue.sync { defaults.string(forKey: Key.sourceRootOverride.rawValue) } }
        set { queue.sync { defaults.set(newValue, forKey: Key.sourceRootOverride.rawValue) } }
    }

    public var thinkProvider: String {
        get { queue.sync { defaults.string(forKey: Key.thinkProvider.rawValue) ?? "open_ai" } }
        set { queue.sync { defaults.set(newValue, forKey: Key.thinkProvider.rawValue) } }
    }

    public var thinkModel: String {
        get { queue.sync { defaults.string(forKey: Key.thinkModel.rawValue) ?? "gpt-4.1-mini" } }
        set { queue.sync { defaults.set(newValue, forKey: Key.thinkModel.rawValue) } }
    }

    public var speakModel: String {
        get { queue.sync { defaults.string(forKey: Key.speakModel.rawValue) ?? "aura-2-thalia-en" } }
        set { queue.sync { defaults.set(newValue, forKey: Key.speakModel.rawValue) } }
    }

    public var didCompleteOnboarding: Bool {
        get { queue.sync { defaults.bool(forKey: Key.didCompleteOnboarding.rawValue) } }
        set { queue.sync { defaults.set(newValue, forKey: Key.didCompleteOnboarding.rawValue) } }
    }
}

public enum VoiceProviderKind: String, Sendable, Codable, CaseIterable {
    case deepgram
    case elevenLabs

    public var displayName: String {
        switch self {
        case .deepgram: "Deepgram"
        case .elevenLabs: "ElevenLabs"
        }
    }
}
