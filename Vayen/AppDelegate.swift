import AppKit
import Combine
import SwiftUI
import VayenCore

/// Owns the status item and the one popover. Every dismissal path funnels into
/// `popoverDidClose`, which tears down capture, playback, and the live turn.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()
    private var appliedMenuBarState: AppModel.MenuBarState = .idle
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.onLaunch()

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(named: "MenuBarIdle")
            image?.accessibilityDescription = "Vayen"
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.action = #selector(togglePopover)
            button.target = self
        }
        statusItem = item

        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.applyMenuBarState() }
            }
            .store(in: &cancellables)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: 420, height: 560)
        let hosting = NSHostingController(rootView: PopoverRootView().environmentObject(model))
        popover.contentViewController = hosting
        self.popover = popover
    }

    private func applyMenuBarState() {
        let state = model.menuBarState
        guard state != appliedMenuBarState else { return }
        appliedMenuBarState = state
        let image = NSImage(named: state.assetName)
        image?.accessibilityDescription = "Vayen"
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Activate so the popover can take keyboard focus and own the mic
            // permission dialog if one appears.
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            model.popoverShown()
        }
    }

    // MARK: - NSPopoverDelegate

    /// Single teardown point for every dismissal: outside click, Escape,
    /// programmatic close. Stops capture, playback, and the live turn.
    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.model.popoverDismissed()
        }
    }

    func popoverShouldDetach(_ popover: NSPopover) -> Bool {
        // The product keeps conversation inside the popover; never detach.
        false
    }
}
