// Generates every ZAP brand asset from one geometry definition: the approved graphite app icon with a slim
// vertical remote (circular D-pad, select button, microphone button, "…" button) and the monochrome mark.
//   branding/*.svg (vector sources), branding/zap-app-icon-512.png, Resources/AppIcon.icns
// The menu bar icon is drawn by the app itself (Sources/ZAP/MenuBarIcon.swift) so it can show states.
// Run from the repository root:  swift branding/make-assets.swift
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

// MARK: Geometry (1024 × 1024 icon canvas, origin bottom-left as in CoreGraphics)

struct Remote {
    static let body = CGRect(x: 340, y: 178, width: 344, height: 668)
    static let bodyRadius: CGFloat = 160
    static let pad = CGPoint(x: 512, y: 668)
    static let padRadius: CGFloat = 141
    static let selectRadius: CGFloat = 55
    static let arrowDistance: CGFloat = 101
    static let mic = CGPoint(x: 512, y: 436)
    static let dots = CGPoint(x: 512, y: 300)
    static let buttonRadius: CGFloat = 54
}
let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let tileRadius: CGFloat = 185

func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255, alpha: alpha)
}

func white(_ alpha: CGFloat) -> CGColor { CGColor(gray: 1, alpha: alpha) }
func black(_ alpha: CGFloat) -> CGColor { CGColor(gray: 0, alpha: alpha) }

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(gradient, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func circle(_ center: CGPoint, _ radius: CGFloat) -> CGRect {
    CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
}

/// Fills `path` with a vertical gradient.
func fill(_ ctx: CGContext, _ path: CGPath, top: CGColor, bottom: CGColor) {
    let box = path.boundingBoxOfPath
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    linear(ctx, [top, bottom], from: CGPoint(x: box.midX, y: box.maxY), to: CGPoint(x: box.midX, y: box.minY))
    ctx.restoreGState()
}

/// Strokes `path` with a gradient running from `from` to `to` (metallic rims, light edges).
func gradientStroke(_ ctx: CGContext, _ path: CGPath, width: CGFloat, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setLineWidth(width)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    linear(ctx, colors, from: from, to: to)
    ctx.restoreGState()
}

/// A small triangle pointing along `angle` (radians), centred `distance` from the D-pad centre.
func arrow(_ angle: CGFloat, distance: CGFloat, size: CGFloat) -> CGPath {
    let c = CGPoint(x: Remote.pad.x + distance * cos(angle), y: Remote.pad.y + distance * sin(angle))
    func p(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
        CGPoint(x: c.x + along * cos(angle) - across * sin(angle), y: c.y + along * sin(angle) + across * cos(angle))
    }
    let path = CGMutablePath()
    path.move(to: p(size * 0.45, 0))
    path.addLine(to: p(-size * 0.4, size * 0.55))
    path.addLine(to: p(-size * 0.4, -size * 0.55))
    path.closeSubpath()
    return path
}

/// Microphone glyph centred on `c`, `scale` 1 at full size.
func micGlyph(_ ctx: CGContext, center c: CGPoint, scale s: CGFloat, color: CGColor) {
    ctx.setFillColor(color)
    ctx.setStrokeColor(color)
    let head = CGRect(x: c.x - 11 * s, y: c.y - 2 * s, width: 22 * s, height: 36 * s)
    ctx.addPath(CGPath(roundedRect: head, cornerWidth: 11 * s, cornerHeight: 11 * s, transform: nil))
    ctx.fillPath()
    ctx.setLineWidth(4.5 * s)
    ctx.setLineCap(.round)
    ctx.addArc(center: CGPoint(x: c.x, y: c.y + 10 * s), radius: 19 * s, startAngle: .pi * 1.02, endAngle: .pi * 1.98,
               clockwise: false)
    ctx.strokePath()
    ctx.move(to: CGPoint(x: c.x, y: c.y - 9 * s))
    ctx.addLine(to: CGPoint(x: c.x, y: c.y - 19 * s))
    ctx.move(to: CGPoint(x: c.x - 10 * s, y: c.y - 19 * s))
    ctx.addLine(to: CGPoint(x: c.x + 10 * s, y: c.y - 19 * s))
    ctx.strokePath()
}

// MARK: Raster icon

/// `detail`: 2 = full (≥ 128 px), 1 = medium (32–64 px), 0 = minimal (16 px). Small sizes drop texture and
/// fine details and keep thicker shapes, so the remote still reads in Finder lists and the Dock.
func drawIcon(_ ctx: CGContext, detail: Int) {
    // Tile with its drop shadow.
    let tile = CGPath(roundedRect: tileRect, cornerWidth: tileRadius, cornerHeight: tileRadius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: black(0.45))
    ctx.addPath(tile)
    ctx.setFillColor(hex(0x202124))
    ctx.fillPath()
    ctx.restoreGState()
    fill(ctx, tile, top: hex(0x3C3D41), bottom: hex(0x17181B))
    // Soft light from the top-left, and a fine brushed texture.
    ctx.saveGState()
    ctx.addPath(tile)
    ctx.clip()
    let glow = CGGradient(colorsSpace: space, colors: [white(0.07), white(0)] as CFArray, locations: nil)!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 330, y: 860), startRadius: 0,
                           endCenter: CGPoint(x: 330, y: 860), endRadius: 700, options: [])
    if detail == 2 {
        var seed: UInt64 = 0x5A50
        func random() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
        }
        for _ in 0..<5200 {
            let x = tileRect.minX + random() * tileRect.width
            let y = tileRect.minY + random() * tileRect.height
            ctx.setFillColor(random() > 0.5 ? white(0.035 * random()) : black(0.06 * random()))
            ctx.fill(CGRect(x: x, y: y, width: 1.4, height: 1.4))
        }
    }
    ctx.restoreGState()
    gradientStroke(ctx, CGPath(roundedRect: tileRect.insetBy(dx: 1.5, dy: 1.5), cornerWidth: tileRadius - 1.5,
                               cornerHeight: tileRadius - 1.5, transform: nil),
                   width: 3, [white(0.2), white(0.05), black(0.25)],
                   from: CGPoint(x: 512, y: tileRect.maxY), to: CGPoint(x: 512, y: tileRect.minY))

    // Remote body with its shadow on the tile.
    let body = CGPath(roundedRect: Remote.body, cornerWidth: Remote.bodyRadius, cornerHeight: Remote.bodyRadius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: detail == 0 ? 20 : 46, color: black(0.62))
    ctx.addPath(body)
    ctx.setFillColor(hex(0x1C1D20))
    ctx.fillPath()
    ctx.restoreGState()
    fill(ctx, body, top: hex(0x313236), bottom: hex(0x151619))
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    linear(ctx, [white(0.06), white(0), black(0.12)], from: CGPoint(x: Remote.body.minX, y: 512),
           to: CGPoint(x: Remote.body.maxX, y: 512))
    ctx.restoreGState()
    // Silver rim: bright where the light comes from, darker at the bottom right.
    let rimWidth: CGFloat = detail == 0 ? 22 : (detail == 1 ? 14 : 9)
    gradientStroke(ctx, CGPath(roundedRect: Remote.body.insetBy(dx: rimWidth / 2, dy: rimWidth / 2),
                               cornerWidth: Remote.bodyRadius - rimWidth / 2, cornerHeight: Remote.bodyRadius - rimWidth / 2,
                               transform: nil),
                   width: rimWidth, [hex(0xECEDEF), hex(0xA4A6AB), hex(0x5D5F64), hex(0x3A3B3F)],
                   from: CGPoint(x: Remote.body.minX, y: Remote.body.maxY), to: CGPoint(x: Remote.body.maxX, y: Remote.body.minY))
    if detail > 0 {
        ctx.addPath(CGPath(roundedRect: Remote.body.insetBy(dx: rimWidth + 1.5, dy: rimWidth + 1.5),
                           cornerWidth: Remote.bodyRadius - rimWidth - 1.5, cornerHeight: Remote.bodyRadius - rimWidth - 1.5,
                           transform: nil))
        ctx.setStrokeColor(black(0.55))
        ctx.setLineWidth(2.5)
        ctx.strokePath()
    }

    // D-pad: a dark disc with four arrows and a raised select button.
    let pad = CGPath(ellipseIn: circle(Remote.pad, Remote.padRadius), transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 3), blur: 6, color: white(0.06))
    ctx.addPath(pad)
    ctx.setFillColor(hex(0x0E0F11))
    ctx.fillPath()
    ctx.restoreGState()
    fill(ctx, pad, top: hex(0x0B0C0E), bottom: hex(0x18191C))
    gradientStroke(ctx, pad, width: detail == 0 ? 6 : 3, [white(0.04), white(0.16)],
                   from: CGPoint(x: 512, y: Remote.pad.y + Remote.padRadius), to: CGPoint(x: 512, y: Remote.pad.y - Remote.padRadius))
    if detail > 0 {
        ctx.setFillColor(white(0.9))
        for angle in [CGFloat.pi / 2, -.pi / 2, .pi, 0] {
            ctx.addPath(arrow(angle, distance: Remote.arrowDistance, size: detail == 1 ? 40 : 30))
            ctx.fillPath()
        }
    }
    let select = CGPath(ellipseIn: circle(Remote.pad, Remote.selectRadius), transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -7), blur: 14, color: black(0.7))
    ctx.addPath(select)
    ctx.setFillColor(hex(0x26272B))
    ctx.fillPath()
    ctx.restoreGState()
    fill(ctx, select, top: hex(0x3A3B40), bottom: hex(0x1D1E22))
    gradientStroke(ctx, select, width: 2.5, [white(0.28), white(0.02)],
                   from: CGPoint(x: 512, y: Remote.pad.y + Remote.selectRadius), to: CGPoint(x: 512, y: Remote.pad.y - Remote.selectRadius))

    // Microphone and "…" buttons.
    for center in [Remote.mic, Remote.dots] {
        let button = CGPath(ellipseIn: circle(center, Remote.buttonRadius), transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 12, color: black(0.65))
        ctx.addPath(button)
        ctx.setFillColor(hex(0x141518))
        ctx.fillPath()
        ctx.restoreGState()
        fill(ctx, button, top: hex(0x222327), bottom: hex(0x101113))
        gradientStroke(ctx, button, width: detail == 0 ? 5 : 2.5, [white(0.22), white(0.03)],
                       from: CGPoint(x: center.x, y: center.y + Remote.buttonRadius),
                       to: CGPoint(x: center.x, y: center.y - Remote.buttonRadius))
    }
    if detail == 0 {
        // 16 px: the buttons become light dots, or they vanish into the body.
        ctx.setFillColor(hex(0x9C9EA3))
        ctx.fillEllipse(in: circle(Remote.pad, Remote.selectRadius + 6))
        ctx.setFillColor(hex(0x7C7E83))
        ctx.fillEllipse(in: circle(Remote.mic, Remote.buttonRadius))
        ctx.fillEllipse(in: circle(Remote.dots, Remote.buttonRadius))
    }
    if detail > 0 {
        micGlyph(ctx, center: Remote.mic, scale: detail == 1 ? 1.25 : 1, color: white(0.9))
        ctx.setFillColor(white(0.88))
        let dot: CGFloat = detail == 1 ? 9 : 6.5
        for dx in [-22.0, 0, 22.0] as [CGFloat] {
            ctx.fillEllipse(in: circle(CGPoint(x: Remote.dots.x + dx * (detail == 1 ? 1.15 : 1), y: Remote.dots.y), dot))
        }
    }
}

