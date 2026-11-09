import AppKit

/// Shared vector artwork for the menu bar and the application icon.
@MainActor
struct IconArtwork {
    static let size = NSSize(width: 21, height: 20)

    private let keyboard: NSImage?
    private let badge: NSImage?
    private let badgeWidth: CGFloat

    init(badge name: String, color: NSColor) {
        let configuration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        keyboard = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        badge = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        badgeWidth = name == "lock.open.fill" ? 9 : 7
    }

    func draw(in rect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.minY)
        context.scaleBy(x: rect.width / Self.size.width, y: rect.height / Self.size.height)
        // Preserve the menu bar's optical alignment and transparent badge gap.
        context.translateBy(x: -1, y: -1)
        keyboard?.draw(in: NSRect(x: 0, y: 5, width: 21, height: 14))
        if let badge {
            context.saveGState()
            context.setBlendMode(.clear)
            NSBezierPath(roundedRect: NSRect(x: 13, y: 0.5, width: 11, height: 12), xRadius: 3, yRadius: 3).fill()
            context.restoreGState()
            badge.draw(in: NSRect(x: 18.5 - badgeWidth / 2, y: 2, width: badgeWidth, height: 9))
        }
        context.restoreGState()
    }
}
