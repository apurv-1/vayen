import SwiftUI

/// Vayen "quiet instrument" tokens (planning/design-brief.md): warm neutral
/// surfaces, one restrained accent, hairline separators, system type.
enum V {
    static func color(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(hex: hex)
        })
    }

    /// Warm paper base.
    static let base = color(light: 0xF7F6F2, dark: 0x191C1A)
    /// Reading surface.
    static let surface = color(light: 0xFFFFFF, dark: 0x222723)
    /// Primary text.
    static let ink = color(light: 0x20231F, dark: 0xF1F3EE)
    /// Secondary text.
    static let ink2 = color(light: 0x5B6157, dark: 0x9AA69D)
    /// Single accent: forest / sage.
    static let accent = color(light: 0x245F4D, dark: 0xA6C6B4)
    /// Hairline separator.
    static let hairline = color(light: 0xE3E0D8, dark: 0x333833)
    /// Listening/recording emphasis (kept semantic, never color-only).
    static let live = color(light: 0x8C2F26, dark: 0xD98880)
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Font {
    static let vIdentity = Font.system(size: 17, weight: .semibold)
    static let vTitle = Font.system(size: 14, weight: .medium)
    static let vBody = Font.system(size: 13)
    static let vMeta = Font.system(size: 11.5)
    static let vMono = Font.system(size: 11.5, design: .monospaced)
}

/// Compact hairline divider on the warm surface.
struct VHairline: View {
    var body: some View {
        Rectangle().fill(V.hairline).frame(height: 1)
    }
}
