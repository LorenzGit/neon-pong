import SpriteKit
import UIKit

/// Procedurally generated textures. Everything the game draws is made here at
/// launch, so the app ships with no bitmap art and stays crisp at 4K.
enum TextureFactory {

    private static var cache: [String: SKTexture] = [:]

    private static func cached(_ key: String, _ build: () -> UIImage) -> SKTexture {
        if let hit = cache[key] { return hit }
        let texture = SKTexture(image: build())
        texture.filteringMode = .linear
        cache[key] = texture
        return texture
    }

    private static func render(_ size: CGSize, _ draw: (CGContext, CGSize) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            draw(ctx.cgContext, size)
        }
    }

    // MARK: - Glows

    /// Soft radial falloff used for every light source in the game.
    /// `falloff` above 1 tightens the core; below 1 spreads it.
    static func radialGlow(diameter: CGFloat = 256,
                           color: UIColor = .white,
                           falloff: CGFloat = 2.2) -> SKTexture {
        cached("glow-\(Int(diameter))-\(color.hexKey)-\(falloff)") {
            render(CGSize(width: diameter, height: diameter)) { ctx, size in
                let steps = 48
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let radius = size.width / 2
                var colors: [CGColor] = []
                var locations: [CGFloat] = []
                for i in 0...steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    let alpha = pow(1 - t, falloff)
                    colors.append(color.withAlphaComponent(alpha).cgColor)
                    locations.append(t)
                }
                guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                                colors: colors as CFArray,
                                                locations: locations) else { return }
                ctx.drawRadialGradient(gradient,
                                       startCenter: center, startRadius: 0,
                                       endCenter: center, endRadius: radius,
                                       options: [])
            }
        }
    }

    /// A filled circle with a hard edge, anti-aliased. Used for the ball core.
    static func disc(diameter: CGFloat, color: UIColor = .white) -> SKTexture {
        cached("disc-\(Int(diameter))-\(color.hexKey)") {
            render(CGSize(width: diameter, height: diameter)) { ctx, size in
                ctx.setFillColor(color.cgColor)
                ctx.fillEllipse(in: CGRect(origin: .zero, size: size))
            }
        }
    }

    /// A capsule with a bright core fading to the edges, used for paddles and bars.
    static func capsule(size: CGSize, color: UIColor) -> SKTexture {
        cached("cap-\(Int(size.width))x\(Int(size.height))-\(color.hexKey)") {
            render(size) { ctx, s in
                let rect = CGRect(origin: .zero, size: s)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: min(s.width, s.height) / 2)
                ctx.addPath(path.cgPath)
                ctx.clip()
                let colors = [
                    color.withBrightness(1.35).cgColor,
                    color.cgColor,
                    color.withBrightness(0.72).cgColor
                ]
                guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                                colors: colors as CFArray,
                                                locations: [0, 0.45, 1]) else { return }
                // Light the short axis so the capsule reads as a tube.
                if s.height >= s.width {
                    ctx.drawLinearGradient(gradient, start: .zero,
                                           end: CGPoint(x: s.width, y: 0), options: [])
                } else {
                    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s.height),
                                           end: .zero, options: [])
                }
            }
        }
    }

    /// 1x1 white pixel, tinted by the sprite's colour. Cheap solid rectangles.
    static var pixel: SKTexture {
        cached("pixel") {
            render(CGSize(width: 4, height: 4)) { ctx, s in
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.fill(CGRect(origin: .zero, size: s))
            }
        }
    }

    /// Tall thin rectangle used as a confetti flake.
    static func confettiStrip() -> SKTexture {
        cached("confetti") {
            render(CGSize(width: 12, height: 36)) { ctx, s in
                ctx.setFillColor(UIColor.white.cgColor)
                ctx.addPath(UIBezierPath(roundedRect: CGRect(origin: .zero, size: s),
                                         cornerRadius: 3).cgPath)
                ctx.fillPath()
            }
        }
    }

    /// Small four-point star / spark used by particle emitters.
    static func spark(diameter: CGFloat = 64) -> SKTexture {
        cached("spark-\(Int(diameter))") {
            render(CGSize(width: diameter, height: diameter)) { ctx, s in
                let c = CGPoint(x: s.width / 2, y: s.height / 2)
                let r = s.width / 2
                // Soft core.
                let colors = [UIColor.white.cgColor,
                              UIColor.white.withAlphaComponent(0.0).cgColor]
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors as CFArray, locations: [0, 1]) {
                    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0,
                                           endCenter: c, endRadius: r * 0.55, options: [])
                }
                // Cross flare.
                ctx.setBlendMode(.plusLighter)
                for angle in [CGFloat(0), .pi / 2] {
                    ctx.saveGState()
                    ctx.translateBy(x: c.x, y: c.y)
                    ctx.rotate(by: angle)
                    let bar = CGRect(x: -r * 0.94, y: -r * 0.055,
                                     width: r * 1.88, height: r * 0.11)
                    ctx.addPath(UIBezierPath(roundedRect: bar, cornerRadius: r * 0.055).cgPath)
                    ctx.setFillColor(UIColor.white.withAlphaComponent(0.55).cgColor)
                    ctx.fillPath()
                    ctx.restoreGState()
                }
            }
        }
    }

    /// Square smoke puff for explosion debris.
    static func smoke(diameter: CGFloat = 96) -> SKTexture {
        cached("smoke-\(Int(diameter))") {
            render(CGSize(width: diameter, height: diameter)) { ctx, s in
                let c = CGPoint(x: s.width / 2, y: s.height / 2)
                let colors = [UIColor.white.withAlphaComponent(0.85).cgColor,
                              UIColor.white.withAlphaComponent(0.28).cgColor,
                              UIColor.white.withAlphaComponent(0.0).cgColor]
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors as CFArray, locations: [0, 0.5, 1]) {
                    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0,
                                           endCenter: c, endRadius: s.width / 2, options: [])
                }
            }
        }
    }

    // MARK: - Full-screen overlays

    /// A vignette that darkens the arena edges so the neon reads brighter.
    static func vignette(size: CGSize) -> SKTexture {
        cached("vig-\(Int(size.width))x\(Int(size.height))") {
            render(size) { ctx, s in
                let c = CGPoint(x: s.width / 2, y: s.height / 2)
                let colors = [UIColor.black.withAlphaComponent(0.0).cgColor,
                              UIColor.black.withAlphaComponent(0.10).cgColor,
                              UIColor.black.withAlphaComponent(0.62).cgColor]
                if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: colors as CFArray, locations: [0, 0.55, 1]) {
                    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0,
                                           endCenter: c, endRadius: s.width * 0.62, options: [])
                }
            }
        }
    }

    /// Full-screen CRT scanlines baked into a single texture, so the overlay
    /// costs one sprite instead of hundreds of line nodes.
    static func scanlines(size: CGSize, spacing: CGFloat = 3,
                          thickness: CGFloat = 1, opacity: CGFloat = 0.34) -> SKTexture {
        cached("scanlines-\(Int(size.width))x\(Int(size.height))-\(spacing)-\(opacity)") {
            render(size) { ctx, s in
                ctx.setFillColor(UIColor.black.withAlphaComponent(opacity).cgColor)
                var y: CGFloat = 0
                while y < s.height {
                    ctx.fill(CGRect(x: 0, y: y, width: s.width, height: thickness))
                    y += spacing
                }
            }
        }
    }

    /// Hollow ring. Scaling a sprite keeps the circle smooth, where scaling an
    /// SKShapeNode by 50x makes its path flattening visible as radial spokes.
    static func ring(diameter: CGFloat = 512, thickness: CGFloat = 26) -> SKTexture {
        cached("ring-\(Int(diameter))-\(Int(thickness))") {
            render(CGSize(width: diameter, height: diameter)) { ctx, s in
                let inset = thickness / 2 + 2
                let rect = CGRect(origin: .zero, size: s).insetBy(dx: inset, dy: inset)
                ctx.setStrokeColor(UIColor.white.cgColor)
                ctx.setLineWidth(thickness)
                ctx.strokeEllipse(in: rect)
            }
        }
    }

    /// Vertical fade to the background colour, used to soften a scroll edge.
    static func verticalFade(size: CGSize, color: UIColor, topOpaque: Bool) -> SKTexture {
        cached("fade-\(Int(size.width))x\(Int(size.height))-\(color.hexKey)-\(topOpaque)") {
            render(size) { ctx, s in
                let colors = topOpaque
                    ? [color.cgColor, color.withAlphaComponent(0).cgColor]
                    : [color.withAlphaComponent(0).cgColor, color.cgColor]
                guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                                colors: colors as CFArray,
                                                locations: [0, 1]) else { return }
                ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: s.height),
                                       end: .zero, options: [])
            }
        }
    }

    // MARK: - Panels

    /// Rounded panel with a soft inner fill and a neon border.
    static func panel(size: CGSize, corner: CGFloat, fill: UIColor, stroke: UIColor,
                      lineWidth: CGFloat = 3) -> SKTexture {
        cached("panel-\(Int(size.width))x\(Int(size.height))-\(Int(corner))-\(fill.hexKey)-\(stroke.hexKey)-\(lineWidth)") {
            render(size) { ctx, s in
                let inset = lineWidth / 2
                let rect = CGRect(origin: .zero, size: s).insetBy(dx: inset, dy: inset)
                let path = UIBezierPath(roundedRect: rect, cornerRadius: corner)
                ctx.addPath(path.cgPath)
                ctx.setFillColor(fill.cgColor)
                ctx.fillPath()
                ctx.addPath(path.cgPath)
                ctx.setStrokeColor(stroke.cgColor)
                ctx.setLineWidth(lineWidth)
                ctx.strokePath()
            }
        }
    }
}

private extension UIColor {
    /// Stable short key for cache identity.
    var hexKey: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%02X%02X%02X%02X",
                      Int(r * 255), Int(g * 255), Int(b * 255), Int(a * 255))
    }
}
