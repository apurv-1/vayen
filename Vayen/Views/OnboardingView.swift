import SwiftUI
import VayenCore

/// First-run setup inside the popover: what Vayen observes, where the key
/// lives, and what crosses the network. Voice key entry is optional here.
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var keyDraft = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Vayen")
                        .font(.vIdentity)
                        .foregroundStyle(V.ink)
                    Text("Ask what your coding agents are doing. Vayen reads local Claude Code transcripts and explains the session you pick, by voice or text. It never controls the agent or edits its files.")
                        .font(.vBody)
                        .foregroundStyle(V.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 10) {
                        checkRow(symbol: "doc.text.magnifyingglass", text: "Reads ~/.claude/projects (read-only)")
                        checkRow(symbol: "key.fill", text: "Your Deepgram key, stored in Keychain")
                        checkRow(symbol: "mic", text: "Microphone only when you tap the mic")
                    }

                    VHairline()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Deepgram API key")
                            .font(.vTitle)
                            .foregroundStyle(V.ink)
                        HStack(spacing: 8) {
                            SecureField("Paste your Deepgram key", text: $keyDraft)
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
                            Button("Save key") {
                                model.saveDeepgramKey(keyDraft)
                                keyDraft = ""
                            }
                            .font(.vMeta.weight(.medium))
                            .foregroundStyle(V.accent)
                            .buttonStyle(.plain)
                            .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if model.hasDeepgramKey {
                            Text("Key saved")
                                .font(.vMeta)
                                .foregroundStyle(V.accent)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
            VHairline()
            footer
        }
    }

    private func checkRow(symbol: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundStyle(V.accent)
                .frame(width: 18)
            Text(text)
                .font(.vBody)
                .foregroundStyle(V.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button("Continue") { model.finishOnboarding() }
                .font(.vBody.weight(.medium))
                .foregroundStyle(V.base)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(V.accent)
                )
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            Button("Skip for now") { model.finishOnboarding() }
                .font(.vMeta)
                .foregroundStyle(V.ink2)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
