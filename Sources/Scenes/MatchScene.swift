import SpriteKit
import UIKit

/// The game. Manual, sub-stepped physics rather than SKPhysicsBody, because a
/// fast ball must never tunnel through a paddle and the bounce angle has to be
/// exactly the classic "where you hit the bat decides the angle" rule.
final class MatchScene: BaseScene {

    private enum Phase {
        case countdown
        case playing
        case pointBreak
        case paused
        case awaitingController(PlayerSlot)
        case finished
    }

    // MARK: - State

    private let config: MatchConfig
    private var phase: Phase = .countdown

    private var scores: [PlayerSlot: Int] = [.one: 0, .two: 0]
    private var paddles: [PlayerSlot: Paddle] = [:]
    private var cpus: [PlayerSlot: CPUOpponent] = [:]
    private var balls: [Ball] = []
    private var powerUps: [PowerUpNode] = []
    private var activeEffects: [ActiveEffect] = []

    private let playfield = SKNode()
    private var shake: ScreenShake!
    /// Scales delta time for the slow-motion beat on the match-winning point.
    private var timeScale: CGFloat = 1

    private var phaseTimer: TimeInterval = 0
    private var powerUpTimer: TimeInterval = 0
    private var serveTarget: PlayerSlot = .one

    // HUD
    private var scoreLabels: [PlayerSlot: NeonLabel] = [:]
    private var nameLabels: [PlayerSlot: NeonLabel] = [:]
    private var effectRails: [PlayerSlot: SKNode] = [:]
    private var effectChips: [PlayerSlot: [EffectChip]] = [.one: [], .two: []]
    private var bannerNode: SKNode?
    private var pauseOverlay: SKNode?
    private var pauseList: MenuList?
    private var disconnectOverlay: SKNode?

    // Stats
    private var matchStart = Date()
    private var longestRally = 0
    private var totalRallies = 0
    private var topBallSpeed: CGFloat = 0
    private var powerUpsCollected: [PlayerSlot: Int] = [.one: 0, .two: 0]
    private var largestDeficit: [PlayerSlot: Int] = [.one: 0, .two: 0]
    private var multiballPoints = 0
    private var fireballPoints = 0
    private var matchPointReached: Set<PlayerSlot> = []

