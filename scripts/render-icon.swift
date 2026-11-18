// Renders the Icon Composer layers for the Caution Flag app icon.
// Usage: swift scripts/render-icon.swift
// Source of truth for the geometry: assets/icon/caution-flag.svg (1024 grid,
// y down). Layers are full-bleed and unmasked; macOS applies the squircle and
// Liquid Glass. Re-run after changing the geometry, then rebuild.
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let out = root.appendingPathComponent("assets/icon/AppIcon.icon/Assets")
let caution = NSColor(srgbRed: 0xF5 / 255, green: 0xC5 / 255, blue: 0x42 / 255, alpha: 1)
let asphalt = NSColor(srgbRed: 0x1F / 255, green: 0x2A / 255, blue: 0x36 / 255, alpha: 1)

func render(_ name: String, _ draw: (CGContext) -> Void) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    // Match the SVG's y-down coordinates.
    cg.translateBy(x: 0, y: 1024)
    cg.scaleBy(x: 1, y: -1)
    draw(cg)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

try render("icon-backing.png") { cg in
    cg.setFillColor(caution.cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
}

try render("icon-mark.png") { cg in
    cg.setFillColor(asphalt.cgColor)
    cg.setStrokeColor(asphalt.cgColor)
    // Pole.
    cg.addPath(CGPath(roundedRect: CGRect(x: 258, y: 182, width: 52, height: 660),
                      cornerWidth: 26, cornerHeight: 26, transform: nil))
    cg.fillPath()
    // Pennant: filled triangle, stroked with round joins to soften the corners.
    let pennant = CGMutablePath()
    pennant.move(to: CGPoint(x: 310, y: 236))
    pennant.addLine(to: CGPoint(x: 746, y: 370))
    pennant.addLine(to: CGPoint(x: 310, y: 504))
    pennant.closeSubpath()
    cg.addPath(pennant)
    cg.setLineWidth(40)
    cg.setLineJoin(.round)
    cg.drawPath(using: .fillStroke)
}
print("Wrote layers to \(out.path)")
