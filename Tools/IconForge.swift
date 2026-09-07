#!/usr/bin/env swift
// Renders every piece of bitmap art the app ships: the layered tvOS app icon,
// the App Store icon, both top shelf images and the launch image. Run with:
//   xcrun swift Tools/IconForge.swift <output-directory>
// Keeping this in the repo means the art can be regenerated after a brand tweak
// instead of being an opaque binary.

import AppKit
import CoreGraphics
import CoreText
import Foundation

// MARK: - Palette (mirrors Sources/Core/Theme.swift)

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

let cyan = rgb(0x24E5FF)
let magenta = rgb(0xFF3DC5)
let gold = rgb(0xFFD65C)
let deep = rgb(0x04060F)
let deeper = rgb(0x01020A)
let gridLine = rgb(0x1B2E52)
let gridBright = rgb(0x2C4B84)

// MARK: - Drawing helpers

/// Radial glow centred on `point`.
func glow(_ ctx: CGContext, at point: CGPoint, radius: CGFloat, color: CGColor, intensity: CGFloat = 1) {
    let space = CGColorSpaceCreateDeviceRGB()
    var colors: [CGColor] = []
    var stops: [CGFloat] = []
    let steps = 32
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps)
        let alpha = pow(1 - t, 2.2) * intensity
        colors.append(color.copy(alpha: alpha) ?? color)
        stops.append(t)
    }
    guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: stops)
    else { return }
    ctx.saveGState()
    ctx.setBlendMode(.plusLighter)
    ctx.drawRadialGradient(gradient, startCenter: point, startRadius: 0,
                           endCenter: point, endRadius: radius, options: [])
    ctx.restoreGState()
}

/// Filled shape with a neon bloom around it.
func neonFill(_ ctx: CGContext, path: CGPath, color: CGColor, bloom: CGFloat) {
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: bloom, color: color.copy(alpha: 0.95))
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
    ctx.restoreGState()
    // Second pass tightens the core so it reads as light, not a blurry blob.
    ctx.saveGState()
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
    ctx.setShadow(offset: .zero, blur: bloom * 0.35, color: color)
    ctx.fillPath()
    ctx.restoreGState()
}

func capsulePath(_ rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: min(rect.width, rect.height) / 2,
           cornerHeight: min(rect.width, rect.height) / 2, transform: nil)
}

/// Draws tracked, glowing text centred on `center`. Returns the drawn width.
@discardableResult
func neonText(_ ctx: CGContext, _ string: String, center: CGPoint, size: CGFloat,
              color: CGColor, tracking: CGFloat, bloom: CGFloat,
              align: Int = 0) -> CGFloat {
    let font = NSFont.systemFont(ofSize: size, weight: .black)
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(cgColor: color) ?? .white,
        .kern: tracking
    ]
    let attributed = NSAttributedString(string: string, attributes: attributes)
    let line = CTLineCreateWithAttributedString(attributed)
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

    let originX: CGFloat
    switch align {
    case -1: originX = center.x                       // left
    case 1:  originX = center.x - bounds.width        // right
    default: originX = center.x - bounds.width / 2    // centred
    }
    let originY = center.y - bounds.height / 2 - bounds.origin.y

    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: bloom, color: color.copy(alpha: 0.9))
    ctx.textPosition = CGPoint(x: originX, y: originY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()

    // Crisp pass on top of the bloom.
    ctx.saveGState()
    ctx.textPosition = CGPoint(x: originX, y: originY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()

    return bounds.width
}

func render(size: CGSize, opaque: Bool, _ body: (CGContext, CGSize) -> Void) -> Data {
    let width = Int(size.width)
    let height = Int(size.height)
    guard let ctx = CGContext(data: nil, width: width, height: height,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("could not create context") }
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    if opaque {
        ctx.setFillColor(deeper)
        ctx.fill(CGRect(origin: .zero, size: size))
    }
    body(ctx, size)
    guard let image = ctx.makeImage() else { fatalError("could not render image") }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("could not encode png")
    }
    return data
}

// MARK: - Composition

enum Layer {
    case back, middle, front, flat
}

