import AppKit

/// Cached template images let macOS tint the keyboard and badge together for
/// light, dark, and highlighted menu bars. No drawing is done by the monitor.
@MainActor
enum MenuBarIcon {
    private static let unlocked = make(badge: "lock.open.fill")
    private static let locked = make(badge: "lock.fill")
    private static let paused = make(badge: "pause.fill")

    static func image(for status: LockStatus) -> NSImage {
        switch status {
        case .unlocked: unlocked
        case .locked: locked
        case .paused: paused
        }
    }

    private static func make(badge: String) -> NSImage {
        let size = IconArtwork.size
        let image = NSImage(size: size)
        let artwork = IconArtwork(badge: badge, color: .black)

        // Render once at standard and Retina resolutions. Both representations
        // have the same point size, so changing states never moves the menu item.
        for scale in [1, 2] {
            guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 21 * scale, pixelsHigh: 20 * scale,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }

            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
            artwork.draw(in: NSRect(origin: .zero, size: size))

            NSGraphicsContext.restoreGraphicsState()
            bitmap.size = size
            image.addRepresentation(bitmap)
        }
        image.isTemplate = true
        return image
    }
}
