import SpriteKit

enum Wordmark {
    /// "NEON PONG" set in the two player colours. Used by the splash, the main
    /// menu and the generated app icon so the brand reads the same everywhere.
    static func make(scale: CGFloat = 1, glow: CGFloat = 1.0) -> SKNode {
        let node = SKNode()
        let neon = NeonLabel("NEON", style: .hero, color: Theme.p1, align: .right, glow: glow)
        let pong = NeonLabel("PONG", style: .hero, color: Theme.p2, align: .left, glow: glow)
        neon.position = CGPoint(x: -48, y: 0)
        pong.position = CGPoint(x: 48, y: 0)
        node.addChild(neon)
        node.addChild(pong)
        node.setScale(scale)
        return node
    }
}
