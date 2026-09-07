import CoreGraphics
import Foundation

enum BallSpeedPreset: Int, CaseIterable {
    case chill = 0
    case classic = 1
    case turbo = 2

    var title: String {
        switch self {
        case .chill: return "CHILL"
        case .classic: return "CLASSIC"
        case .turbo: return "TURBO"
        }
    }

    /// Serve speed in points per second.
    var launchSpeed: CGFloat {
        switch self {
        case .chill: return 780
        case .classic: return 1020
        case .turbo: return 1340
        }
    }

    /// Speed added on every paddle hit.
    var rallyAcceleration: CGFloat {
        switch self {
        case .chill: return 26
        case .classic: return 42
        case .turbo: return 58
        }
    }

    var maxSpeed: CGFloat {
        switch self {
        case .chill: return 1700
        case .classic: return 2250
        case .turbo: return 2900
        }
    }
}

/// Everything that defines how one match plays. Built from settings + seats.
struct MatchConfig {
    var targetScore: Int
    var speed: BallSpeedPreset
    var powerUpsEnabled: Bool
    /// nil when a human holds the seat.
    var cpu: [PlayerSlot: CPUDifficulty]

    static func current(seats: (PlayerSlot) -> SeatOccupant) -> MatchConfig {
        let store = SaveStore.shared
        var cpu: [PlayerSlot: CPUDifficulty] = [:]
        for slot in PlayerSlot.allCases {
            if case .cpu(let difficulty) = seats(slot) { cpu[slot] = difficulty }
        }
        return MatchConfig(
            targetScore: store.targetScore,
            speed: BallSpeedPreset(rawValue: store.ballSpeedIndex) ?? .classic,
            powerUpsEnabled: store.powerUpsEnabled,
            cpu: cpu)
    }

    func isHuman(_ slot: PlayerSlot) -> Bool { cpu[slot] == nil }

    var isSinglePlayer: Bool { !cpu.isEmpty }
}

/// What happened in a finished match, handed to the result screen and the
/// achievement engine.
struct MatchResult {
    var winner: PlayerSlot
    var scores: [PlayerSlot: Int]
    var longestRally: Int
    var totalRallies: Int
    var powerUpsCollected: [PlayerSlot: Int]
    var topBallSpeed: CGFloat
    var duration: TimeInterval
    var wasComeback: Bool
    var largestDeficitOvercome: Int
    var multiballPoints: Int
    /// Points scored while the fireball modifier was live.
    var fireballPoints: Int

    func score(_ slot: PlayerSlot) -> Int { scores[slot] ?? 0 }
    var isShutout: Bool { score(winner.opponent) == 0 }
    var margin: Int { score(winner) - score(winner.opponent) }
}
