import SwiftUI
import VayenCore

/// One session's observer conversation: identity and evidence freshness up
/// top, readable transcript in the middle, mic and text fallback at the
/// bottom. Listening state is always text plus symbol, never color alone.
struct ConversationView: View {
    @EnvironmentObject private var model: AppModel
    @State private var coverageExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            header
            VHairline()
            evidenceLine
            VHairline()
            transcript
            if let banner = model.errorBanner {
                VHairline()
                errorBanner(banner)
            }
            VHairline()
            statusLine
            bottomBar
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                model.backToList()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(V.ink2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to sessions")
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selected?.title ?? "Session")
                    .font(.vTitle)
                    .foregroundStyle(V.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let project = model.selected?.projectPath {
                    Text(abbreviate(project))
                        .font(.vMeta)
                        .foregroundStyle(V.ink2)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var evidenceLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let version = model.snapshotVersion {
                    Text("Evidence v\(version)" + cutoffSuffix)
                        .font(.vMeta)
                        .foregroundStyle(V.ink2)
                } else {
                    Text("Loading evidence…")
                        .font(.vMeta)
                        .foregroundStyle(V.ink2)
                }
                if model.newActivityAvailable {
                    Text("New activity")
                        .font(.vMeta.weight(.medium))
                        .foregroundStyle(V.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(V.accent.opacity(0.10)))
                }
                Spacer()
            }
            if !model.snapshotLimitations.isEmpty {
                DisclosureGroup(isExpanded: $coverageExpanded) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(model.snapshotLimitations, id: \.self) { note in
                            Text(note)
                                .font(.vMeta)
                                .foregroundStyle(V.ink2)
                        }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("Coverage notes")
                        .font(.vMeta)
                        .foregroundStyle(V.ink2)
                }
                .tint(V.ink2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cutoffSuffix: String {
        guard let cutoff = model.snapshotCutoff else { return "" }
        return " · through " + cutoff.formatted(date: .omitted, time: .standard)
    }

    @ViewBuilder
    private var transcript: some View {
        if model.messages.isEmpty && model.convoStatus == .ready {
            emptyTranscript
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .onChange(of: model.messages.count) { _, _ in
                    if let last = model.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyTranscript: some View {
        VStack(spacing: 12) {
            Text("Ask what this session is doing.")
                .font(.vBody)
                .foregroundStyle(V.ink2)
            VStack(spacing: 8) {
                ForEach(Self.suggestions, id: \.self) { question in
                    Button(question) { model.sendFollowUp(question) }
                        .font(.vMeta)
                        .foregroundStyle(V.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(V.accent.opacity(0.10))
                        )
                        .buttonStyle(.plain)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static let suggestions = [
        "What are you doing right now?",
        "What was the original task?",
        "What did you change?",
    ]

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Text(message)
                .font(.vMeta)
                .foregroundStyle(V.live)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button {
                model.errorBanner = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(V.live)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8).fill(V.live.opacity(0.10))
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            if model.convoStatus == .listening {
                Image(systemName: "mic.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(V.live)
            }
            Text(statusText)
                .font(.vMeta)
                .foregroundStyle(V.ink2)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private var statusText: String {
        switch model.convoStatus {
        case .connecting: "Connecting to voice…"
        case .ready: "Ready. Tap the mic or type."
        case .listening: "Listening"
        case .thinking: "Thinking"
        case .speaking: "Speaking"
        case .ended: "Conversation ended"
        case .failed: "Voice unavailable - text still works if connected"
        case .idle: ""
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                model.micTapped()
            } label: {
                Image(systemName: model.micOn ? "mic.fill" : "mic")
                    .font(.system(size: 15))
                    .foregroundStyle(model.micOn ? V.live : V.ink)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(model.micOn ? V.live.opacity(0.12) : V.surface)
                    )
                    .overlay(
                        Circle().stroke(V.hairline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!micEnabled)
            .accessibilityLabel(model.micOn ? "Stop microphone" : "Start microphone")
            .keyboardShortcut("m", modifiers: .command)

            TextField("Type a question", text: $model.draft)
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
                .onSubmit { model.sendDraft() }

            Button {
                model.sendDraft()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(V.accent)
            }
            .buttonStyle(.plain)
            .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !sendEnabled)
            .accessibilityLabel("Send question")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var micEnabled: Bool {
        switch model.convoStatus {
        case .ready, .listening, .thinking, .speaking: true
        case .idle, .connecting, .ended, .failed: false
        }
    }

    private var sendEnabled: Bool {
        switch model.convoStatus {
        case .ready, .listening, .thinking, .speaking: true
        case .idle, .connecting, .ended, .failed: false
        }
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.text)
                .font(.vBody)
                .foregroundStyle(V.ink)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(bubbleBackground)
                .frame(maxWidth: 300, alignment: message.role == .user ? .trailing : .leading)
            if message.role != .user { Spacer(minLength: 40) }
        }
    }

    private var bubbleBackground: some View {
        Group {
            if message.role == .user {
                RoundedRectangle(cornerRadius: 10).fill(V.accent.opacity(0.10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(V.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10).stroke(V.hairline, lineWidth: 1)
                    )
            }
        }
    }
}

private func abbreviate(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}
