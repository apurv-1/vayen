import SwiftUI
import VayenCore

/// Single popover surface. All views - list, conversation, settings, setup -
/// live inside it; nothing detaches into a window.
struct PopoverRootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            V.base.ignoresSafeArea()
            switch model.route {
            case .onboarding:
                OnboardingView()
            case .sessions:
                SessionListView()
            case .conversation:
                ConversationView()
            case .settings:
                SettingsView()
            }
        }
        .frame(width: 420, height: 560)
        .animation(.easeOut(duration: 0.15), value: model.route)
    }
}
