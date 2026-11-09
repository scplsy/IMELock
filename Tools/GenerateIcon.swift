import AppKit

@main
@MainActor
struct GenerateIcon {
    static func main() throws {
        let output = URL(fileURLWithPath: "IMELock/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
        let variants = [(16, "16"), (32, "16@2x"), (32, "32"), (64, "32@2x"),
                        (128, "128"), (256, "128@2x"), (256, "256"), (512, "256@2x"),
                        (512, "512"), (1024, "512@2x")]
        let ink = NSColor(srgbRed: 0.075, green: 0.13, blue: 0.18, alpha: 1)
        let mint = NSColor(srgbRed: 0.64, green: 0.92, blue: 0.79, alpha: 1)
        let artwork = IconArtwork(badge: "lock.fill", color: mint)

        for (size, name) in variants {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

            ink.setFill()
            NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 188, yRadius: 188).fill()
            // Keep the badge cutout inside the artwork layer so the app icon's
            // background remains solid, matching the menu bar's transparent gap.
            context.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
            artwork.draw(in: NSRect(x: 144, y: 162, width: 736, height: 736 * 20 / 21))
            context.cgContext.endTransparencyLayer()

            NSGraphicsContext.restoreGraphicsState()
            try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(name).png"))
        }
    }
}
