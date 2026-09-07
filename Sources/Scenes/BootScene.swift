import SpriteKit
import UIKit

/// Animated splash. A ball is served between two paddles, the wordmark lands on
/// the impact, then the app moves on. Any button press skips ahead.
final class BootScene: BaseScene {

    private var finished = false

    override func build() {
        let center = CGPoint(x: Theme.sceneSize.width / 2, y: Theme.sceneSize.height / 2)

        // Horizon line the whole composition sits on.
        let horizon = Arena.bar(from: CGPoint(x: 180, y: center.y - 210),
                                to: CGPoint(x: 1740, y: center.y - 210),
                                width: 2, color: Theme.arenaLineBright)
        horizon.alpha = 0
        horizon.run(.sequence([.wait(forDuration: 0.15),
                               .fadeAlpha(to: 0.5, duration: 0.5)]))
        world.addChild(horizon)

        // Paddles slide in from off-screen.
        let leftPaddle = makePaddle(color: Theme.p1)
        leftPaddle.position = CGPoint(x: -60, y: center.y)
        world.addChild(leftPaddle)
        leftPaddle.run(.sequence([
            .wait(forDuration: 0.1),
            .move(to: CGPoint(x: 330, y: center.y), duration: 0.5).eased(.easeOut)
        ]))

        let rightPaddle = makePaddle(color: Theme.p2)
        rightPaddle.position = CGPoint(x: Theme.sceneSize.width + 60, y: center.y)
        world.addChild(rightPaddle)
        rightPaddle.run(.sequence([
            .wait(forDuration: 0.1),
            .move(to: CGPoint(x: 1590, y: center.y), duration: 0.5).eased(.easeOut)
        ]))

        // The ball rallies once, and its second impact triggers the wordmark.
        let ball = SKNode()
        let ballCore = SKSpriteNode(texture: TextureFactory.disc(diameter: 96, color: .white),
                                    size: CGSize(width: 30, height: 30))
        ball.addChild(GlowSprite(color: .white, diameter: 220, intensity: 0.9))
        ball.addChild(ballCore)
        ball.position = CGPoint(x: 330, y: center.y)
        ball.alpha = 0
        ball.zPosition = 5
        let trail = Effects.ballTrail(color: Theme.p1, target: world)
        trail.particleBirthRate = 340
        ball.addChild(trail)
        world.addChild(ball)

        ball.run(.sequence([
            .wait(forDuration: 0.62),
            .fadeIn(withDuration: 0.05),
            .run { [weak self] in
                self?.impact(at: CGPoint(x: 330, y: center.y), color: Theme.p1, power: 0.7)
                SoundEngine.shared.play(.paddleHit, volume: 0.8)
            },
            .move(to: CGPoint(x: 1590, y: center.y), duration: 0.42).eased(.easeInEaseOut),
            .run { [weak self] in
                trail.particleColor = Theme.p2
                self?.impact(at: CGPoint(x: 1590, y: center.y), color: Theme.p2, power: 0.9)
                SoundEngine.shared.play(.paddleHitHard, volume: 0.9)
            },
            .move(to: center, duration: 0.24).eased(.easeIn),
            .run { [weak self] in
                self?.revealWordmark(at: center)
            },
            .fadeOut(withDuration: 0.1)
        ]))

        // Auto-advance once the reveal has had a beat to land.
        run(.sequence([.wait(forDuration: 3.4), .run { [weak self] in self?.advance() }]))
    }

    private func makePaddle(color: UIColor) -> SKNode {
        let node = SKNode()
        node.addChild(GlowSprite(color: color, diameter: 340, intensity: 0.5, falloff: 2.6)
            .placed(at: .zero))
        let core = SKSpriteNode(texture: TextureFactory.capsule(
            size: CGSize(width: 48, height: 400), color: color),
                                size: CGSize(width: 24, height: 200))
        node.addChild(core)
        return node
    }

    private func impact(at point: CGPoint, color: UIColor, power: CGFloat) {
        let sparks = Effects.sparks(color: color, direction: CGVector(dx: 0, dy: 1), power: power)
        sparks.emissionAngleRange = .pi * 2
        sparks.position = point
        world.addChild(sparks)
        let wave = Effects.shockwave(color: color, radius: 220 * power)
        wave.position = point
        world.addChild(wave)
    }

    private func revealWordmark(at center: CGPoint) {
        SoundEngine.shared.play(.explosion, volume: 0.55)
        SoundEngine.shared.play(.matchWin, volume: 0.6)
        hub.rumbleAll(intensity: 0.6, sharpness: 0.5, duration: 0.2)

        let burst = Effects.explosion(color: Theme.p1.mixed(with: Theme.p2, 0.5), power: 1.25)
        burst.position = center
        world.addChild(burst)

        let wordmark = SKNode()
        let neon = NeonLabel("NEON", style: .hero, color: Theme.p1, align: .right, glow: 1.0)
        let pong = NeonLabel("PONG", style: .hero, color: Theme.p2, align: .left, glow: 1.0)
        neon.position = CGPoint(x: -48, y: 0)
        pong.position = CGPoint(x: 48, y: 0)
        wordmark.addChild(neon)
        wordmark.addChild(pong)
        wordmark.position = CGPoint(x: center.x, y: center.y + 6)
        wordmark.zPosition = 10
        world.addChild(wordmark)

        wordmark.setScale(1.5)
        wordmark.alpha = 0
        wordmark.run(.group([
            .scale(to: 1, duration: 0.34).eased(.easeOut),
            .fadeIn(withDuration: 0.18)
        ]))

        let rule = Arena.bar(from: CGPoint(x: -300, y: 0), to: CGPoint(x: 300, y: 0),
                             width: 3, color: Theme.gold)
        rule.position = CGPoint(x: center.x, y: center.y - 112)
        rule.zPosition = 10
        rule.xScale = 0
        rule.run(.sequence([.wait(forDuration: 0.22),
                            .scaleX(to: 1, duration: 0.34).eased(.easeOut)]))
        world.addChild(rule)

        let tagline = NeonLabel("COUCH CO-OP EDITION", style: .heading,
                                color: Theme.gold, glow: 0.6)
        tagline.position = CGPoint(x: center.x, y: center.y - 168)
        tagline.zPosition = 10
        tagline.fadeIn(after: 0.34, duration: 0.3)
        world.addChild(tagline)

        let skip = NeonLabel("PRESS ANY BUTTON", style: .caption, color: Theme.inkFaint, glow: 0.2)
        skip.position = CGPoint(x: center.x, y: 150)
        skip.zPosition = 10
        skip.alpha = 0
        skip.run(.sequence([
            .wait(forDuration: 0.9),
            .fadeAlpha(to: 0.85, duration: 0.3),
            .breathe(from: 0.85, to: 0.3, duration: 1.4)
        ]))
        world.addChild(skip)
    }

    override func handle(menu: MenuInput) {
        if menu.confirm || menu.back || menu.pause { advance() }
    }

    override func handleMenuButton() -> Bool {
        advance()
        return true
    }

    private func advance() {
        guard !finished else { return }
        finished = true
        // First run drops straight into controller setup; after that the main
        // menu is the home screen.
        let store = SaveStore.shared
        let route: Route = store.hasSeenIntro ? .menu : .lobby(returnToMenu: true)
        store.hasSeenIntro = true
        Router.shared.go(route, transition: .fade(with: Theme.background, duration: 0.4))
    }
}
