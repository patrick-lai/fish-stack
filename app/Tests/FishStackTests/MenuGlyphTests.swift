import AppKit
import XCTest
@testable import FishStack

/// Writes the menu-bar glyph in each state to a folder when FISH_STACK_GLYPHS is set, so the template art can be checked by eye.
final class MenuGlyphTests: XCTestCase {
    func testWritesTheGlyphStatesWhenAsked() throws {
        guard let folder = ProcessInfo.processInfo.environment["FISH_STACK_GLYPHS"] else {
            throw XCTSkip("Set FISH_STACK_GLYPHS to a folder to write the menu-bar glyph states.")
        }
        let directory = URL(fileURLWithPath: folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let states: [(String, MarkState, CGFloat, Bool)] = [
            ("serving", .serving, 1, false),
            ("loading", .loading, 0.2, false),
            ("offline", .offline, 1, true),
        ]
        for (name, state, pulse, attention) in states {
            let image = MenuGlyph.image(state, pulse: pulse, attention: attention)
            XCTAssertTrue(image.isTemplate)
            let pixels = 36
            let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            NSColor(white: 0.93, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
            image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
            NSGraphicsContext.restoreGraphicsState()
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("glyph-\(name).png"))
        }
    }
}
