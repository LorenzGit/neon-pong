import Foundation
import CoreGraphics

/// The two couch-coop seats. Everything player-scoped is keyed on this.
enum PlayerSlot: Int, CaseIterable, Codable {
    case one = 0
    case two = 1

    var opponent: PlayerSlot { self == .one ? .two : .one }

    /// "P1" / "P2"
    var shortName: String { self == .one ? "P1" : "P2" }
    var longName: String { self == .one ? "PLAYER 1" : "PLAYER 2" }

    /// Player 1 defends the left wall, player 2 the right.
    var isLeft: Bool { self == .one }
}

/// Who is driving a seat.
enum SeatOccupant: Equatable {
    case empty
    /// A physical controller, identified by its stable hub id.
    case controller(ControllerID)
    case cpu(CPUDifficulty)
}

/// Stable identity for a connected controller across the app.
struct ControllerID: Hashable, Codable {
    let raw: String
}

enum CPUDifficulty: Int, CaseIterable, Codable {
    case casual = 0
    case pro = 1
    case ruthless = 2

    var title: String {
        switch self {
        case .casual: return "CASUAL"
        case .pro: return "PRO"
        case .ruthless: return "RUTHLESS"
        }
    }

    /// Fraction of the arena the paddle can cross per second.
    var maxSpeed: CGFloat {
        switch self {
        case .casual: return 780
        case .pro: return 1180
        case .ruthless: return 1650
        }
    }

    /// How far ahead the CPU predicts the ball, 0...1. Lower is more beatable.
    var prediction: CGFloat {
        switch self {
        case .casual: return 0.35
        case .pro: return 0.72
        case .ruthless: return 0.96
        }
    }

    /// Random aim error in points, applied per rally.
    var sloppiness: CGFloat {
        switch self {
        case .casual: return 130
        case .pro: return 52
        case .ruthless: return 14
        }
    }
}