/// One composition, drawn at any size. `u` is the unit scale so every dimension
/// is expressed relative to the canvas width.
func drawComposition(_ ctx: CGContext, size: CGSize, layer: Layer, showWordmark: Bool) {
    let w = size.width
    let h = size.height
    let u = w / 1000.0

    let drawBack = layer == .back || layer == .flat
    let drawMiddle = layer == .middle || layer == .flat
    let drawFront = layer == .front || layer == .flat

    if drawBack {
        // Base gradient: lifted in the middle, crushed at the edges.
        let space = CGColorSpaceCreateDeviceRGB()
        if let gradient = CGGradient(colorsSpace: space,
                                     colors: [rgb(0x0B1430), deep, deeper] as CFArray,
                                     locations: [0, 0.55, 1]) {
            ctx.drawRadialGradient(gradient,
                                   startCenter: CGPoint(x: w / 2, y: h / 2), startRadius: 0,
                                   endCenter: CGPoint(x: w / 2, y: h / 2), endRadius: w * 0.72,
                                   options: [.drawsAfterEndLocation])
        }

        // Field grid.
        ctx.saveGState()
        ctx.setLineWidth(max(1, 1.6 * u))
        ctx.setStrokeColor(gridLine.copy(alpha: 0.55) ?? gridLine)
        let columns = 14
        for i in 0...columns {
            let x = w * CGFloat(i) / CGFloat(columns)
            ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: h))
        }
        let rows = max(4, Int(8 * h / (w * 0.6)))
        for i in 0...rows {
            let y = h * CGFloat(i) / CGFloat(rows)
            ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: w, y: y))
        }
        ctx.strokePath()
        ctx.restoreGState()

        // Goal washes at both edges.
        glow(ctx, at: CGPoint(x: 0, y: h / 2), radius: w * 0.42, color: cyan, intensity: 0.42)
        glow(ctx, at: CGPoint(x: w, y: h / 2), radius: w * 0.42, color: magenta, intensity: 0.42)

        // Vignette.
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [CGColor(gray: 0, alpha: 0),
                                              CGColor(gray: 0, alpha: 0.75)] as CFArray,
                                     locations: [0.45, 1]) {
            ctx.drawRadialGradient(gradient,
                                   startCenter: CGPoint(x: w / 2, y: h / 2), startRadius: 0,
                                   endCenter: CGPoint(x: w / 2, y: h / 2), endRadius: w * 0.68,
                                   options: [.drawsAfterEndLocation])
        }
    }

    if drawMiddle {
        // Dashed centre net.
        ctx.saveGState()
        let dashHeight = 26 * u
        let gap = 20 * u
        var y = h * 0.5 - floor(h * 0.5 / (dashHeight + gap)) * (dashHeight + gap)
        while y < h {
            let rect = CGRect(x: w / 2 - 4 * u, y: y, width: 8 * u, height: dashHeight)
            ctx.setShadow(offset: .zero, blur: 10 * u, color: gridBright)
            ctx.setFillColor(gridBright.copy(alpha: 0.9) ?? gridBright)
            ctx.fill(rect)
            y += dashHeight + gap
        }
        ctx.restoreGState()

        // Paddles, sitting proud of each edge.
        let paddleWidth = 30 * u
        let paddleHeight = h * 0.42
        let inset = 112 * u
        let left = CGRect(x: inset - paddleWidth / 2, y: h * 0.5 - paddleHeight * 0.62,
                          width: paddleWidth, height: paddleHeight)
        let right = CGRect(x: w - inset - paddleWidth / 2, y: h * 0.5 - paddleHeight * 0.38,
                           width: paddleWidth, height: paddleHeight)
        glow(ctx, at: CGPoint(x: left.midX, y: left.midY), radius: 190 * u, color: cyan, intensity: 0.85)
        glow(ctx, at: CGPoint(x: right.midX, y: right.midY), radius: 190 * u, color: magenta, intensity: 0.85)
        neonFill(ctx, path: capsulePath(left), color: cyan, bloom: 34 * u)
        neonFill(ctx, path: capsulePath(right), color: magenta, bloom: 34 * u)
    }

    if drawFront {
        // Ball with a comet trail running left to right.
        let ballRadius = 24 * u
        let ballCenter = CGPoint(x: w * 0.635, y: h * 0.720)
        let trailStart = CGPoint(x: w * 0.240, y: h * 0.470)

        ctx.saveGState()
        ctx.setBlendMode(.plusLighter)
        let segments = 26
        for i in 0..<segments {
            let t = CGFloat(i) / CGFloat(segments - 1)
            let point = CGPoint(x: trailStart.x + (ballCenter.x - trailStart.x) * t,
                                y: trailStart.y + (ballCenter.y - trailStart.y) * t)
            let radius = ballRadius * (0.18 + 0.82 * t)
            let alpha = pow(t, 1.8) * 0.85
            glow(ctx, at: point, radius: radius * 4.2, color: rgb(0xFFFFFF), intensity: alpha * 0.55)
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: alpha))
            ctx.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius,
                                       width: radius * 2, height: radius * 2))
        }
        ctx.restoreGState()

        glow(ctx, at: ballCenter, radius: ballRadius * 7.5, color: rgb(0xFFFFFF), intensity: 0.9)
        neonFill(ctx, path: CGPath(ellipseIn: CGRect(x: ballCenter.x - ballRadius,
                                                     y: ballCenter.y - ballRadius,
                                                     width: ballRadius * 2,
                                                     height: ballRadius * 2), transform: nil),
                 color: rgb(0xFFFFFF), bloom: 40 * u)

        if showWordmark {
            let fontSize = h * 0.158
            let tracking = fontSize * 0.14
            // Measure so "NEON" and "PONG" can meet in the middle.
            let probeFont = NSFont.systemFont(ofSize: fontSize, weight: .black)
            func measure(_ s: String) -> CGFloat {
                let a = NSAttributedString(string: s, attributes: [.font: probeFont, .kern: tracking])
                return CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(a),
                                                  .useOpticalBounds).width
            }
            let gapWidth = fontSize * 0.34
            let total = measure("NEON") + gapWidth + measure("PONG")
            let baselineY = h * 0.330
            let startX = w / 2 - total / 2
            neonText(ctx, "NEON", center: CGPoint(x: startX, y: baselineY), size: fontSize,
                     color: cyan, tracking: tracking, bloom: fontSize * 0.34, align: -1)
            neonText(ctx, "PONG",
                     center: CGPoint(x: startX + measure("NEON") + gapWidth, y: baselineY),
                     size: fontSize, color: magenta, tracking: tracking,
                     bloom: fontSize * 0.34, align: -1)

            // Gold rule anchors the wordmark and echoes the in-app menu.
            let ruleWidth = total * 0.52
            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 12 * u, color: gold)
            ctx.setFillColor(gold)
            ctx.fill(CGRect(x: w / 2 - ruleWidth / 2, y: baselineY - fontSize * 0.74,
                            width: ruleWidth, height: max(2, 5 * u)))
            ctx.restoreGState()
        }
    }
}