func png(size: Int, _ draw: (CGContext) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.interpolationQuality = .high
    draw(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func appIcon(_ px: Int) -> Data {
    png(size: px) { ctx in
        let k = CGFloat(px) / 1024
        ctx.scaleBy(x: k, y: k)
        drawIcon(ctx, detail: px >= 128 ? 2 : (px >= 32 ? 1 : 0))
    }
}

func writeText(_ text: String, _ path: String) {
    let url = root.appendingPathComponent(path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! text.write(to: url, atomically: true, encoding: .utf8)
    print("wrote \(path)")
}

// MARK: SVG sources (top-left origin: y = 1024 - y)

func f(_ v: CGFloat) -> String { String(format: "%.1f", Double(v)) }
func sy(_ y: CGFloat) -> CGFloat { 1024 - y }

func svgArrow(_ angle: CGFloat) -> String {
    let path = arrow(angle, distance: Remote.arrowDistance, size: 30)
    var points: [String] = []
    path.applyWithBlock { element in
        let e = element.pointee
        if e.type == .moveToPoint || e.type == .addLineToPoint { points.append("\(f(e.points[0].x)),\(f(sy(e.points[0].y)))") }
    }
    return "<polygon points=\"\(points.joined(separator: " "))\" fill=\"#E6E6E6\"/>"
}

let b = Remote.body
writeText("""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>
<linearGradient id="tile" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3C3D41"/><stop offset="1" stop-color="#17181B"/></linearGradient>
<linearGradient id="body" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#313236"/><stop offset="1" stop-color="#151619"/></linearGradient>
<linearGradient id="rim" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#ECEDEF"/><stop offset="0.35" stop-color="#A4A6AB"/><stop offset="0.7" stop-color="#5D5F64"/><stop offset="1" stop-color="#3A3B3F"/></linearGradient>
<linearGradient id="pad" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0B0C0E"/><stop offset="1" stop-color="#18191C"/></linearGradient>
<linearGradient id="key" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#3A3B40"/><stop offset="1" stop-color="#1D1E22"/></linearGradient>
<linearGradient id="button" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#222327"/><stop offset="1" stop-color="#101113"/></linearGradient>
<filter id="shadow" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="22" stdDeviation="22" flood-color="#000" flood-opacity="0.6"/></filter>
</defs>
<rect x="\(f(tileRect.minX))" y="\(f(tileRect.minY))" width="\(f(tileRect.width))" height="\(f(tileRect.height))" rx="\(f(tileRadius))" fill="url(#tile)"/>
<rect x="\(f(tileRect.minX + 1.5))" y="\(f(tileRect.minY + 1.5))" width="\(f(tileRect.width - 3))" height="\(f(tileRect.height - 3))" rx="\(f(tileRadius - 1.5))" fill="none" stroke="#FFFFFF" stroke-opacity="0.12" stroke-width="3"/>
<rect x="\(f(b.minX))" y="\(f(sy(b.maxY)))" width="\(f(b.width))" height="\(f(b.height))" rx="\(f(Remote.bodyRadius))" fill="url(#body)" filter="url(#shadow)"/>
<rect x="\(f(b.minX + 4.5))" y="\(f(sy(b.maxY) + 4.5))" width="\(f(b.width - 9))" height="\(f(b.height - 9))" rx="\(f(Remote.bodyRadius - 4.5))" fill="none" stroke="url(#rim)" stroke-width="9"/>
<circle cx="512" cy="\(f(sy(Remote.pad.y)))" r="\(f(Remote.padRadius))" fill="url(#pad)" stroke="#FFFFFF" stroke-opacity="0.1" stroke-width="3"/>
\(svgArrow(.pi / 2))
\(svgArrow(-.pi / 2))
\(svgArrow(.pi))
\(svgArrow(0))
<circle cx="512" cy="\(f(sy(Remote.pad.y)))" r="\(f(Remote.selectRadius))" fill="url(#key)" stroke="#FFFFFF" stroke-opacity="0.18" stroke-width="2.5"/>
<circle cx="512" cy="\(f(sy(Remote.mic.y)))" r="\(f(Remote.buttonRadius))" fill="url(#button)" stroke="#FFFFFF" stroke-opacity="0.14" stroke-width="2.5"/>
<rect x="501" y="\(f(sy(Remote.mic.y) - 34))" width="22" height="36" rx="11" fill="#E6E6E6"/>
<path d="M493,\(f(sy(Remote.mic.y) - 10)) a19,19 0 0 0 38,0 M512,\(f(sy(Remote.mic.y) + 9)) v10 M502,\(f(sy(Remote.mic.y) + 19)) h20" fill="none" stroke="#E6E6E6" stroke-width="4.5" stroke-linecap="round"/>
<circle cx="512" cy="\(f(sy(Remote.dots.y)))" r="\(f(Remote.buttonRadius))" fill="url(#button)" stroke="#FFFFFF" stroke-opacity="0.14" stroke-width="2.5"/>
<g fill="#E0E0E0"><circle cx="490" cy="\(f(sy(Remote.dots.y)))" r="6.5"/><circle cx="512" cy="\(f(sy(Remote.dots.y)))" r="6.5"/><circle cx="534" cy="\(f(sy(Remote.dots.y)))" r="6.5"/></g>
</svg>
""", "branding/zap-app-icon.svg")

/// The monochrome mark (same silhouette as the menu bar icon), on a 100 × 100 grid.
func markSVG(_ color: String, x: CGFloat = 0, y: CGFloat = 0, scale: CGFloat = 1) -> String {
    """
    <g transform="translate(\(f(x)) \(f(y))) scale(\(String(format: "%.3f", Double(scale))))" fill="none" stroke="\(color)">
    <rect x="27.2" y="5" width="45.6" height="90" rx="21.7" stroke-width="6.9"/>
    <circle cx="50" cy="31.9" r="12.8" stroke-width="5.8"/>
    <circle cx="50" cy="31.9" r="4.7" fill="\(color)" stroke="none"/>
    <circle cx="50" cy="62.2" r="5.3" fill="\(color)" stroke="none"/>
    <circle cx="50" cy="82.2" r="4.4" fill="\(color)" stroke="none"/>
    </g>
    """
}

writeText("""
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100" width="100" height="100">
\(markSVG("#F2F2F0"))
</svg>
""", "branding/zap-mark.svg")

func wordmark(_ color: String) -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 100" width="300" height="100">
    \(markSVG(color, x: 0, y: 10, scale: 0.8))
    <g fill="none" stroke="\(color)" stroke-width="7" stroke-linecap="round" stroke-linejoin="round">
    <polyline points="104,31 146,31 104,69 146,69"/>
    <polyline points="168,69 194,31 220,69"/>
    <line x1="179" y1="55" x2="209" y2="55"/>
    <path d="M244,69 V31 H266 A15,15 0 0 1 266,61 H244"/>
    </g>
    </svg>
    """
}
writeText(wordmark("#F2F2F0"), "branding/zap-wordmark-on-dark.svg")
writeText(wordmark("#15161B"), "branding/zap-wordmark-on-light.svg")

// MARK: App icon (.icns) and a 512 px preview

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ZAP.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! appIcon(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! appIcon(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
precondition(iconutil.terminationStatus == 0, "iconutil failed")
print("wrote Resources/AppIcon.icns")
try! appIcon(512).write(to: root.appendingPathComponent("branding/zap-app-icon-512.png"))
print("wrote branding/zap-app-icon-512.png")
