import SwiftUI
import VayenCore

/// Secondary surface: provider setup, key storage, source root, and data
/// handling notes. The stored key is never shown back; only its presence.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var keyDraft = ""
    @State private var rootDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            VHairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    providerSection
                    VHairline()
                    keySection
                    VHairline()
                    sourceSection
                    VHairline()
                    privacySection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            VHairline()
            footer
        }
        .onAppear {
            rootDraft = model.settings.claudeSourceRootOverride ?? ""
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                model.route = .sessions
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(V.ink2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to sessions")
            Text("Settings")
                .font(.vTitle)
                .foregroundStyle(V.ink)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var providerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Voice provider")
                .font(.vTitle)
                .foregroundStyle(V.ink)
            Picker("Voice provider", selection: $model.voiceProvider) {
                ForEach(VoiceProviderKind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            if model.voiceProvider == .elevenLabs {
                Text("ElevenLabs support is not wired in this build yet.")
                    .font(.vMeta)
                    .foregroundStyle(V.ink2)
            }
        }
    }

    private var keySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Deepgram API key")
                .font(.vTitle)
                .foregroundStyle(V.ink)
            HStack(spacing: 8) {
                SecureField(
                    model.hasDeepgramKey ? "Stored in Keychain" : "Paste your Deepgram key",
                    text: $keyDraft
                )
                .textFieldStyle(.plain)
                .font(.vBody)
                .foregroundStyle(V.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(V.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8).stroke(V.hairline, lineWidth: 1)
                )
                Button("Save") {
                    model.saveDeepgramKey(keyDraft)
                    keyDraft = ""
                }
                .font(.vMeta.weight(.medium))
                .foregroundStyle(V.accent)
                .buttonStyle(.plain)
                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if model.hasDeepgramKey {
                    Button("Remove") {
                        model.saveDeepgramKey("")
                    }
                    .font(.vMeta)
                    .foregroundStyle(V.live)
                    .buttonStyle(.plain)
                }
            }
            Text("Your key stays in the macOS Keychain. Audio and selected-session evidence go to Deepgram; see their retention terms.")
                .font(.vMeta)
                .foregroundStyle(V.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Code transcripts")
                .font(.vTitle)
                .foregroundStyle(V.ink)
            HStack(spacing: 8) {
                TextField("~/.claude/projects (default)", text: $rootDraft)
                    .textFieldStyle(.plain)
                    .font(.vBody)
                    .foregroundStyle(V.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8).fill(V.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8).stroke(V.hairline, lineWidth: 1)
                    )
                Button("Apply") {
                    model.setSourceRoot(rootDraft.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .font(.vMeta.weight(.medium))
                .foregroundStyle(V.accent)
                .buttonStyle(.plain)
            }
        }
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Privacy")
                .font(.vTitle)
                .foregroundStyle(V.ink)
            Text("Transcripts are read-only. Vayen never writes to Claude Code.")
            Text("Only the session you select is sent to the voice provider.")
            Text("Microphone audio is never stored.")
        }
        .font(.vMeta)
        .foregroundStyle(V.ink2)
    }

    private var footer: some View {
        HStack {
            Text("Vayen \(versionString)")
                .font(.vMeta)
                .foregroundStyle(V.ink2)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }

    private var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
