import SwiftUI
import VayenCore

/// Menu-bar list: discovered sessions, honest activity labels, Talk action.
struct SessionListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            header
            VHairline()
            content
            VHairline()
            footer
        }
    }

    private var header: some View {
        HStack {
            Text("Vayen")
                .font(.vIdentity)
                .foregroundStyle(V.ink)
            Spacer()
            Button {
                model.route = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(V.ink2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            Button("Quit") { model.quit() }
                .font(.vMeta)
                .foregroundStyle(V.ink2)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if let error = model.discoveryError {
            emptyState(
                title: "No sessions visible",
                detail: error,
                action: "Open settings"
            ) { model.route = .settings }
        } else if model.sessions.isEmpty && model.loadingSessions {
            VStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking for sessions…").font(.vMeta).foregroundStyle(V.ink2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.sessions.isEmpty {
            emptyState(
                title: "No sessions found",
                detail: "Vayen watches Claude Code transcripts under your configured source root. Start a Claude Code session and it will appear here.",
                action: nil,
                actionBody: {}
            )
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.sessions) { summary in
                        SessionRow(summary: summary) {
                            model.openConversation(for: summary)
                        }
                        VHairline().padding(.leading, 20)
                    }
                }
            }
        }
    }

    private func emptyState(title: String, detail: String, action: String?, actionBody: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.vTitle).foregroundStyle(V.ink)
            Text(detail)
                .font(.vMeta)
                .foregroundStyle(V.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            if let action {
                Button(action, action: actionBody)
                    .font(.vMeta)
                    .foregroundStyle(V.accent)
                    .buttonStyle(.plain)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 10))
                .foregroundStyle(V.ink2)
            Text(model.discoveryError == nil ? "Watching Claude Code transcripts" : "Discovery off")
                .font(.vMeta)
                .foregroundStyle(V.ink2)
            Spacer()
            if model.hasDeepgramKey == false {
                Text("No voice key")
                    .font(.vMeta)
                    .foregroundStyle(V.live)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 9)
    }
}

struct SessionRow: View {
    let summary: SessionSummary
    let onTalk: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(summary.title)
                    .font(.vTitle)
                    .foregroundStyle(V.ink)
                    .lineLimit(2)
                    .truncationMode(.tail)
                HStack(spacing: 6) {
                    Text(summary.identity.harness.displayName)
                    if let project = summary.projectPath {
                        Text("·")
                        Text(abbreviate(project))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                .font(.vMeta)
                .foregroundStyle(V.ink2)
                Text(activityLabel)
                    .font(.vMeta)
                    .foregroundStyle(V.ink2)
            }
            Spacer(minLength: 8)
            Button("Talk", action: onTalk)
                .font(.vMeta.weight(.medium))
                .foregroundStyle(V.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(V.accent.opacity(hovering ? 0.16 : 0.10))
                )
                .buttonStyle(.plain)
                .accessibilityLabel("Talk about \(summary.title)")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(hovering ? V.surface.opacity(0.5) : .clear)
        .onHover { hovering = $0 }
        .contentShape(Rectangle())
    }

    /// Honest activity wording: observed timestamps, never inferred state.
    private var activityLabel: String {
        if let last = summary.lastEventAt {
            return "Updated \(Self.relative(last))"
        }
        if let modified = summary.fileModifiedAt {
            return "Source changed \(Self.relative(modified))"
        }
        return "Status unavailable"
    }

    static func relative(_ date: Date) -> String {
        let delta = Date().timeIntervalSince(date)
        if delta < 45 { return "just now" }
        if delta < 3600 { return "\(Int(delta / 60))m ago" }
        if delta < 86400 { return "\(Int(delta / 3600))h ago" }
        return "\(Int(delta / 86400))d ago"
    }
}

private func abbreviate(_ path: String) -> String {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}
