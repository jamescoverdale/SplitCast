// Draws the Splitcast app icon (1024×1024 PNGs for the light, dark and tinted slots).
// Run from the repo root:
//   swiftc -O tools/make_splitcast_icon.swift -o "$TMPDIR/make_splitcast_icon" \
//     && "$TMPDIR/make_splitcast_icon" Splitcast/Assets.xcassets/AppIcon.appiconset
// Two race bibs: an orange one behind (you then) and a white one in front (you now), with
// THEN / NOW on the front bib's strip.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size: CGFloat = 1024
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

enum Variant: String, CaseIterable {
    case light = "AppIcon"
    case dark = "AppIcon-dark"
    case tinted = "AppIcon-tinted"
}

func hex(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: sRGB, components: [CGFloat((h >> 16) & 255) / 255, CGFloat((h >> 8) & 255) / 255, CGFloat(h & 255) / 255, a])!
}

func grey(_ w: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(colorSpace: sRGB, components: [w, w, w, a])! }

struct Palette {
    var backgroundTop: CGColor?
    var backgroundBottom: CGColor?
    var backBib: CGColor
    var frontBib: CGColor
    var ink: CGColor
    var then: CGColor
    var now: CGColor
    var label: CGColor
    var shadow: CGFloat

    static func of(_ v: Variant) -> Palette {
        switch v {
        case .light:
            Palette(backgroundTop: hex(0x1FC8E0), backgroundBottom: hex(0x2F5BFF), backBib: hex(0xFF6B1A), frontBib: grey(1),
                    ink: hex(0x14213D), then: hex(0xFF6B1A), now: hex(0x2F7BFF), label: grey(1), shadow: 0.28)
        case .dark:
            // Transparent: iOS draws its own dark backdrop behind dark-mode icons.
            Palette(backgroundTop: nil, backgroundBottom: nil, backBib: hex(0xF2702A), frontBib: hex(0xE8ECF2),
                    ink: hex(0x14213D), then: hex(0xF2702A), now: hex(0x3D86FF), label: grey(1), shadow: 0.45)
        case .tinted:
            // Greyscale on transparent: iOS colours it with the user's tint.
            Palette(backgroundTop: nil, backgroundBottom: nil, backBib: grey(1, 0.45), frontBib: grey(1),
                    ink: grey(0.15), then: grey(0.55), now: grey(0.35), label: grey(1), shadow: 0)
        }
    }
}

/// Text as a path centred on the origin, so it can be placed and filled like any shape.
func textPath(_ text: String, size: CGFloat, weight: CGFloat, kern: CGFloat = 0) -> CGPath {
    let base = CTFontCreateUIFontForLanguage(.system, size, nil)!
    let descriptor = CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(base),
        [kCTFontTraitsAttribute: [kCTFontWeightTrait: weight]] as CFDictionary)
    let font = CTFontCreateWithFontDescriptor(descriptor, size, nil)
    let attributes = [NSAttributedString.Key(kCTFontAttributeName as String): font,
                      NSAttributedString.Key(kCTKernAttributeName as String): kern] as [NSAttributedString.Key: Any]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    let out = CGMutablePath()
    for run in CTLineGetGlyphRuns(line) as! [CTRun] {
        let n = CTRunGetGlyphCount(run)
        var glyphs = [CGGlyph](repeating: 0, count: n)
        var positions = [CGPoint](repeating: .zero, count: n)
        CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: n), &positions)
        for i in 0..<n {
            if let g = CTFontCreatePathForGlyph(font, glyphs[i], nil) {
                out.addPath(g, transform: CGAffineTransform(translationX: positions[i].x, y: positions[i].y))
            }
        }
    }
    let box = out.boundingBoxOfPath
    return out.copy(using: [CGAffineTransform(translationX: -box.midX, y: -box.midY)])!
}

func drawText(_ ctx: CGContext, _ text: String, at p: CGPoint, size: CGFloat, weight: CGFloat, kern: CGFloat = 0, color: CGColor) {
    ctx.setFillColor(color)
    ctx.addPath(textPath(text, size: size, weight: weight, kern: kern).copy(using: [CGAffineTransform(translationX: p.x, y: p.y)])!)
    ctx.fillPath()
}

/// A bib of 600×470 points centred on `center`, rotated by `angle`; `content` draws in its frame.
func drawBib(_ ctx: CGContext, center: CGPoint, angle: CGFloat, paper: CGColor, shadow: CGFloat,
             content: (CGContext, CGRect) -> Void = { _, _ in }) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle)
    let r = CGRect(x: -300, y: -235, width: 600, height: 470)
    let shape = CGPath(roundedRect: r, cornerWidth: 34, cornerHeight: 34, transform: nil)
    ctx.saveGState()
    if shadow > 0 { ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: grey(0, shadow)) }
    ctx.setFillColor(paper)
    ctx.addPath(shape)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(shape)
    ctx.clip()
    content(ctx, r)
    ctx.restoreGState()
}

func draw(_ variant: Variant) -> CGImage {
    // The main icon must be opaque; dark and tinted need transparency.
    let alpha: CGImageAlphaInfo = variant == .light ? .noneSkipLast : .premultipliedLast
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: sRGB, bitmapInfo: alpha.rawValue)!
    let p = Palette.of(variant)
    if let top = p.backgroundTop, let bottom = p.backgroundBottom {
        let gradient = CGGradient(colorsSpace: sRGB, colors: [top, bottom] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
    } else {
        ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
    }

    // You then: behind and to the left.
    drawBib(ctx, center: CGPoint(x: 450, y: 560), angle: 0.16, paper: p.backBib, shadow: p.shadow)

    // You now: in front, with the name, a big S and the THEN / NOW strip.
    drawBib(ctx, center: CGPoint(x: 575, y: 455), angle: -0.08, paper: p.frontBib, shadow: p.shadow) { ctx, r in
        let strip: CGFloat = 84
        for (i, (label, colour)) in [("THEN", p.then), ("NOW", p.now)].enumerated() {
            let cell = CGRect(x: r.minX + CGFloat(i) * r.width / 2, y: r.minY, width: r.width / 2 + 1, height: strip)
            ctx.setFillColor(colour)
            ctx.fill(cell)
            drawText(ctx, label, at: CGPoint(x: cell.midX, y: cell.midY), size: 40, weight: 0.55, kern: 6, color: p.label)
        }
        let body = CGRect(x: r.minX, y: r.minY + strip, width: r.width, height: r.height - strip)
        drawText(ctx, "SPLITCAST", at: CGPoint(x: body.midX, y: body.maxY - 58), size: 44, weight: 0.5, kern: 8, color: p.ink)
        drawText(ctx, "S", at: CGPoint(x: body.midX, y: body.midY - 26), size: 250, weight: 0.62, color: p.ink)
    }
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
}

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
for variant in Variant.allCases {
    let url = outDir.appendingPathComponent("\(variant.rawValue).png")
    writePNG(draw(variant), to: url)
    print("wrote \(url.path)")
}

// App icons can't be shown inside the app, so the About screen gets its own copy.
let aboutDir = outDir.deletingLastPathComponent().appendingPathComponent("AboutIcon.imageset")
if FileManager.default.fileExists(atPath: aboutDir.path) {
    let url = aboutDir.appendingPathComponent("AboutIcon.png")
    writePNG(draw(.light), to: url)
    print("wrote \(url.path)")
}
