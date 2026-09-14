import AppKit

// Menu-bar-only app: accessory activation policy keeps it out of the Dock and
// app switcher. All UI lives inside the popover owned by AppDelegate.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
