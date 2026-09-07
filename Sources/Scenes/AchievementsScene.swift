import SpriteKit
import UIKit

/// Trophy case. A focus-driven grid that scrolls to keep the selected card on
/// screen, with progress bars for the counted achievements.
final class AchievementsScene: BaseScene {

    private let columns = 3
    private let cardSize = CGSize(width: 566, height: 148)
    private let rowSpacing: CGFloat = 164
    private let viewport = CGRect(x: 0, y: 168, width: 1920, height: 690)

    private var cards: [AchievementCard] = []
    private let grid = SKNode()
    private var focusIndex = 0
    private var scrollOffset: CGFloat = 0

    override func build() {
        let title = NeonLabel("ACHIEVEMENTS", style: .title, color: Theme.ink, glow: 0.8)
        title.position = CGPoint(x: 960, y: 982)
        world.addChild(title)
        title.riseIn(distance: 22)

        buildProgressHeader()
        buildGrid()

        let hints = hintRow([
            (symbol: "arrow.up.and.down.and.arrow.left.and.right", fallback: "DPAD",
             label: "BROWSE"),
            menuHint("BACK")
        ], color: Theme.inkFaint)
        hints.position = CGPoint(x: 960, y: Arena.hintRowY)
        world.addChild(hints)
    }

    private func buildProgressHeader() {
        let unlocked = AchievementTracker.shared.unlockedCount
        let total = AchievementCatalog.all.count

        let label = NeonLabel("\(unlocked) OF \(total) UNLOCKED", style: .body,
                              color: Theme.gold, glow: 0.5)
        label.position = CGPoint(x: 960, y: 922)
        world.addChild(label)

        let barWidth: CGFloat = 760
        let track = SKSpriteNode(texture: TextureFactory.capsule(
            size: CGSize(width: barWidth, height: 16), color: Theme.arenaLineBright),
                                 size: CGSize(width: barWidth, height: 14))
        track.position = CGPoint(x: 960, y: 884)
        track.alpha = 0.5
        world.addChild(track)

        let ratio = total > 0 ? CGFloat(unlocked) / CGFloat(total) : 0
        let fillWidth = max(14, barWidth * ratio)
        let fill = SKSpriteNode(texture: TextureFactory.capsule(
            size: CGSize(width: fillWidth, height: 16), color: Theme.gold),
                                size: CGSize(width: fillWidth, height: 14))
        fill.position = CGPoint(x: 960 - barWidth / 2 + fillWidth / 2, y: 884)
        fill.xScale = 0
        fill.run(.sequence([.wait(forDuration: 0.15),
                            .scaleX(to: 1, duration: 0.5).eased(.easeOut)]))
        world.addChild(fill)

        let glow = GlowSprite(color: Theme.gold, diameter: 420, intensity: 0.25, falloff: 3)
        glow.position = fill.position
        glow.yScale = 0.09
        glow.xScale = fillWidth / 420 * 1.3
        world.addChild(glow)
    }

    private func buildGrid() {
        let crop = SKCropNode()
        let mask = SKSpriteNode(color: .white, size: viewport.size)
        mask.position = CGPoint(x: viewport.midX, y: viewport.midY)
        crop.maskNode = mask
        crop.addChild(grid)
        world.addChild(crop)

        // Soften the clipped edge so a half-visible row reads as "more below".
        let fade = SKSpriteNode(
            texture: TextureFactory.verticalFade(size: CGSize(width: viewport.width, height: 90),
                                                 color: Theme.backgroundDeep, topOpaque: false),
            size: CGSize(width: viewport.width, height: 90))
        fade.position = CGPoint(x: viewport.midX, y: viewport.minY + 45)
        fade.zPosition = 20
        world.addChild(fade)

        for (index, achievement) in AchievementCatalog.all.enumerated() {
            let card = AchievementCard(achievement: achievement, size: cardSize)
            card.position = cardPosition(index)
            grid.addChild(card)
            cards.append(card)
            card.fadeIn(after: 0.02 * Double(index % 12), duration: 0.28)
        }
        updateFocus(animated: false)
    }

