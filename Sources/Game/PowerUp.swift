import CoreGraphics
import UIKit

/// The eight pickups that can spawn mid-arena. A pickup is claimed by whoever
/// last touched the ball that hit it, which keeps the rule readable at a glance.
enum PowerUpKind: Int, CaseIterable {
    case grow
    case shrink
    case multiball
    case fireball
    case shield
    case freeze
    case magnet
    case ghost

    var title: String {
        switch self {
        case .grow: return "EXPAND"
        case .shrink: return "SHRINK RAY"
        case .multiball: return "MULTIBALL"
        case .fireball: return "FIREBALL"
        case .shield: return "SHIELD"
        case .freeze: return "DEEP FREEZE"
        case .magnet: return "MAGNET"
        case .ghost: return "GHOST BALL"
        }
    }

    /// One line of copy shown on the pickup toast.
    var blurb: String {
        switch self {
        case .grow: return "Your paddle grows"
        case .shrink: return "Their paddle shrinks"
        case .multiball: return "Two extra balls"
        case .fireball: return "Faster ball, worth 2 points"
        case .shield: return "Blocks one shot"
        case .freeze: return "Their paddle slows down"
        case .magnet: return "The ball bends your way"
        case .ghost: return "The ball fades on their half"
        }
    }

    var symbol: String {
        switch self {
        case .grow: return "arrow.up.and.down"
        case .shrink: return "arrow.down.right.and.arrow.up.left"
        case .multiball: return "circle.grid.2x1.fill"
        case .fireball: return "flame.fill"
        case .shield: return "shield.fill"
        case .freeze: return "snowflake"
        case .magnet: return "scope"
        case .ghost: return "eye.slash.fill"
        }
    }

    /// Single-character stand-in when the SF Symbol is unavailable.
    var glyphFallback: String {
        switch self {
        case .grow: return "^"
        case .shrink: return "v"
        case .multiball: return "oo"
        case .fireball: return "*"
        case .shield: return "U"
        case .freeze: return "#"
        case .magnet: return "@"
        case .ghost: return "?"
        }
    }

    /// True when the effect lands on the collector, false when it hits the
    /// opponent. Drives the pickup's colour and the toast wording.
    var isSelfBuff: Bool {
        switch self {
        case .grow, .multiball, .fireball, .shield, .magnet, .ghost: return true
        case .shrink, .freeze: return false
        }
    }

    var tint: UIColor {
        switch self {
        case .grow: return Theme.good
        case .shrink: return Theme.danger
        case .multiball: return UIColor(hex: 0xFFB03A)
        case .fireball: return UIColor(hex: 0xFF6A2C)
        case .shield: return UIColor(hex: 0x7CC4FF)
        case .freeze: return UIColor(hex: 0x76E4FF)
        case .magnet: return UIColor(hex: 0xC98BFF)
        case .ghost: return UIColor(hex: 0xB8C6DE)
        }
    }

    /// Seconds the effect stays live. Instant effects return 0.
    var duration: TimeInterval {
        switch self {
        case .grow: return 11
        case .shrink: return 9
        case .freeze: return 6.5
        case .magnet: return 8
        case .ghost: return 8
        case .multiball, .fireball, .shield: return 0
        }
    }

    /// Instant effects apply once and never appear in the active-effect rail.
    var isInstant: Bool { duration == 0 }

    /// Relative spawn weight. Multiball and fireball are the loudest, so they
    /// show up less often than the steady modifiers.
    var weight: Int {
        switch self {
        case .grow: return 16
        case .shrink: return 14
        case .multiball: return 8
        case .fireball: return 9
        case .shield: return 12
        case .freeze: return 12
        case .magnet: return 11
        case .ghost: return 9
        }
    }

    static func randomWeighted() -> PowerUpKind {
        let total = allCases.reduce(0) { $0 + $1.weight }
        var roll = Int.random(in: 0..<total)
        for kind in allCases {
            roll -= kind.weight
            if roll < 0 { return kind }
        }
        return .grow
    }
}

/// A timed modifier currently applied to a player.
struct ActiveEffect {
    let kind: PowerUpKind
    /// The player the effect acts on. For `shrink` this is the victim.
    let target: PlayerSlot
    /// The player who collected it, for scoring and stats.
    let owner: PlayerSlot
    var remaining: TimeInterval

    var progress: CGFloat {
        guard kind.duration > 0 else { return 0 }
        return CGFloat(remaining / kind.duration)
    }
}
