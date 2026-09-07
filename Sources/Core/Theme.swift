import SpriteKit
import UIKit

/// Design tokens for the whole app. Every colour, size and duration used by more
/// than one screen lives here so the look stays consistent.
enum Theme {

    // MARK: - Canvas

    /// tvOS renders the UI in a 1920x1080 point space regardless of 1080p/4K output.
    static let sceneSize = CGSize(width: 1920, height: 1080)

    /// tvOS reserves an overscan-safe inset. Nothing important may sit outside this.
    static let safeInset = UIEdgeInsets(top: 60, left: 90, bottom: 60, right: 90)

    // MARK: - Palette

    static let background       = UIColor(hex: 0x04060F)
    static let backgroundDeep   = UIColor(hex: 0x01020A)
    static let arenaLine        = UIColor(hex: 0x1B2E52)
    static let arenaLineBright  = UIColor(hex: 0x2C4B84)

    static let p1               = UIColor(hex: 0x24E5FF)   // cyan
    static let p1Deep           = UIColor(hex: 0x0090C8)
    static let p2               = UIColor(hex: 0xFF3DC5)   // magenta
    static let p2Deep           = UIColor(hex: 0xB0197F)

    static let gold             = UIColor(hex: 0xFFD65C)
    static let danger           = UIColor(hex: 0xFF5A48)
    static let good             = UIColor(hex: 0x5CFF9E)
    static let ink              = UIColor(hex: 0xFFFFFF)
    static let inkDim           = UIColor(hex: 0x8FA3C4)
    static let inkFaint         = UIColor(hex: 0x4C5C78)

    static let panelFill        = UIColor(hex: 0x0A1024, alpha: 0.92)
    static let panelStroke      = UIColor(hex: 0x2A3D66)

    /// Colour assigned to a player slot.
    static func color(for slot: PlayerSlot) -> UIColor {
        slot == .one ? p1 : p2
    }

    static func deepColor(for slot: PlayerSlot) -> UIColor {
        slot == .one ? p1Deep : p2Deep
    }

    // MARK: - Type scale

    enum TextStyle {
        case hero        // splash wordmark
        case title       // screen titles
        case heading     // section headings
        case body        // paragraphs, list rows
        case caption     // hints, metadata
        case score       // in-match score digits
        case button

        var size: CGFloat {
            switch self {
            case .hero:    return 168
            case .title:   return 76
            case .heading: return 42
            case .body:    return 30
            case .caption: return 25
            case .score:   return 92
            case .button:  return 34
            }
        }

        var weight: UIFont.Weight {
            switch self {
            case .hero, .score: return .black
            case .title:        return .heavy
            case .heading:      return .bold
            case .button:       return .semibold
            case .body:         return .medium
            case .caption:      return .medium
            }
        }

        /// Letter spacing. Wide tracking is what sells the arcade-marquee feel.
        var tracking: CGFloat {
            switch self {
            case .hero:    return 26
            case .title:   return 12
            case .heading: return 6
            case .score:   return 4
            case .button:  return 4
            case .body:    return 1.5
            case .caption: return 2.5
            }
        }

        var monospaced: Bool {
            switch self {
            case .score, .caption: return true
            default: return false
            }
        }
    }

    static func font(_ style: TextStyle) -> UIFont {
        if style.monospaced {
            return UIFont.monospacedSystemFont(ofSize: style.size, weight: style.weight)
        }
        return UIFont.systemFont(ofSize: style.size, weight: style.weight)
    }

    // MARK: - Motion

    /// Standard screen transition. Short enough to feel instant on a remote.
    static let transition: TimeInterval = 0.28
    /// Delay before a held stick starts repeating in menus.
    static let menuRepeatDelay: TimeInterval = 0.42
    static let menuRepeatInterval: TimeInterval = 0.14
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: alpha
        )
    }

    /// Blend towards another colour. `t` of 0 returns self.
    func mixed(with other: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let u = max(0, min(1, t))
        return UIColor(red: r1 + (r2 - r1) * u,
                       green: g1 + (g2 - g1) * u,
                       blue: b1 + (b2 - b1) * u,
                       alpha: a1 + (a2 - a1) * u)
    }

    func withBrightness(_ scale: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: max(0, min(1, b * scale)), alpha: a)
    }
}