    init(size: CGSize, config: MatchConfig) {
        self.config = config
        super.init(size: size)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Build

    override func build() {
        world.addChild(playfield)
        playfield.addChild(Arena.buildBackdrop())
        shake = ScreenShake(node: playfield)

        for slot in PlayerSlot.allCases {
            let paddle = Paddle(slot: slot)
            playfield.addChild(paddle)
            paddle.attachShield(to: playfield)
            paddles[slot] = paddle
            if let difficulty = config.cpu[slot] {
                cpus[slot] = CPUOpponent(slot: slot, difficulty: difficulty)
            }
        }

        buildHUD()
        hub.isMatchActive = true
        AchievementTracker.shared.record(.matchStarted)

        serveTarget = Bool.random() ? .one : .two

        #if DEBUG
        applyDebugSeeds()
        #endif

        startCountdown()
    }

    #if DEBUG
    /// Puts the match into a specific state so a screenshot can capture it.
    private func applyDebugSeeds() {
        if let seeded = DebugHarness.seededScores {
            scores = seeded
            for slot in PlayerSlot.allCases {
                scoreLabels[slot]?.text = "\(scores[slot] ?? 0)"
            }
        }
        for kind in DebugHarness.seededEffects {
            let target: PlayerSlot = kind.isSelfBuff ? .one : .two
            switch kind {
            case .grow: paddles[target]?.sizeScale = 1.65
            case .shrink: paddles[target]?.sizeScale = 0.62
            case .freeze: paddles[target]?.speedScale = 0.42
            case .shield: paddles[target]?.giveShield()
            default: break
            }
            guard !kind.isInstant else { continue }
            activeEffects.append(ActiveEffect(kind: kind, target: target, owner: .one,
                                              remaining: kind.duration))
            rebuildEffectRail(for: target)
        }
        if DebugHarness.startPaused {
            run(.sequence([.wait(forDuration: 0.4), .run { [weak self] in
                self?.phase = .playing
                self?.pause()
            }]))
        }
        if DebugHarness.startDisconnected {
            run(.sequence([.wait(forDuration: 0.4), .run { [weak self] in
                guard let self else { return }
                // Empty the seat first; otherwise the reconnect watcher sees a
                // ready seat and dismisses the overlay on the next frame.
                self.hub.clearSeat(.two)
                self.showDisconnectOverlay(slot: .two,
                                           name: ControllerProfile(brand: .xbox,
                                                                    displayName: "").shortName)
            }]))
        }
    }
    #endif

    override func willMove(from view: SKView) {
        super.willMove(from: view)
        hub.isMatchActive = false
    }

    private func buildHUD() {
        for slot in PlayerSlot.allCases {
            let color = Theme.color(for: slot)
            let x = slot.isLeft ? 960 - Arena.scoreOffset : 960 + Arena.scoreOffset

            let score = NeonLabel("0", style: .score, color: color, glow: 0.9)
            score.position = CGPoint(x: x, y: Arena.scoreY)
            world.addChild(score)
            scoreLabels[slot] = score

            let name = NeonLabel(seatTitle(slot), style: .caption,
                                 color: color.withAlphaComponent(0.9),
                                 align: slot.isLeft ? .left : .right, glow: 0.35)
            name.position = CGPoint(x: slot.isLeft ? Arena.minX : Arena.maxX, y: Arena.nameY)
            name.fitting(width: 520)
            world.addChild(name)
            nameLabels[slot] = name

            let rail = SKNode()
            rail.position = CGPoint(x: slot.isLeft ? Arena.minX + 8 : Arena.maxX - 8,
                                    y: Arena.effectRailY)
            world.addChild(rail)
            effectRails[slot] = rail
        }

        let divider = NeonLabel("—", style: .heading, color: Theme.inkFaint, glow: 0.2)
        divider.position = CGPoint(x: 960, y: Arena.scoreY + 6)
        world.addChild(divider)

        let target = NeonLabel("FIRST TO \(config.targetScore)", style: .caption,
                               color: Theme.inkFaint, glow: 0.2)
        target.position = CGPoint(x: 960, y: Arena.nameY)
        world.addChild(target)
    }

    private func seatTitle(_ slot: PlayerSlot) -> String {
        if let difficulty = config.cpu[slot] { return "CPU · \(difficulty.title)" }
        return slot.longName
    }

    // MARK: - Phases

    private func startCountdown() {
        phase = .countdown
        phaseTimer = 0
        clearBalls()
        paddles.values.forEach { $0.resetForServe() }

        var stepDuration = 0.62
        #if DEBUG
        if DebugHarness.skipCountdown { stepDuration = 0.06 }
        #endif
        let steps = ["3", "2", "1", "GO"]
        for (index, text) in steps.enumerated() {
            run(.sequence([
                .wait(forDuration: Double(index) * stepDuration),
                .run { [weak self] in
                    guard let self else { return }
                    self.showCountdownStep(text, isGo: text == "GO")
                }
            ]))
        }
        run(.sequence([
            .wait(forDuration: Double(steps.count) * stepDuration),
            .run { [weak self] in self?.beginPlay() }
        ]))
    }

    private func showCountdownStep(_ text: String, isGo: Bool) {
        SoundEngine.shared.play(isGo ? .countdownGo : .countdown)
        let color = isGo ? Theme.good : Theme.ink
        let label = NeonLabel(text, style: .hero, color: color, glow: 1.0)
        label.position = CGPoint(x: 960, y: Arena.centerY)
        label.zPosition = 60
        label.setScale(1.6)
        label.alpha = 0
        world.addChild(label)
        label.run(.sequence([
            .group([
                .scale(to: 1, duration: 0.2).eased(.easeOut),
                .fadeAlpha(to: 1, duration: 0.12)
            ]),
            .wait(forDuration: 0.22),
            .group([
                .scale(to: 1.4, duration: 0.2),
                .fadeOut(withDuration: 0.2)
            ]),
            .removeFromParent()
        ]))
        if isGo {
            let wave = Effects.shockwave(color: Theme.good, radius: 520, duration: 0.55)
            wave.position = CGPoint(x: 960, y: Arena.centerY)
            wave.zPosition = 59
            world.addChild(wave)
        }
    }

    private func beginPlay() {
        phase = .playing
        powerUpTimer = Double.random(in: 3.5...6.0)
        serve()
        showMatchPointBannerIfNeeded()
        #if DEBUG
        if let kind = DebugHarness.seededPickup { spawnPickup(kind) }
        #endif
    }

    private func serve() {
        let ball = Ball(trailTarget: playfield)
        ball.serve(towards: serveTarget, speed: config.speed.launchSpeed)
        ball.tintTrail(Theme.ink)
        playfield.addChild(ball)
        balls = [ball]
        SoundEngine.shared.play(.countdownGo, volume: 0.35)
    }

    private func clearBalls() {
        balls.forEach { $0.removeFromParent() }
        balls.removeAll()
        powerUps.forEach { $0.expire() }
        powerUps.removeAll()
    }

    // MARK: - Update

    override func tick(dt rawDt: CGFloat) {
        let dt = rawDt * timeScale
        shake.update(dt: rawDt)

        switch phase {
        case .playing:
            updateInput(dt: dt)
            updateBalls(dt: dt)
            updateEffects(dt: dt)
            updatePowerUpSpawning(dt: dt)
        case .pointBreak:
            updateInput(dt: dt)
            updateEffects(dt: dt)
            phaseTimer -= Double(dt)
            if phaseTimer <= 0 {
                phase = .playing
                serve()
                showMatchPointBannerIfNeeded()
            }
        case .countdown:
            updateInput(dt: dt)
        case .paused, .finished:
            break
        case .awaitingController:
            updateReconnectAttempts()
        }

        updateEffectRails(dt: dt)
        checkPauseRequest()
    }

    private func checkPauseRequest() {
        guard case .playing = phase else { return }
        if hub.menuInput.pause { pause() }
    }

    // MARK: - Input and paddles

    private func updateInput(dt: CGFloat) {
        for slot in PlayerSlot.allCases {
            guard let paddle = paddles[slot] else { continue }
            if let cpu = cpus[slot] {
                let target = cpu.targetY(balls: balls, paddle: paddle, dt: dt)
                paddle.moveTo(y: target, dt: dt,
                              maxSpeed: cpu.difficulty.maxSpeed * paddle.speedScale)
            } else {
                let input = hub.steering(for: slot)
                paddle.steer(axis: input.axis, absolute: input.absolute, dt: dt)
            }
        }
    }

    // MARK: - Ball simulation

    private func updateBalls(dt: CGFloat) {
        guard !balls.isEmpty else { return }
        var scoredThisFrame = false

        for ball in balls where ball.parent != nil {
            // Sub-step so a fast ball cannot pass through a paddle in one frame.
            let travel = ball.currentSpeed * dt
            let steps = max(1, Int(ceil(travel / (ball.radius * 0.7))))
            let sub = dt / CGFloat(steps)

            for _ in 0..<steps {
                applyMagnet(to: ball, dt: sub)
                ball.position.x += ball.velocity.dx * sub
                ball.position.y += ball.velocity.dy * sub

                bounceOffWalls(ball)
                for slot in PlayerSlot.allCases { bounceOffPaddle(ball, slot: slot) }
                collectPowerUp(with: ball)

                if let conceding = goalCrossed(by: ball) {
                    if consumeShield(for: conceding, ball: ball) { continue }
                    scoredThisFrame = true
                    concede(by: conceding, ball: ball)
                    break
                }
            }

            ball.updateGhostVisibility(dt: dt)
            if ball.currentSpeed > topBallSpeed {
                topBallSpeed = ball.currentSpeed
                AchievementTracker.shared.record(.ballSpeedPeaked(topBallSpeed))
            }
            if scoredThisFrame { break }
        }
    }

    private func bounceOffWalls(_ ball: Ball) {
        let low = Arena.minY + ball.radius
        let high = Arena.maxY - ball.radius
        if ball.position.y < low, ball.velocity.dy < 0 {
            ball.position.y = low
            ball.velocity.dy = abs(ball.velocity.dy)
            wallImpact(at: CGPoint(x: ball.position.x, y: Arena.minY), ball: ball)
        } else if ball.position.y > high, ball.velocity.dy > 0 {
            ball.position.y = high
            ball.velocity.dy = -abs(ball.velocity.dy)
            wallImpact(at: CGPoint(x: ball.position.x, y: Arena.maxY), ball: ball)
        }
    }

    private func wallImpact(at point: CGPoint, ball: Ball) {
        let color = ball.lastHitBy.map { Theme.color(for: $0) } ?? Theme.ink
        let normal = CGVector(dx: 0, dy: point.y > Arena.centerY ? -1 : 1)
        let sparks = Effects.sparks(color: color, direction: normal, power: 0.55)
        sparks.position = point
        playfield.addChild(sparks)
        shake.add(0.05)
        SoundEngine.shared.play(.wallHit, volume: 0.55)
    }

    private func bounceOffPaddle(_ ball: Ball, slot: PlayerSlot) {
        guard let paddle = paddles[slot] else { return }
        let movingToward = slot.isLeft ? ball.velocity.dx < 0 : ball.velocity.dx > 0
        guard movingToward else { return }

        let faceX = Arena.paddleX(slot) + (slot.isLeft ? Arena.paddleWidth / 2 : -Arena.paddleWidth / 2)
        let crossed = slot.isLeft
            ? ball.position.x - ball.radius <= faceX
            : ball.position.x + ball.radius >= faceX
        guard crossed else { return }
        // Do not catch a ball that is already well behind the bat.
        let behind = slot.isLeft
            ? ball.position.x < Arena.paddleX(slot) - Arena.paddleWidth
            : ball.position.x > Arena.paddleX(slot) + Arena.paddleWidth
        guard !behind else { return }

        let reach = paddle.halfHeight + ball.radius
        let offset = ball.position.y - paddle.centerY
        guard abs(offset) <= reach else { return }

        // Reposition onto the face, then rebuild the velocity from the hit point.
        ball.position.x = slot.isLeft ? faceX + ball.radius : faceX - ball.radius

        let normalized = clamp(offset / reach, -1, 1)
        let angle = normalized * Arena.maxBounceAngle
        var speed = min(ball.currentSpeed + config.speed.rallyAcceleration,
                        config.speed.maxSpeed)
        if ball.isFireball { speed = min(speed * 1.02, config.speed.maxSpeed * 1.3) }

        let direction: CGFloat = slot.isLeft ? 1 : -1
        var vx = cos(angle) * speed * direction
        var vy = sin(angle) * speed
        // A little of the bat's own motion carries into the return.
        vy += paddle.velocityY * 0.20

        // Renormalise, then keep enough horizontal travel that rallies progress.
        let magnitude = sqrt(vx * vx + vy * vy)
        if magnitude > 0 {
            vx = vx / magnitude * speed
            vy = vy / magnitude * speed
        }
        let minHorizontal = speed * 0.36
        if abs(vx) < minHorizontal {
            vx = minHorizontal * direction
            let remaining = max(0, speed * speed - vx * vx)
            vy = sqrt(remaining) * (vy < 0 ? -1 : 1)
        }
        ball.velocity = CGVector(dx: vx, dy: vy)

        ball.lastHitBy = slot
        ball.rallyHits += 1
        ball.tintTrail(Theme.color(for: slot))
        longestRally = max(longestRally, ball.rallyHits)

        let power = clamp(speed / config.speed.maxSpeed, 0.25, 1.0)
        paddle.playHitFeedback(power: power)
        shake.add(0.08 + 0.14 * power)
        hub.rumbleSeat(slot, intensity: Float(0.35 + 0.5 * power), sharpness: 0.75,
                       duration: 0.06)
        SoundEngine.shared.play(power > 0.7 ? .paddleHitHard : .paddleHit,
                               volume: Float(0.6 + 0.35 * power))

        let sparks = Effects.sparks(color: Theme.color(for: slot),
                                    direction: CGVector(dx: direction, dy: 0),
                                    power: 0.7 + power * 0.6)
        sparks.position = CGPoint(x: ball.position.x, y: ball.position.y)
        playfield.addChild(sparks)

        if ball.rallyHits > 0 && ball.rallyHits % 10 == 0 {
            showBanner("\(ball.rallyHits) HIT RALLY", color: Theme.good, duration: 0.9)
        }
    }

    /// Magnet bends the ball towards its owner's paddle while it is on that
    /// owner's half and heading their way.
    private func applyMagnet(to ball: Ball, dt: CGFloat) {
        guard let owner = ball.magnetOwner, let paddle = paddles[owner] else { return }
        let onOwnerHalf = owner.isLeft
            ? ball.position.x < Arena.centerX
            : ball.position.x > Arena.centerX
        let headingToOwner = owner.isLeft ? ball.velocity.dx < 0 : ball.velocity.dx > 0
        guard onOwnerHalf && headingToOwner else { return }

        let speed = ball.currentSpeed
        let pull = (paddle.centerY - ball.position.y)
        ball.velocity.dy += clamp(pull, -1, 1) * 900 * dt
        // Preserve speed so the magnet steers without accelerating.
        let magnitude = ball.currentSpeed
        if magnitude > 0 {
            ball.velocity.dx = ball.velocity.dx / magnitude * speed
            ball.velocity.dy = ball.velocity.dy / magnitude * speed
        }
    }

    // MARK: - Goals

    /// Returns the player who just conceded, if the ball left the field.
    private func goalCrossed(by ball: Ball) -> PlayerSlot? {
        if ball.position.x + ball.radius < Arena.minX { return .one }
        if ball.position.x - ball.radius > Arena.maxX { return .two }
        return nil
    }

    private func consumeShield(for slot: PlayerSlot, ball: Ball) -> Bool {
        guard let paddle = paddles[slot], paddle.hasShield else { return false }
        paddle.consumeShield()
        ball.position.x = slot.isLeft
            ? paddle.shieldX + ball.radius + 2
            : paddle.shieldX - ball.radius - 2
        ball.velocity.dx = abs(ball.velocity.dx) * (slot.isLeft ? 1 : -1)

        let color = UIColor(hex: 0x7CC4FF)
        let burst = Effects.explosion(color: color, power: 0.8)
        burst.position = CGPoint(x: paddle.shieldX, y: ball.position.y)
        playfield.addChild(burst)
        shake.add(0.4)
        SoundEngine.shared.play(.explosion, volume: 0.5)
        hub.rumbleSeat(slot, intensity: 0.8, sharpness: 0.4, duration: 0.16)
        showBanner("SHIELD HELD", color: color, duration: 1.0)
        AchievementTracker.shared.record(.shieldBlocked)
        return true
    }

    private func concede(by conceding: PlayerSlot, ball: Ball) {
        let scorer = conceding.opponent
        let points = ball.isFireball ? 2 : 1
        let wasMultiball = balls.count > 1
        let scoredWithGhost = ball.ghostOwner == scorer

        scores[scorer] = (scores[scorer] ?? 0) + points
        totalRallies += 1
        AchievementTracker.shared.record(.pointScored(by: scorer))
        AchievementTracker.shared.record(.rallyEnded(hits: ball.rallyHits))
        if wasMultiball {
            multiballPoints += 1
            AchievementTracker.shared.record(.scoredDuringMultiball)
        }
        if ball.isFireball {
            fireballPoints += 1
            AchievementTracker.shared.record(.scoredWithFireball)
        }
        if scoredWithGhost { AchievementTracker.shared.record(.scoredWithGhostBall) }

        // Track the deepest hole each player climbed out of.
        let deficit = (scores[conceding] ?? 0) - (scores[scorer] ?? 0)
        if deficit > 0 {
            largestDeficit[scorer] = max(largestDeficit[scorer] ?? 0, deficit)
        }

        let goalPoint = CGPoint(x: Arena.goalLine(conceding),
                                y: clamp(ball.position.y, Arena.minY, Arena.maxY))
        let color = Theme.color(for: scorer)
        let burst = Effects.explosion(color: color, power: 1.5)
        burst.position = goalPoint
        playfield.addChild(burst)

        flashGoalWall(conceding, color: color)
        shake.add(0.75)
        SoundEngine.shared.play(.explosion)
        SoundEngine.shared.play(.score, volume: 0.7)
        hub.rumbleAll(intensity: 0.85, sharpness: 0.35, duration: 0.22)

        scoreLabels[scorer]?.text = "\(scores[scorer] ?? 0)"
        scoreLabels[scorer]?.pop(scale: 1.35, duration: 0.3)

        clearBallsAfterGoal()
        clearBallModifiers()

        if (scores[scorer] ?? 0) >= config.targetScore {
            finish(winner: scorer)
        } else {
            if points == 2 {
                showBanner("FIREBALL — 2 POINTS", color: UIColor(hex: 0xFF6A2C), duration: 1.3)
            }
            serveTarget = conceding
            phase = .pointBreak
            phaseTimer = 1.25
        }
    }

    private func flashGoalWall(_ slot: PlayerSlot, color: UIColor) {
        let wall = SKSpriteNode(texture: TextureFactory.pixel, color: color,
                                size: CGSize(width: 18, height: Arena.field.height))
        wall.colorBlendFactor = 1
        wall.blendMode = .add
        wall.position = CGPoint(x: Arena.goalLine(slot), y: Arena.centerY)
        wall.zPosition = 8
        playfield.addChild(wall)
        wall.run(.sequence([
            .fadeAlpha(to: 1, duration: 0.04),
            .fadeOut(withDuration: 0.5),
            .removeFromParent()
        ]))
    }

    private func clearBallsAfterGoal() {
        balls.forEach { $0.vanish() }
        balls.removeAll()
        powerUps.forEach { $0.expire() }
        powerUps.removeAll()
    }

    private func clearBallModifiers() {
        // Ball-bound modifiers die with the point; paddle timers keep running.
        let doomed: Set<PowerUpKind> = [.fireball, .ghost, .magnet, .multiball]
        guard activeEffects.contains(where: { doomed.contains($0.kind) }) else { return }
        activeEffects.removeAll { doomed.contains($0.kind) }
        PlayerSlot.allCases.forEach { rebuildEffectRail(for: $0) }
    }

    // MARK: - Power-ups

    private func updatePowerUpSpawning(dt: CGFloat) {
        guard config.powerUpsEnabled, !balls.isEmpty else { return }
        powerUpTimer -= Double(dt)
        guard powerUpTimer <= 0 else { return }
        powerUpTimer = Double.random(in: 6.5...11.0)
        guard powerUps.count < 2 else { return }

        spawnPickup(PowerUpKind.randomWeighted())
    }

    private func spawnPickup(_ kind: PowerUpKind) {
        let node = PowerUpNode(kind: kind)
        // Spawn in the middle band so neither player owns the pickup by default.
        node.position = CGPoint(
            x: .random(in: Arena.centerX - 320...Arena.centerX + 320),
            y: .random(in: Arena.minY + 130...Arena.maxY - 130))
        playfield.addChild(node)
        powerUps.append(node)
        SoundEngine.shared.play(.powerUpSpawn, volume: 0.6)

        node.run(.sequence([
            .wait(forDuration: 9.0),
            .run { [weak node] in node?.startExpiryWarning() },
            .wait(forDuration: 3.5),
            .run { [weak self, weak node] in
                guard let node, !node.isClaimed else { return }
                node.expire()
                self?.powerUps.removeAll { $0 === node }
            }
        ]))
    }

    private func collectPowerUp(with ball: Ball) {
        guard !powerUps.isEmpty else { return }
        for node in powerUps where !node.isClaimed {
            let dx = ball.position.x - node.position.x
            let dy = ball.position.y - node.position.y
            let reach = node.radius + ball.radius
            guard dx * dx + dy * dy <= reach * reach else { continue }
            // Unclaimed balls (straight off the serve) give the pickup to
            // whoever the ball is heading away from, so it is never a dead drop.
            let owner = ball.lastHitBy ?? (ball.velocity.dx > 0 ? PlayerSlot.one : .two)
            guard node.claim() else { continue }
            powerUps.removeAll { $0 === node }
            apply(node.kind, to: owner, at: node.position, ball: ball)
        }
    }

    private func apply(_ kind: PowerUpKind, to owner: PlayerSlot,
                       at point: CGPoint, ball: Ball) {
        powerUpsCollected[owner] = (powerUpsCollected[owner] ?? 0) + 1
        AchievementTracker.shared.record(.powerUpCollected(kind))

        let burst = Effects.pickupBurst(color: kind.tint)
        burst.position = point
        playfield.addChild(burst)
        shake.add(0.22)
        SoundEngine.shared.play(kind.isSelfBuff ? .powerUpGood : .powerUpBad)
        hub.rumbleSeat(owner, intensity: 0.7, sharpness: 0.6, duration: 0.14)

        let target: PlayerSlot = kind.isSelfBuff ? owner : owner.opponent
        toasts.showNotice("\(owner.shortName)  ·  \(kind.title)",
                          subtitle: kind.blurb.uppercased(),
                          tint: kind.tint, symbol: kind.symbol, duration: 2.2)

        switch kind {
        case .grow:
            paddles[target]?.sizeScale = 1.65
        case .shrink:
            paddles[target]?.sizeScale = 0.62
        case .freeze:
            paddles[target]?.speedScale = 0.42
        case .shield:
            paddles[target]?.giveShield()
        case .multiball:
            spawnMultiball(from: ball, owner: owner)
        case .fireball:
            ball.setFireball(true)
            let boosted = min(ball.currentSpeed * 1.35, config.speed.maxSpeed * 1.3)
            let magnitude = ball.currentSpeed
            if magnitude > 0 {
                ball.velocity.dx = ball.velocity.dx / magnitude * boosted
                ball.velocity.dy = ball.velocity.dy / magnitude * boosted
            }
        case .ghost:
            balls.forEach { $0.ghostOwner = owner }
        case .magnet:
            balls.forEach { $0.magnetOwner = owner }
        }

        guard !kind.isInstant else { return }
        // Refresh an existing timer rather than stacking duplicates.
        activeEffects.removeAll { $0.kind == kind && $0.target == target }
        activeEffects.append(ActiveEffect(kind: kind, target: target, owner: owner,
                                          remaining: kind.duration))
        rebuildEffectRail(for: target)
    }

    private func spawnMultiball(from source: Ball, owner: PlayerSlot) {
        let speed = source.currentSpeed
        let baseAngle = atan2(source.velocity.dy, source.velocity.dx)
        for offset in [CGFloat.pi / 7, -CGFloat.pi / 7] {
            let extra = Ball(trailTarget: playfield)
            extra.launch(from: source.position, angle: baseAngle + offset,
                         speed: speed, lastHitBy: source.lastHitBy)
            extra.tintTrail(Theme.color(for: owner))
            extra.ghostOwner = source.ghostOwner
            extra.magnetOwner = source.magnetOwner
            playfield.addChild(extra)
            balls.append(extra)
        }
    }

    // MARK: - Active effects

    private func updateEffects(dt: CGFloat) {
        guard !activeEffects.isEmpty else { return }
        var expired: [ActiveEffect] = []
        for index in activeEffects.indices.reversed() {
            activeEffects[index].remaining -= Double(dt)
            if activeEffects[index].remaining <= 0 {
                expired.append(activeEffects.remove(at: index))
            }
        }
        for effect in expired {
            switch effect.kind {
            case .grow, .shrink:
                paddles[effect.target]?.sizeScale = 1
            case .freeze:
                paddles[effect.target]?.speedScale = 1
            case .ghost:
                balls.forEach { $0.ghostOwner = nil; $0.alpha = 1 }
            case .magnet:
                balls.forEach { $0.magnetOwner = nil }
            case .multiball, .fireball, .shield:
                break
            }
            rebuildEffectRail(for: effect.target)
            SoundEngine.shared.play(.uiBack, volume: 0.4)
        }
    }

    private func rebuildEffectRail(for slot: PlayerSlot) {
        guard let rail = effectRails[slot] else { return }
        rail.removeAllChildren()
        let effects = activeEffects.filter { $0.target == slot }
        var chips: [EffectChip] = []
        var x: CGFloat = 0
        for effect in effects {
            let chip = EffectChip(effect: effect)
            // Rails grow inwards from each player's own side of the screen.
            let direction: CGFloat = slot.isLeft ? 1 : -1
            chip.position = CGPoint(x: x + direction * chip.width / 2, y: 0)
            rail.addChild(chip)
            chips.append(chip)
            x += direction * (chip.width + 16)
        }
        effectChips[slot] = chips
    }

    private func updateEffectRails(dt: CGFloat) {
        for slot in PlayerSlot.allCases {
            let effects = activeEffects.filter { $0.target == slot }
            let chips = effectChips[slot] ?? []
            guard effects.count == chips.count else { continue }
            for (chip, effect) in zip(chips, effects) {
                chip.setProgress(effect.progress, remaining: effect.remaining)
            }
        }
    }

    // MARK: - Banners

    private func showBanner(_ text: String, color: UIColor, duration: TimeInterval) {
        bannerNode?.removeFromParent()
        let label = NeonLabel(text, style: .heading, color: color, glow: 0.9)
        label.position = CGPoint(x: 960, y: Arena.maxY - 74)
        label.zPosition = 50
        label.setScale(0.85)
        label.alpha = 0
        world.addChild(label)
        bannerNode = label
        label.run(.sequence([
            .group([.scale(to: 1, duration: 0.16).eased(.easeOut),
                    .fadeAlpha(to: 1, duration: 0.12)]),
            .wait(forDuration: duration),
            .group([.scale(to: 1.1, duration: 0.24), .fadeOut(withDuration: 0.24)]),
            .removeFromParent()
        ]))
    }

    private func showMatchPointBannerIfNeeded() {
        for slot in PlayerSlot.allCases {
            guard (scores[slot] ?? 0) >= config.targetScore - 1 else { continue }
            matchPointReached.insert(slot)
            showBanner("MATCH POINT · \(slot.shortName)", color: Theme.gold, duration: 1.6)
            return
        }
    }

    // MARK: - Finish

    private func finish(winner: PlayerSlot) {
        phase = .finished
        timeScale = 0.22

        let result = MatchResult(
            winner: winner,
            scores: scores,
            longestRally: longestRally,
            totalRallies: totalRallies,
            powerUpsCollected: powerUpsCollected,
            topBallSpeed: topBallSpeed,
            duration: Date().timeIntervalSince(matchStart),
            wasComeback: (largestDeficit[winner] ?? 0) > 0,
            largestDeficitOvercome: largestDeficit[winner] ?? 0,
            multiballPoints: multiballPoints,
            fireballPoints: fireballPoints)

        persist(result)
        AchievementTracker.shared.record(.matchFinished(result, config: config))

        let flash = SKSpriteNode(color: Theme.color(for: winner), size: Theme.sceneSize)
        flash.position = CGPoint(x: 960, y: 540)
        flash.zPosition = 200
        flash.alpha = 0
        flash.blendMode = .add
        chrome.addChild(flash)
        flash.run(.sequence([
            .fadeAlpha(to: 0.55, duration: 0.06),
            .fadeOut(withDuration: 0.7)
        ]))

        shake.add(1.0)
        run(.sequence([
            .wait(forDuration: 1.5),
            .run {
                Router.shared.go(.result(result, self.config),
                                 transition: .fade(with: Theme.background, duration: 0.5))
            }
        ]))
    }

    private func persist(_ result: MatchResult) {
        SaveStore.shared.mutateStats { stats in
            stats.matchesPlayed += 1
            stats.addWin(result.winner)
            stats.totalRallies += result.totalRallies
            stats.longestRally = max(stats.longestRally, result.longestRally)
            stats.totalPoints += result.score(.one) + result.score(.two)
            stats.powerUpsCollected += result.powerUpsCollected.values.reduce(0, +)
            stats.fastestBallSpeed = max(stats.fastestBallSpeed, Double(result.topBallSpeed))
            stats.multiballPoints += result.multiballPoints
            stats.totalPlayTime += result.duration
            if result.isShutout { stats.shutouts += 1 }
            if result.wasComeback { stats.comebacks += 1 }
        }
        AchievementTracker.shared.record(.playTime(result.duration))
    }

    // MARK: - Pause

    private func pause() {
        guard case .playing = phase else { return }
        phase = .paused
        SoundEngine.shared.play(.uiBack)

        let overlay = SKNode()
        overlay.zPosition = 300
        let scrim = SKSpriteNode(color: UIColor(hex: 0x02040C, alpha: 0.82), size: Theme.sceneSize)
        scrim.position = CGPoint(x: 960, y: 540)
        overlay.addChild(scrim)

        let title = NeonLabel("PAUSED", style: .title, color: Theme.ink, glow: 0.8)
        title.position = CGPoint(x: 960, y: 790)
        overlay.addChild(title)

        let scoreline = NeonLabel("\(scores[.one] ?? 0)  —  \(scores[.two] ?? 0)",
                                  style: .heading, color: Theme.gold, glow: 0.5)
        scoreline.position = CGPoint(x: 960, y: 716)
        overlay.addChild(scoreline)

        let list = MenuList(items: [
            MenuItem(id: "resume", title: "RESUME", symbol: "play.fill", tint: Theme.good),
            MenuItem(id: "restart", title: "RESTART MATCH", symbol: "arrow.clockwise",
                     tint: Theme.p1),
            MenuItem(id: "setup", title: "CONTROLLER SETUP", symbol: "gamecontroller.fill",
                     tint: Theme.p2),
            MenuItem(id: "quit", title: "QUIT TO MENU", symbol: "house.fill", tint: Theme.danger)
        ], width: 700)
        list.position = CGPoint(x: 960, y: 470)
        list.onSelect = { [weak self] item, _ in self?.handlePauseSelection(item) }
        overlay.addChild(list)
        pauseList = list

        chrome.addChild(overlay)
        pauseOverlay = overlay
        overlay.alpha = 0
        overlay.run(.fadeIn(withDuration: 0.18))
    }

    private func handlePauseSelection(_ item: MenuItem) {
        switch item.id {
        case "resume":
            resume()
        case "restart":
            Router.shared.go(.match(config), transition: .fade(withDuration: 0.3))
        case "setup":
            Router.shared.go(.lobby(returnToMenu: true))
        default:
            Router.shared.go(.menu)
        }
    }

    private func resume() {
        pauseOverlay?.run(.sequence([.fadeOut(withDuration: 0.15), .removeFromParent()]))
        pauseOverlay = nil
        pauseList = nil
        // With a ball still on the table play just continues; between points the
        // break timer runs down as usual.
        if balls.isEmpty {
            phase = .pointBreak
            phaseTimer = 0.6
        } else {
            phase = .playing
        }
        SoundEngine.shared.play(.uiConfirm)
    }

    // MARK: - Controller loss

    override func hub(_ hub: ControllerHub, seatDidLoseDevice slot: PlayerSlot, name: String) {
        super.hub(hub, seatDidLoseDevice: slot, name: name)
        guard config.isHuman(slot) else { return }
        switch phase {
        case .finished:
            return
        default:
            showDisconnectOverlay(slot: slot, name: name)
        }
    }

    private func showDisconnectOverlay(slot: PlayerSlot, name: String) {
        guard disconnectOverlay == nil else { return }
        phase = .awaitingController(slot)

        let overlay = SKNode()
        overlay.zPosition = 320
        let scrim = SKSpriteNode(color: UIColor(hex: 0x02040C, alpha: 0.88), size: Theme.sceneSize)
        scrim.position = CGPoint(x: 960, y: 540)
        overlay.addChild(scrim)

        let panelWidth: CGFloat = 1180
        // Text must never reach the rim: the neon border and its glow need air.
        let textWidth = panelWidth - 120
        let panel = PanelNode(size: CGSize(width: panelWidth, height: 404), corner: 30,
                              fill: UIColor(hex: 0x0A0F22, alpha: 0.96),
                              stroke: Theme.danger, lineWidth: 3, rimGlow: 0.3)
        panel.position = CGPoint(x: 960, y: 556)
        overlay.addChild(panel)

        if let icon = SymbolNode("gamecontroller.fill", pointSize: 76, color: Theme.danger) {
            icon.position = CGPoint(x: 960, y: 682)
            icon.zPosition = 2
            icon.run(.breathe(from: 0.45, to: 1.0, duration: 0.9))
            overlay.addChild(icon)
        }

        let title = NeonLabel("\(slot.longName) CONTROLLER LOST", style: .heading,
                              color: Theme.danger, glow: 0.8)
        title.position = CGPoint(x: 960, y: 608)
        title.zPosition = 2
        title.fitting(width: textWidth)
        overlay.addChild(title)

        let detail = NeonLabel("\(name.uppercased()) DISCONNECTED — THE MATCH IS ON HOLD",
                               style: .caption, color: Theme.inkDim, glow: 0.2)
        detail.position = CGPoint(x: 960, y: 560)
        detail.zPosition = 2
        detail.fitting(width: textWidth)
        overlay.addChild(detail)

        let waiting = NeonLabel("RECONNECT IT, OR PRESS ANY BUTTON ON ANOTHER CONTROLLER",
                                style: .body, color: Theme.ink, glow: 0.4)
        waiting.position = CGPoint(x: 960, y: 500)
        waiting.zPosition = 2
        waiting.fitting(width: textWidth)
        waiting.run(.breathe(from: 0.55, to: 1.0, duration: 1.3))
        overlay.addChild(waiting)

        let profile = hintProfile
        let options = hintRow([
            (symbol: profile?.tertiarySymbol ?? "y.circle.fill",
             fallback: profile?.tertiaryFallback ?? "Y", label: "HAND THE SEAT TO THE CPU"),
            menuHint("QUIT")
        ], color: Theme.inkFaint)
        options.position = CGPoint(x: 960, y: 434)
        options.zPosition = 2
        overlay.addChild(options)

        chrome.addChild(overlay)
        disconnectOverlay = overlay
        overlay.alpha = 0
        overlay.run(.fadeIn(withDuration: 0.2))
    }

    /// While a seat is empty mid-match, any free controller can drop in and the
    /// match picks up where it left off.
    private func updateReconnectAttempts() {
        guard case .awaitingController(let slot) = phase else { return }

        if !hub.devicesPressingTertiary().isEmpty {
            hub.seatCPU(.pro, in: slot)
            cpus[slot] = CPUOpponent(slot: slot, difficulty: .pro)
            nameLabels[slot]?.text = "CPU · \(CPUDifficulty.pro.title)"
            dismissDisconnectOverlay(resumeMessage: "CPU TOOK OVER \(slot.shortName)")
            return
        }

        for device in hub.unassignedDevicesPressingConfirm() {
            hub.assign(device, to: slot)
            dismissDisconnectOverlay(resumeMessage: "\(slot.shortName) IS BACK")
            return
        }

        // The original pad reconnecting is auto-seated by the hub, so just watch
        // for the seat filling up again.
        if hub.isSeatReady(slot) {
            dismissDisconnectOverlay(resumeMessage: "\(slot.shortName) IS BACK")
        }
    }

    override func hub(_ hub: ControllerHub, seatDidRegainDevice slot: PlayerSlot, name: String) {
        super.hub(hub, seatDidRegainDevice: slot, name: name)
        if case .awaitingController(let waiting) = phase, waiting == slot {
            dismissDisconnectOverlay(resumeMessage: "\(slot.shortName) IS BACK")
        }
    }

    private func dismissDisconnectOverlay(resumeMessage: String) {
        disconnectOverlay?.run(.sequence([.fadeOut(withDuration: 0.2), .removeFromParent()]))
        disconnectOverlay = nil
        SoundEngine.shared.play(.controllerJoin)
        showBanner(resumeMessage, color: Theme.good, duration: 1.0)
        if balls.isEmpty {
            phase = .pointBreak
            phaseTimer = 1.0
        } else {
            phase = .playing
        }
    }

    // MARK: - Menu routing

    override func handle(menu: MenuInput) {
        switch phase {
        case .paused:
            guard let list = pauseList else { return }
            if menu.up { list.move(by: -1) }
            if menu.down { list.move(by: 1) }
            if menu.confirm { list.activate() }
            if menu.back { resume() }
        case .awaitingController:
            break
        default:
            break
        }
    }

    override func handleMenuButton() -> Bool {
        switch phase {
        case .playing, .pointBreak, .countdown:
            pause()
            return true
        case .paused:
            resume()
            return true
        case .awaitingController:
            Router.shared.go(.menu)
            return true
        case .finished:
            return true
        }
    }
}

/// Timer pill for one active power-up, shown in a player's HUD rail.
final class EffectChip: SKNode {

