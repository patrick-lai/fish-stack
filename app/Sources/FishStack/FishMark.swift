import AppKit

/// Fish Stack's mark. A fish sits inside the same ring as CommissionAI's compass emblem, so the two
/// apps read as one family. Geometry is in design units with y pointing down and the nose toward +x.
enum FishMark {
    struct Palette {
        let body: NSColor
        let fin: NSColor
    }

    static let dark = Palette(body: color(0xECE8DF), fin: color(0x6FA8F7))
    static let mono = Palette(body: .black, fin: .black)

    static let ringRadius: CGFloat = 270
    static let ringWeight: CGFloat = 34
    /// Design-space bounds of the whole fish, tail to dorsal fin. Used to centre the menu-bar glyph.
    static let bounds = CGRect(x: -215, y: -190, width: 415, height: 305)

    static func color(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }

    static func canvas(center: CGPoint, scale: CGFloat) -> CGAffineTransform {
        CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: center.x, ty: center.y)
    }

    static func body(_ transform: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 200, y: 0), transform: transform)
        path.addCurve(to: CGPoint(x: -120, y: -36), control1: CGPoint(x: 150, y: -130), control2: CGPoint(x: -10, y: -140), transform: transform)
        path.addLine(to: CGPoint(x: -120, y: 36), transform: transform)
        path.addCurve(to: CGPoint(x: 200, y: 0), control1: CGPoint(x: -10, y: 140), control2: CGPoint(x: 150, y: 130), transform: transform)
        path.closeSubpath()
        return path
    }

    static func tail(_ transform: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -100, y: -34), transform: transform)
        path.addLine(to: CGPoint(x: -215, y: -108), transform: transform)
        path.addQuadCurve(to: CGPoint(x: -215, y: 108), control: CGPoint(x: -168, y: 0), transform: transform)
        path.addLine(to: CGPoint(x: -100, y: 34), transform: transform)
        path.closeSubpath()
        return path
    }

    static func dorsal(_ transform: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 55, y: -104), transform: transform)
        path.addQuadCurve(to: CGPoint(x: -35, y: -178), control: CGPoint(x: 20, y: -200), transform: transform)
        path.addQuadCurve(to: CGPoint(x: -48, y: -106), control: CGPoint(x: -22, y: -140), transform: transform)
        path.closeSubpath()
        return path
    }

    static func eye(_ transform: CGAffineTransform, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: 128 - radius, y: -18 - radius, width: radius * 2, height: radius * 2), transform: transform)
        return path
    }

    static func gill(_ transform: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 62, y: -72), transform: transform)
        path.addQuadCurve(to: CGPoint(x: 62, y: 72), control: CGPoint(x: 40, y: 0), transform: transform)
        return path
    }

    static func ring(_ transform: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        for radius in [ringRadius + ringWeight / 2, ringRadius - ringWeight / 2] {
            path.addEllipse(in: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: transform)
        }
        return path
    }

    /// Paints the fish onto a transparent canvas. `detailed` adds the gill line and the ring; the
    /// menu-bar glyph leaves both out because they turn to mud below about 18 points.
    static func draw(in context: CGContext, center: CGPoint, scale: CGFloat, palette: Palette, detailed: Bool) {
        let transform = canvas(center: center, scale: scale)
        context.saveGState()
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        if detailed {
            context.setFillColor(palette.body.cgColor)
            context.addPath(ring(transform))
            context.fillPath(using: .evenOdd)
        }
        // Fins go under the body so their bases tuck in and the join reads as one silhouette.
        context.setFillColor(palette.fin.cgColor)
        context.addPath(tail(transform))
        context.addPath(dorsal(transform))
        context.fillPath()
        context.setFillColor(palette.body.cgColor)
        context.addPath(body(transform))
        context.fillPath()
        context.setBlendMode(.clear)
        context.setFillColor(NSColor.black.cgColor)
        context.addPath(eye(transform, radius: detailed ? 17 : 26))
        context.fillPath()
        if detailed {
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(9 * scale)
            context.setLineCap(.round)
            context.addPath(gill(transform))
            context.strokePath()
        }
        context.setBlendMode(.normal)
        context.endTransparencyLayer()
        context.restoreGState()
    }

    /// The brand tile image: the full mark with its ring, in colour, for the popover header.
    static func tile(side: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }
            draw(in: context, center: CGPoint(x: rect.midX, y: rect.midY), scale: rect.width * 1.1 / 1024, palette: dark, detailed: true)
            return true
        }
    }
}

