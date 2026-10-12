import AppKit

/// Fish Stack's mark: two fish turning around a target inside a navy disk. Geometry is normalised so the
/// disk has radius 1 and y points down. The tail of each fish sits at the top of its arc and its head at the bottom.
enum FishMark {
    enum Style {
        /// Full colour, for the app icon and the popover header.
        case color
        /// Black disk with the fish and target cut out, for the menu bar. macOS tints it for the bar.
        case template
    }

    static let spine: CGFloat = 0.52
    static let halfWidth: CGFloat = 0.12
    /// The arc runs a little under half a turn, so the tail and the head of each fish sit off the centre line.
    private static let tailAngle: CGFloat = -.pi / 2 + 0.03
    private static let span: CGFloat = .pi - 0.33
    static let fishBlue = color(0x8FD3F7)
    static let fishWhite = color(0xEEF8FF)
    static let ink = color(0x0B1A2E)
    static let diskCenter = color(0x22497A)
    static let diskEdge = color(0x0B1A2E)

    static func color(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }

    static func transform(center: CGPoint, radius: CGFloat) -> CGAffineTransform {
        CGAffineTransform(a: radius, b: 0, c: 0, d: -radius, tx: center.x, ty: center.y)
    }

    /// Angle along the spine for s in 0...1, from the tail (0) over the outside to the head (1).
    private static func angle(_ s: CGFloat) -> CGFloat {
        tailAngle - s * span
    }

    /// Half the body width at s. It is zero at the tail tip and widest at the head.
    private static func width(_ s: CGFloat) -> CGFloat {
        halfWidth * pow(sin(.pi * s / 2), 0.75)
    }

    private static func point(_ s: CGFloat, radius: CGFloat, turned: Bool) -> CGPoint {
        let a = angle(s)
        let p = CGPoint(x: radius * cos(a), y: radius * sin(a))
        return turned ? CGPoint(x: -p.x, y: -p.y) : p
    }

    /// One fish, a crescent along the spine with a rounded head. `turned` gives the second fish, rotated half a turn.
    static func body(turned: Bool, _ transform: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        let steps = 96
        let caps = 24
        path.move(to: point(0, radius: spine, turned: turned), transform: transform)
        for i in 1...steps {
            let s = CGFloat(i) / CGFloat(steps)
            path.addLine(to: point(s, radius: spine + width(s), turned: turned), transform: transform)
        }
        // Round the head: a half circle from the outer edge, over the tip, to the inner edge.
        let a = angle(1)
        let normal = CGPoint(x: cos(a), y: sin(a))
        let forward = CGPoint(x: sin(a), y: -cos(a))
        let centre = CGPoint(x: spine * normal.x, y: spine * normal.y)
        let w = width(1)
        for k in 1..<caps {
            let theta = CGFloat(k) / CGFloat(caps) * .pi
            let p = CGPoint(
                x: centre.x + w * (cos(theta) * normal.x + sin(theta) * forward.x),
                y: centre.y + w * (cos(theta) * normal.y + sin(theta) * forward.y)
            )
            path.addLine(to: turned ? CGPoint(x: -p.x, y: -p.y) : p, transform: transform)
        }
        for i in stride(from: steps - 1, through: 0, by: -1) {
            let s = CGFloat(i) / CGFloat(steps)
            path.addLine(to: point(s, radius: spine - width(s), turned: turned), transform: transform)
        }
        path.closeSubpath()
        return path
    }

    static func eye(turned: Bool, _ transform: CGAffineTransform) -> CGPath {
        let s: CGFloat = 0.86
        let center = point(s, radius: spine + 0.35 * width(s), turned: turned)
        let r: CGFloat = 0.042
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2), transform: transform)
        return path
    }

    static func targetRing(_ transform: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: -0.24, y: -0.24, width: 0.48, height: 0.48), transform: transform)
        return path
    }

    static func targetDot(_ transform: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: -0.1, y: -0.1, width: 0.2, height: 0.2), transform: transform)
        return path
    }

    static func disk(_ transform: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        path.addEllipse(in: CGRect(x: -1, y: -1, width: 2, height: 2), transform: transform)
        return path
    }

    /// Paints the mark into `context`, centred on `center` with the disk's radius in points.
    static func draw(in context: CGContext, center: CGPoint, radius: CGFloat, style: Style) {
        let t = transform(center: center, radius: radius)
        context.saveGState()
        switch style {
        case .color:
            context.addPath(disk(t))
            context.clip()
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [diskCenter.cgColor, diskEdge.cgColor] as CFArray, locations: [0, 1]) {
                context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
            }
            context.setFillColor(fishBlue.cgColor)
            context.addPath(body(turned: false, t))
            context.fillPath()
            context.setFillColor(fishWhite.cgColor)
            context.addPath(body(turned: true, t))
            context.fillPath()
            context.setFillColor(ink.cgColor)
            context.addPath(eye(turned: false, t))
            context.addPath(eye(turned: true, t))
            context.fillPath()
            context.setStrokeColor(fishWhite.withAlphaComponent(0.45).cgColor)
            context.setLineWidth(0.035 * radius)
            context.addPath(targetRing(t))
            context.strokePath()
            context.setFillColor(fishWhite.withAlphaComponent(0.6).cgColor)
            context.addPath(targetDot(t))
            context.fillPath()
        case .template:
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(disk(t))
            context.fillPath()
            context.setBlendMode(.clear)
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(body(turned: false, t))
            context.addPath(body(turned: true, t))
            context.fillPath()
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(0.035 * radius)
            context.addPath(targetRing(t))
            context.strokePath()
            context.addPath(targetDot(t))
            context.fillPath()
            context.setBlendMode(.normal)
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(eye(turned: false, t))
            context.addPath(eye(turned: true, t))
            context.fillPath()
        }
        context.restoreGState()
    }

    /// The brand image for the popover header: the full mark in colour at `side` points.
    static func tile(side: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }
            draw(in: context, center: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width * 0.5, style: .color)
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

    /// `pulse` is 0...1 and only matters while loading, where the mark breathes.
    static func image(_ state: MarkState, pulse: CGFloat, attention: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else {
                return false
            }
            context.setAlpha(alpha(state, pulse: pulse))
            FishMark.draw(in: context, center: CGPoint(x: rect.midX, y: rect.midY), radius: 8.4, style: .template)
            context.setAlpha(1)
            if attention {
                let dot = CGRect(x: rect.maxX - 4.6, y: rect.maxY - 4.6, width: 3.6, height: 3.6)
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

/// Renders the app icon at any size from the same mark, on a light squircle plate.
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

    /// Light squircle plate with the navy disk and the fish at about 70% of its width, like the approved icon.
    static func draw(in context: CGContext, size: CGFloat) {
        let k = size / 1024
        let plate = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
        let path = CGPath(roundedRect: plate, cornerWidth: 186 * k, cornerHeight: 186 * k, transform: nil)
        context.saveGState()
        context.addPath(path)
        context.clip()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [FishMark.color(0xFBFBF9).cgColor, FishMark.color(0xE9E9E4).cgColor] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: plate.maxY), end: CGPoint(x: 0, y: plate.minY), options: [])
        }
        context.restoreGState()
        context.saveGState()
        context.addPath(path)
        context.setStrokeColor(NSColor(white: 0, alpha: 0.08).cgColor)
        context.setLineWidth(3 * k)
        context.strokePath()
        context.restoreGState()
        FishMark.draw(in: context, center: CGPoint(x: size / 2, y: size / 2), radius: 300 * k, style: .color)
    }
}
