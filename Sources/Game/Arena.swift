import SpriteKit
import UIKit

/// Fixed geometry for the play area, plus the scenery that fills it. Keeping the
/// numbers in one place means the HUD, the ball and the CPU all agree on where
/// the walls are.
enum Arena {

    /// The rectangle the ball lives in. Sits inside the tvOS overscan-safe area
    /// with room above for the score band.
    static let field = CGRect(x: 110, y: 128, width: 1700, height: 710)

    static var minX: CGFloat { field.minX }
    static var maxX: CGFloat { field.maxX }
    static var minY: CGFloat { field.minY }
    static var maxY: CGFloat { field.maxY }
    static var centerX: CGFloat { field.midX }
    static var centerY: CGFloat { field.midY }

    /// Distance from the goal line to the centre of a paddle.
    static let paddleInset: CGFloat = 74
    static let paddleWidth: CGFloat = 24
    static let paddleHeight: CGFloat = 176
    /// Vertical travel per second at full stick deflection.
    static let paddleSpeed: CGFloat = 1580

    static let ballRadius: CGFloat = 16

    /// Steepest angle off a paddle, measured from the horizontal.
    static let maxBounceAngle: CGFloat = .pi / 3.1

    static func paddleX(_ slot: PlayerSlot) -> CGFloat {
        slot.isLeft ? minX + paddleInset : maxX - paddleInset
    }

    /// The x the ball must cross for `slot` to concede.
    static func goalLine(_ slot: PlayerSlot) -> CGFloat {
        slot.isLeft ? minX : maxX
    }

    // MARK: - HUD anchors

    /// Score digits, player names and the active-effect chips live in a band
    /// above the field; toasts get their own lane along the bottom edge.
    static let scoreY: CGFloat = 950
    static let scoreOffset: CGFloat = 118
    static let nameY: CGFloat = 1006
    static let effectRailY: CGFloat = 872
    static let toastY: CGFloat = 58
    /// Baseline for the button-hint row at the bottom of every menu screen.
    static let hintRowY: CGFloat = 132

    // MARK: - Scenery

    /// Static background: outer frame, centre net, floor grid and goal glows.
    static func buildBackdrop() -> SKNode {
        let root = SKNode()

        // Perspective floor grid, faint enough to stay behind the action.
        let grid = SKNode()
        grid.alpha = 0.5
        let columns = 22
        for i in 0...columns {
            let x = field.minX + field.width * CGFloat(i) / CGFloat(columns)
            let line = bar(from: CGPoint(x: x, y: field.minY),
                           to: CGPoint(x: x, y: field.maxY),
                           width: 1.5,
                           color: Theme.arenaLine)
            line.alpha = i == columns / 2 ? 0 : 0.55
            grid.addChild(line)
        }
        let rows = 10
        for i in 0...rows {
            let y = field.minY + field.height * CGFloat(i) / CGFloat(rows)
            grid.addChild(bar(from: CGPoint(x: field.minX, y: y),
                              to: CGPoint(x: field.maxX, y: y),
                              width: 1.5,
                              color: Theme.arenaLine))
        }
        root.addChild(grid)

        // Outer frame.
        let frame = SKShapeNode(rect: field, cornerRadius: 10)
        frame.strokeColor = Theme.arenaLineBright
        frame.lineWidth = 4
        frame.glowWidth = 3
        frame.fillColor = .clear
        root.addChild(frame)

        // Dashed centre net, the one piece of the original everyone remembers.
        let net = SKNode()
        let dashHeight: CGFloat = 26
        let gap: CGFloat = 22
        var y = field.minY + 12
        while y < field.maxY - dashHeight {
            let dash = SKSpriteNode(texture: TextureFactory.pixel,
                                    color: Theme.arenaLineBright,
                                    size: CGSize(width: 6, height: dashHeight))
            dash.colorBlendFactor = 1
            dash.position = CGPoint(x: field.midX, y: y + dashHeight / 2)
            dash.alpha = 0.75
            net.addChild(dash)
            y += dashHeight + gap
        }
        root.addChild(net)

        // Goal-line glows tinted per player.
        for slot in PlayerSlot.allCases {
            let color = Theme.color(for: slot)
            let line = SKSpriteNode(texture: TextureFactory.pixel, color: color,
                                    size: CGSize(width: 5, height: field.height))
            line.colorBlendFactor = 1
            line.position = CGPoint(x: goalLine(slot), y: field.midY)
            line.alpha = 0.55
            root.addChild(line)

            let glow = GlowSprite(color: color, diameter: 620, intensity: 0.20, falloff: 2.8)
            glow.position = CGPoint(x: goalLine(slot), y: field.midY)
            glow.xScale = 0.42
            glow.yScale = field.height / 620 * 1.25
            root.addChild(glow)
        }

        return root
    }

    /// A 1px-style line drawn as a stretched sprite; cheaper than a shape node.
    static func bar(from: CGPoint, to: CGPoint, width: CGFloat, color: UIColor) -> SKSpriteNode {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = sqrt(dx * dx + dy * dy)
        let node = SKSpriteNode(texture: TextureFactory.pixel, color: color,
                                size: CGSize(width: length, height: width))
        node.colorBlendFactor = 1
        node.position = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
        node.zRotation = atan2(dy, dx)
        return node
    }
}