/// Wide banner used for both top shelf sizes and the launch image.
func drawBanner(_ ctx: CGContext, size: CGSize, wordmarkScale: CGFloat, tagline: Bool) {
    let w = size.width
    let h = size.height
    let u = w / 1920.0

    let space = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: space,
                                 colors: [rgb(0x0C1636), deep, deeper] as CFArray,
                                 locations: [0, 0.6, 1]) {
        ctx.drawRadialGradient(gradient,
                               startCenter: CGPoint(x: w / 2, y: h * 0.52), startRadius: 0,
                               endCenter: CGPoint(x: w / 2, y: h * 0.52), endRadius: w * 0.62,
                               options: [.drawsAfterEndLocation])
    }

    // Perspective-ish grid.
    ctx.saveGState()
    ctx.setLineWidth(max(1, 2 * u))
    ctx.setStrokeColor(gridLine.copy(alpha: 0.5) ?? gridLine)
    for i in 0...24 {
        let x = w * CGFloat(i) / 24
        ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: h))
    }
    for i in 0...10 {
        let y = h * CGFloat(i) / 10
        ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: w, y: y))
    }
    ctx.strokePath()
    ctx.restoreGState()

    glow(ctx, at: CGPoint(x: w * 0.06, y: h / 2), radius: w * 0.34, color: cyan, intensity: 0.5)
    glow(ctx, at: CGPoint(x: w * 0.94, y: h / 2), radius: w * 0.34, color: magenta, intensity: 0.5)

    // Paddles at the extremes.
    let paddleWidth = 26 * u
    let paddleHeight = h * 0.34
    let inset = 150 * u
    let left = CGRect(x: inset, y: h * 0.5 - paddleHeight * 0.66, width: paddleWidth, height: paddleHeight)
    let right = CGRect(x: w - inset - paddleWidth, y: h * 0.5 - paddleHeight * 0.34,
                       width: paddleWidth, height: paddleHeight)
    glow(ctx, at: CGPoint(x: left.midX, y: left.midY), radius: 260 * u, color: cyan, intensity: 0.8)
    glow(ctx, at: CGPoint(x: right.midX, y: right.midY), radius: 260 * u, color: magenta, intensity: 0.8)
    neonFill(ctx, path: capsulePath(left), color: cyan, bloom: 40 * u)
    neonFill(ctx, path: capsulePath(right), color: magenta, bloom: 40 * u)

    // Centre net.
    ctx.saveGState()
    let dashHeight = 30 * u
    let gap = 24 * u
    var y: CGFloat = 0
    while y < h {
        ctx.setShadow(offset: .zero, blur: 12 * u, color: gridBright)
        ctx.setFillColor(gridBright.copy(alpha: 0.75) ?? gridBright)
        ctx.fill(CGRect(x: w / 2 - 4 * u, y: y, width: 8 * u, height: dashHeight))
        y += dashHeight + gap
    }
    ctx.restoreGState()

    // Wordmark.
    let fontSize = h * 0.26 * wordmarkScale
    let tracking = fontSize * 0.15
    let probeFont = NSFont.systemFont(ofSize: fontSize, weight: .black)
    func measure(_ s: String) -> CGFloat {
        let a = NSAttributedString(string: s, attributes: [.font: probeFont, .kern: tracking])
        return CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(a), .useOpticalBounds).width
    }
    let gapWidth = fontSize * 0.34
    let total = measure("NEON") + gapWidth + measure("PONG")
    let centreY = tagline ? h * 0.56 : h * 0.5
    let startX = w / 2 - total / 2
    neonText(ctx, "NEON", center: CGPoint(x: startX, y: centreY), size: fontSize,
             color: cyan, tracking: tracking, bloom: fontSize * 0.36, align: -1)
    neonText(ctx, "PONG", center: CGPoint(x: startX + measure("NEON") + gapWidth, y: centreY),
             size: fontSize, color: magenta, tracking: tracking, bloom: fontSize * 0.36, align: -1)

    if tagline {
        let ruleWidth = total * 0.6
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: 14 * u, color: gold)
        ctx.setFillColor(gold)
        ctx.fill(CGRect(x: w / 2 - ruleWidth / 2, y: centreY - fontSize * 0.78,
                        width: ruleWidth, height: max(2, 4 * u)))
        ctx.restoreGState()
        neonText(ctx, "COUCH CO-OP EDITION",
                 center: CGPoint(x: w / 2, y: centreY - fontSize * 1.1),
                 size: fontSize * 0.20, color: gold, tracking: fontSize * 0.06,
                 bloom: fontSize * 0.12)
    }

    // Ball, sitting just off centre so the banner is not perfectly symmetric.
    let ballRadius = h * 0.055
    let ballCenter = CGPoint(x: w * 0.5 + total * 0.30, y: tagline ? h * 0.83 : h * 0.80)
    glow(ctx, at: ballCenter, radius: ballRadius * 8, color: rgb(0xFFFFFF), intensity: 0.85)
    neonFill(ctx, path: CGPath(ellipseIn: CGRect(x: ballCenter.x - ballRadius,
                                                 y: ballCenter.y - ballRadius,
                                                 width: ballRadius * 2, height: ballRadius * 2),
                               transform: nil),
             color: rgb(0xFFFFFF), bloom: ballRadius * 1.6)
}