    private func cardPosition(_ index: Int) -> CGPoint {
        let column = index % columns
        let row = index / columns
        let x = 960 + CGFloat(column - 1) * (cardSize.width + 34)
        let y = viewport.maxY - cardSize.height / 2 - 12 - CGFloat(row) * rowSpacing
        return CGPoint(x: x, y: y)
    }

    // MARK: - Focus

    override func handle(menu: MenuInput) {
        var moved = false
        if menu.up { focusIndex -= columns; moved = true }
        if menu.down { focusIndex += columns; moved = true }
        if menu.left { focusIndex -= 1; moved = true }
        if menu.right { focusIndex += 1; moved = true }
        if moved {
            focusIndex = clamp(focusIndex, 0, cards.count - 1)
            SoundEngine.shared.play(.uiMove, volume: 0.5)
            updateFocus(animated: true)
        }
        if menu.back { goBack() }
    }

    private func updateFocus(animated: Bool) {
        for (index, card) in cards.enumerated() {
            card.setFocused(index == focusIndex, animated: animated)
        }
        scrollToFocus(animated: animated)
    }

    /// Keeps the focused row fully inside the viewport.
    private func scrollToFocus(animated: Bool) {
        let row = focusIndex / columns
        let cardTop = viewport.maxY - 12 - CGFloat(row) * rowSpacing
        let cardBottom = cardTop - cardSize.height

        var offset = scrollOffset
        if cardTop + offset > viewport.maxY - 12 {
            offset = viewport.maxY - 12 - cardTop
        }
        if cardBottom + offset < viewport.minY + 12 {
            offset = viewport.minY + 12 - cardBottom
        }
        guard offset != scrollOffset else { return }
        scrollOffset = offset
        let action = SKAction.moveTo(y: offset, duration: animated ? 0.22 : 0).eased(.easeOut)
        grid.run(action)
    }

    override func handleMenuButton() -> Bool {
        goBack()
        return true
    }

    private func goBack() {
        SoundEngine.shared.play(.uiBack)
        Router.shared.go(.menu)
    }
}

/// One achievement tile: icon, title, requirement, and either a tick or a
/// progress bar.
final class AchievementCard: SKNode {

    private let panel: PanelNode
    private let focusRing: SKSpriteNode
    private let achievement: Achievement
    private let unlocked: Bool
    private let cardSize: CGSize