    let width: CGFloat
    private let bar: SKSpriteNode
    private let barWidth: CGFloat
    private let timeLabel: NeonLabel

    init(effect: ActiveEffect) {
        let tint = effect.kind.tint
        let label = NeonLabel(effect.kind.title, style: .caption, color: tint,
                              align: .left, glow: 0.35)
        width = label.contentWidth + 132
        barWidth = width - 40
        timeLabel = NeonLabel("", style: .caption, color: Theme.inkDim, align: .right, glow: 0.2)

        bar = SKSpriteNode(texture: TextureFactory.capsule(
            size: CGSize(width: barWidth, height: 8), color: tint),
                           size: CGSize(width: barWidth, height: 6))
        super.init()

        let height: CGFloat = 54
        addChild(PanelNode(size: CGSize(width: width, height: height), corner: 14,
                           fill: tint.withAlphaComponent(0.12), stroke: tint,
                           lineWidth: 2, rimGlow: 0.14))

        var x = -width / 2 + 26
        if let icon = SymbolNode(effect.kind.symbol, pointSize: 22, color: tint) {
            icon.position = CGPoint(x: x, y: 6)
            icon.zPosition = 2
            addChild(icon)
            x += 28
        }
        label.position = CGPoint(x: x, y: 6)
        label.zPosition = 2
        addChild(label)

        timeLabel.position = CGPoint(x: width / 2 - 20, y: 6)
        timeLabel.zPosition = 2
        addChild(timeLabel)

        bar.anchorPoint = CGPoint(x: 0, y: 0.5)
        bar.position = CGPoint(x: -barWidth / 2, y: -16)
        bar.zPosition = 2
        addChild(bar)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setProgress(_ progress: CGFloat, remaining: TimeInterval) {
        bar.xScale = clamp(progress, 0, 1)
        timeLabel.text = String(format: "%.0fs", max(0, remaining.rounded(.up)))
    }
}