/// What the menu-bar glyph should say about the server at a glance.
enum MarkState: Equatable {
    case serving
    case loading
    case offline
}

/// Menu-bar template images. They are monochrome, so macOS can tint them for light and dark bars.
enum MenuGlyph {
    static let side: CGFloat = 18

    /// `pulse` is 0...1 and only matters while loading, where the fish breathes.
    static func image(_ state: MarkState, pulse: CGFloat, attention: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }
            let bounds = FishMark.bounds
            let scale = min(rect.width * 0.94 / bounds.width, rect.height * 0.8 / bounds.height)
            let center = CGPoint(x: rect.midX - scale * bounds.midX, y: rect.midY + scale * bounds.midY)
            context.setAlpha(alpha(state, pulse: pulse))
            FishMark.draw(in: context, center: center, scale: scale, palette: FishMark.mono, detailed: false)
            context.setAlpha(1)
            if attention {
                let dot = CGRect(x: rect.maxX - 5.9, y: rect.maxY - 5.9, width: 3.8, height: 3.8)
                context.setBlendMode(.clear)
                context.fillEllipse(in: dot.insetBy(dx: -1.1, dy: -1.1))
                context.setBlendMode(.normal)
                context.setFillColor(NSColor.black.cgColor)
                context.fillEllipse(in: dot)
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func alpha(_ state: MarkState, pulse: CGFloat) -> CGFloat {
        switch state {
        case .serving: 1
        case .loading: 0.35 + 0.65 * pulse
        case .offline: 0.4
        }
    }
}

/// Renders the app icon at any size from the same geometry as the menu-bar glyph and the header tile.
enum AppIconArt {
    static let sizes: [(name: String, pixels: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]

    static func writeIconset(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for entry in sizes {
            let rep = try makeRep(entry.pixels)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                throw FishError("Could not encode \(entry.name).")
            }
            try png.write(to: directory.appendingPathComponent(entry.name + ".png"))
        }
    }

    private static func makeRep(_ pixels: Int) throws -> NSBitmapImageRep {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
            throw FishError("Could not allocate a \(pixels) pixel icon.")
        }
        guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else {
            throw FishError("Could not open an icon canvas.")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        defer { NSGraphicsContext.restoreGraphicsState() }
        draw(in: graphics.cgContext, size: CGFloat(pixels))
        return rep
    }

    /// Squircle in deep sea teal, the fish mark inside its ring. Coordinates scale with `size`.
    static func draw(in context: CGContext, size: CGFloat) {
        let k = size / 1024
        let plate = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
        let path = CGPath(roundedRect: plate, cornerWidth: 186 * k, cornerHeight: 186 * k, transform: nil)
        context.saveGState()
        context.addPath(path)
        context.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [FishMark.color(0x1E4657).cgColor, FishMark.color(0x0A1822).cgColor] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: plate.maxY), end: CGPoint(x: 0, y: plate.minY), options: [])
        context.restoreGState()
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(NSColor(white: 1, alpha: 0.1).cgColor)
        context.setLineWidth(3 * k)
        context.strokePath()
        context.restoreGState()
        FishMark.draw(in: context, center: CGPoint(x: size / 2, y: size / 2), scale: 1.12 * k, palette: FishMark.dark, detailed: true)
    }
}