    init(achievement: Achievement, size: CGSize) {
        self.achievement = achievement
        self.cardSize = size
        let tracker = AchievementTracker.shared
        unlocked = tracker.isUnlocked(achievement)
        let tint = unlocked ? achievement.tint : Theme.inkFaint

        panel = PanelNode(size: size, corner: 20,
                          fill: unlocked ? tint.withAlphaComponent(0.07)
                                         : UIColor(hex: 0x070C1B, alpha: 0.86),
                          stroke: tint, lineWidth: unlocked ? 3 : 2,
                          rimGlow: unlocked ? 0.24 : 0.06)
        focusRing = SKSpriteNode(texture: TextureFactory.panel(
            size: CGSize(width: size.width + 14, height: size.height + 14), corner: 26,
            fill: .clear, stroke: Theme.ink, lineWidth: 4),
                                 size: CGSize(width: size.width + 14, height: size.height + 14))
        focusRing.alpha = 0
        focusRing.zPosition = 6

        super.init()
        addChild(panel)
        addChild(focusRing)

        let iconX = -size.width / 2 + 50
        let textX = -size.width / 2 + 100
        // Everything to the right of the icon shares one column width.
        let textWidth = size.width / 2 - 22 - textX
        if let icon = SymbolNode(unlocked ? achievement.symbol : "lock.fill",
                                 pointSize: 46, color: tint) {
            icon.position = CGPoint(x: iconX, y: 16)
            icon.zPosition = 2
            addChild(icon)
        }

        let titleLabel = NeonLabel(achievement.title, style: .body,
                                   color: unlocked ? Theme.ink : Theme.inkDim,
                                   align: .left, glow: unlocked ? 0.4 : 0.15)
        titleLabel.position = CGPoint(x: textX, y: 34)
        titleLabel.zPosition = 2
        titleLabel.fitting(width: textWidth - 60)
        addChild(titleLabel)

        let detailLabel = NeonLabel(achievement.detail.uppercased(), style: .caption,
                                    color: Theme.inkDim, align: .left, glow: 0.12)
        detailLabel.position = CGPoint(x: textX, y: -6)
        detailLabel.zPosition = 2
        detailLabel.fitting(width: textWidth)
        addChild(detailLabel)

        if achievement.isCounted {
            addProgressBar(tint: tint, tracker: tracker)
        } else if unlocked {
            let stamp = NeonLabel("UNLOCKED", style: .caption, color: tint,
                                  align: .left, glow: 0.5)
            stamp.position = CGPoint(x: textX, y: -46)
            stamp.zPosition = 2
            addChild(stamp)
        } else {
            let stamp = NeonLabel("LOCKED", style: .caption, color: Theme.inkFaint,
                                  align: .left, glow: 0.1)
            stamp.position = CGPoint(x: textX, y: -46)
            stamp.zPosition = 2
            addChild(stamp)
        }

        if unlocked, let check = SymbolNode("checkmark.seal.fill", pointSize: 30, color: tint) {
            check.position = CGPoint(x: size.width / 2 - 44, y: size.height / 2 - 36)
            check.zPosition = 2
            addChild(check)
        }
        alpha = 0
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func addProgressBar(tint: UIColor, tracker: AchievementTracker) {
        let current = tracker.progress(achievement)
        let ratio = CGFloat(current) / CGFloat(achievement.target)
        let barWidth: CGFloat = 248
        let x = -cardSize.width / 2 + 100 + barWidth / 2

        let track = SKSpriteNode(texture: TextureFactory.capsule(
            size: CGSize(width: barWidth, height: 12), color: Theme.arenaLineBright),
                                 size: CGSize(width: barWidth, height: 10))
        track.position = CGPoint(x: x, y: -46)
        track.zPosition = 2
        track.alpha = 0.6
        addChild(track)

        if ratio > 0 {
            let fillWidth = max(10, barWidth * min(1, ratio))
            let fill = SKSpriteNode(texture: TextureFactory.capsule(
                size: CGSize(width: fillWidth, height: 12), color: tint),
                                    size: CGSize(width: fillWidth, height: 10))
            fill.position = CGPoint(x: x - barWidth / 2 + fillWidth / 2, y: -46)
            fill.zPosition = 3
            addChild(fill)
        }

        let counter = NeonLabel("\(current) / \(achievement.target)", style: .caption,
                                color: unlocked ? tint : Theme.inkDim,
                                align: .left, glow: 0.2)
        counter.position = CGPoint(x: x + barWidth / 2 + 22, y: -46)
        counter.zPosition = 2
        addChild(counter)
    }

    func setFocused(_ focused: Bool, animated: Bool) {
        let duration = animated ? 0.14 : 0.0
        removeAction(forKey: "focus")
        run(.group([
            .scale(to: focused ? 1.04 : 1.0, duration: duration).eased(.easeOut),
            .fadeAlpha(to: focused ? 1.0 : (unlocked ? 0.9 : 0.62), duration: duration)
        ]), withKey: "focus")
        focusRing.removeAllActions()
        focusRing.run(.fadeAlpha(to: focused ? 0.95 : 0, duration: duration))
        zPosition = focused ? 5 : 0
    }
}
