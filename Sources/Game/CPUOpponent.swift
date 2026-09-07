import CoreGraphics

/// Solo-play opponent. It predicts where the ball will cross its own goal line,
/// then drifts towards that point with a deliberate error so it stays beatable.
final class CPUOpponent {

    let slot: PlayerSlot
    let difficulty: CPUDifficulty

    /// Per-rally aim error, re-rolled whenever the ball changes direction.
    private var aimError: CGFloat = 0
    private var lastBallDirection: CGFloat = 0
    /// Idle wander so the paddle is never perfectly still.
    private var idlePhase: CGFloat = 0

    init(slot: PlayerSlot, difficulty: CPUDifficulty) {
        self.slot = slot
        self.difficulty = difficulty
        aimError = .random(in: -difficulty.sloppiness...difficulty.sloppiness)
    }

    /// Chooses a target y for this frame.
    func targetY(balls: [Ball], paddle: Paddle, dt: CGFloat) -> CGFloat {
        idlePhase += dt

        // Track the ball that will reach this side first.
        let incoming = balls.filter { ball in
            slot.isLeft ? ball.velocity.dx < 0 : ball.velocity.dx > 0
        }
        guard let ball = incoming.min(by: { timeToReach($0) < timeToReach($1) }) else {
            // Nothing coming: ease back to centre with a slow wander.
            return Arena.centerY + sin(idlePhase * 0.8) * 70
        }

        let direction: CGFloat = ball.velocity.dx < 0 ? -1 : 1
        if direction != lastBallDirection {
            lastBallDirection = direction
            aimError = .random(in: -difficulty.sloppiness...difficulty.sloppiness)
        }

        let predicted = predictCrossing(ball)
        // Blend prediction with the ball's current height. Lower difficulties
        // mostly chase the ball, which is exactly how a weak player plays.
        let naive = ball.position.y
        let blended = lerp(naive, predicted, difficulty.prediction)
        return clamp(blended + aimError, paddle.minCenterY, paddle.maxCenterY)
    }

    private func timeToReach(_ ball: Ball) -> CGFloat {
        let goal = Arena.paddleX(slot)
        let dx = goal - ball.position.x
        guard abs(ball.velocity.dx) > 1 else { return .greatestFiniteMagnitude }
        let t = dx / ball.velocity.dx
        return t > 0 ? t : .greatestFiniteMagnitude
    }

    /// Where the ball will be when it reaches this paddle's plane, accounting
    /// for bounces off the top and bottom walls.
    private func predictCrossing(_ ball: Ball) -> CGFloat {
        let time = timeToReach(ball)
        guard time < .greatestFiniteMagnitude else { return Arena.centerY }

        var y = ball.position.y + ball.velocity.dy * time
        let low = Arena.minY + ball.radius
        let high = Arena.maxY - ball.radius
        let span = high - low
        guard span > 0 else { return Arena.centerY }

        // Fold the unbounded prediction back inside the walls.
        var folded = (y - low).truncatingRemainder(dividingBy: span * 2)
        if folded < 0 { folded += span * 2 }
        y = folded <= span ? low + folded : low + (span * 2 - folded)
        return y
    }
}