// MARK: - Output

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write("usage: IconForge.swift <output-directory>\n".data(using: .utf8)!)
    exit(1)
}
let root = URL(fileURLWithPath: arguments[1])
let fm = FileManager.default

func write(_ data: Data, to path: String) {
    let url = root.appendingPathComponent(path)
    try? fm.createDirectory(at: url.deletingLastPathComponent(),
                            withIntermediateDirectories: true)
    try! data.write(to: url)
    print("wrote \(path)")
}

// Layered app icon. tvOS icons are 400x240 at 1x.
let iconLayers: [(Layer, String)] = [(.back, "Back"), (.middle, "Middle"), (.front, "Front")]

for (stackName, baseSize) in [("App Icon", CGSize(width: 400, height: 240)),
                              ("App Icon - App Store", CGSize(width: 1280, height: 768))] {
    for (layer, layerName) in iconLayers {
        for scale in [1, 2] {
            let size = CGSize(width: baseSize.width * CGFloat(scale),
                              height: baseSize.height * CGFloat(scale))
            let data = render(size: size, opaque: layer == .back) { ctx, s in
                drawComposition(ctx, size: s, layer: layer, showWordmark: true)
            }
            let file = "\(stackName)-\(layerName)@\(scale)x.png"
            write(data, to: file)
        }
    }
}

// Top shelf images and the launch image are flat.
for (name, size, scale, tagline) in [
    ("TopShelf", CGSize(width: 1920, height: 720), 1, false),
    ("TopShelf", CGSize(width: 3840, height: 1440), 2, false),
    ("TopShelfWide", CGSize(width: 2320, height: 720), 1, false),
    ("TopShelfWide", CGSize(width: 4640, height: 1440), 2, false),
    ("Launch", CGSize(width: 1920, height: 1080), 1, true),
    ("Launch", CGSize(width: 3840, height: 2160), 2, true)
] as [(String, CGSize, Int, Bool)] {
    let data = render(size: size, opaque: true) { ctx, s in
        drawBanner(ctx, size: s, wordmarkScale: tagline ? 0.62 : 0.72, tagline: tagline)
    }
    write(data, to: "\(name)@\(scale)x.png")
}

print("done")
