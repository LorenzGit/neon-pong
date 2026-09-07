import SpriteKit
import UIKit

/// Transient message shown along the bottom edge. Two flavours: a plain notice
/// (controller connected, effect expired) and an achievement card.
struct Toast {
    enum Style {
        case notice(tint: UIColor, symbol: String?)
        case achievement(Achievement)
    }
    let title: String
    let subtitle: String?
    let style: Style
    var duration: TimeInterval = 2.6
}

/// Queues toasts so they never overlap and never get lost.
final class ToastHost: SKNode {

    private var queue: [Toast] = []
    private var showing = false
    private let anchor: CGPoint

    init(anchor: CGPoint) {
        self.anchor = anchor
        super.init()
        zPosition = 900
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func show(_ toast: Toast) {
        queue.append(toast)
        pump()
    }

    func showNotice(_ title: String, subtitle: String? = nil,
                    tint: UIColor = Theme.p1, symbol: String? = nil,
                    duration: TimeInterval = 2.4) {
        show(Toast(title: title, subtitle: subtitle,
                   style: .notice(tint: tint, symbol: symbol), duration: duration))
    }

    func clear() {
        queue.removeAll()
        removeAllChildren()
        showing = false
    }

    private func pump() {
        guard !showing, !queue.isEmpty else { return }
        showing = true
        let toast = queue.removeFirst()
        let card = build(toast)
        card.position = CGPoint(x: anchor.x, y: anchor.y - 90)
        card.alpha = 0
        card.setScale(0.92)
        addChild(card)

        card.run(.sequence([
            .group([
                .move(to: anchor, duration: 0.30).eased(.easeOut),
                .fadeIn(withDuration: 0.22),
                .scale(to: 1, duration: 0.30).eased(.easeOut)
            ]),
            .wait(forDuration: toast.duration),
            .group([
                .move(to: CGPoint(x: anchor.x, y: anchor.y - 70), duration: 0.26),
                .fadeOut(withDuration: 0.26)
            ]),
            .removeFromParent(),
            .run { [weak self] in
                self?.showing = false
                self?.pump()
            }
        ]))
    }

    private func build(_ toast: Toast) -> SKNode {
        let tint: UIColor
        let symbolName: String?
        let eyebrow: String?

        switch toast.style {
        case .notice(let color, let symbol):
            tint = color
            symbolName = symbol
            eyebrow = nil
        case .achievement(let achievement):
            tint = achievement.tint
            symbolName = achievement.symbol
            eyebrow = "ACHIEVEMENT UNLOCKED"
        }

        let hasSubtitle = toast.subtitle != nil || eyebrow != nil
        let height: CGFloat = hasSubtitle ? 92 : 72

        // Size the card to its content instead of using a fixed width.
        let titleProbe = NeonLabel(toast.title, style: .body, color: .white, glow: 0)
        let subtitleProbe = NeonLabel(toast.subtitle ?? eyebrow ?? "",
                                      style: .caption, color: .white, glow: 0)
        let textWidth = max(titleProbe.contentWidth, subtitleProbe.contentWidth)
        let width = clamp(textWidth + (symbolName != nil ? 190 : 120), 420, 1100)

        let card = PanelNode(size: CGSize(width: width, height: height),
                             corner: height / 2,
                             fill: UIColor(hex: 0x080E1E, alpha: 0.96),
                             stroke: tint,
                             lineWidth: 3,
                             rimGlow: 0.35)

        var textX = -width / 2 + 40
        if let symbolName, let icon = SymbolNode(symbolName, pointSize: 36, color: tint) {
            icon.position = CGPoint(x: textX + 14, y: 0)
            icon.zPosition = 2
            card.addChild(icon)
            textX += 66
        }

        if let eyebrow {
            let eyebrowLabel = NeonLabel(eyebrow, style: .caption, color: tint,
                                         align: .left, glow: 0.5)
            eyebrowLabel.position = CGPoint(x: textX, y: 19)
            eyebrowLabel.zPosition = 2
            card.addChild(eyebrowLabel)

            let titleLabel = NeonLabel(toast.title, style: .body, color: Theme.ink,
                                       align: .left, glow: 0.35)
            titleLabel.position = CGPoint(x: textX, y: -16)
            titleLabel.zPosition = 2
            card.addChild(titleLabel)
        } else {
            let titleLabel = NeonLabel(toast.title, style: .body, color: Theme.ink,
                                       align: .left, glow: 0.35)
            titleLabel.position = CGPoint(x: textX, y: toast.subtitle == nil ? 0 : 16)
            titleLabel.zPosition = 2
            card.addChild(titleLabel)

            if let subtitle = toast.subtitle {
                let subtitleLabel = NeonLabel(subtitle, style: .caption, color: Theme.inkDim,
                                              align: .left, glow: 0.2)
                subtitleLabel.position = CGPoint(x: textX, y: -18)
                subtitleLabel.zPosition = 2
                card.addChild(subtitleLabel)
            }
        }

        if case .achievement = toast.style {
            // A quick sparkle sells the unlock without stealing the screen.
            let burst = Effects.pickupBurst(color: tint)
            burst.position = CGPoint(x: -width / 2 + 54, y: 0)
            burst.zPosition = 3
            burst.setScale(0.55)
            card.addChild(burst)
        }

        return card
    }
}
