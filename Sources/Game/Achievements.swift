import UIKit

struct Achievement {
    let id: String
    let title: String
    let detail: String
    let symbol: String
    /// Progress needed to unlock. 1 means a simple one-shot.
    let target: Int
    let tint: UIColor

    var isCounted: Bool { target > 1 }
}

enum AchievementCatalog {

    static let all: [Achievement] = [
        Achievement(id: "first.serve", title: "FIRST SERVE",
                    detail: "Play your first match",
                    symbol: "flag.checkered", target: 1, tint: Theme.p1),
        Achievement(id: "first.point", title: "FIRST BLOOD",
                    detail: "Score your first point",
                    symbol: "target", target: 1, tint: Theme.p1),
        Achievement(id: "points.100", title: "CENTURION",
                    detail: "Score 100 points total",
                    symbol: "100.circle.fill", target: 100, tint: Theme.p1),
        Achievement(id: "points.500", title: "POINT MACHINE",
                    detail: "Score 500 points total",
                    symbol: "chart.line.uptrend.xyaxis", target: 500, tint: Theme.p1),

        Achievement(id: "rally.20", title: "KEEP IT UP",
                    detail: "20 hits in one rally",
                    symbol: "arrow.left.arrow.right", target: 1, tint: Theme.good),
        Achievement(id: "rally.40", title: "MARATHON RALLY",
                    detail: "40 hits in one rally",
                    symbol: "infinity", target: 1, tint: Theme.good),

        Achievement(id: "win.shutout", title: "FLAWLESS",
                    detail: "Win without conceding",
                    symbol: "shield.lefthalf.filled", target: 1, tint: Theme.gold),
        Achievement(id: "win.comeback", title: "NEVER IN DOUBT",
                    detail: "Win from five points down",
                    symbol: "arrow.uturn.up", target: 1, tint: Theme.gold),
        Achievement(id: "win.deuce", title: "SUDDEN DEATH",
                    detail: "Match point both ways",
                    symbol: "bolt.heart.fill", target: 1, tint: Theme.gold),
        Achievement(id: "win.long", title: "THE LONG GAME",
                    detail: "Win a match to 21",
                    symbol: "hourglass", target: 1, tint: Theme.gold),
        Achievement(id: "win.ruthless", title: "MACHINE BREAKER",
                    detail: "Beat the Ruthless CPU",
                    symbol: "cpu.fill", target: 1, tint: Theme.danger),
        Achievement(id: "win.10", title: "HOUSE FAVOURITE",
                    detail: "Win 10 matches",
                    symbol: "rosette", target: 10, tint: Theme.gold),
        Achievement(id: "win.streak3", title: "ON A HEATER",
                    detail: "Win three in a row",
                    symbol: "flame.circle.fill", target: 1, tint: Theme.danger),

        Achievement(id: "speed.2000", title: "LUDICROUS SPEED",
                    detail: "Ball past 2000 units/sec",
                    symbol: "speedometer", target: 1, tint: Theme.danger),

        Achievement(id: "power.10", title: "COLLECTOR",
                    detail: "Collect 10 power-ups",
                    symbol: "bag.fill", target: 10, tint: Theme.p2),
        Achievement(id: "power.50", title: "HOARDER",
                    detail: "Collect 50 power-ups",
                    symbol: "shippingbox.fill", target: 50, tint: Theme.p2),
        Achievement(id: "power.deck", title: "FULL DECK",
                    detail: "Collect every power-up",
                    symbol: "square.grid.3x3.fill", target: 8, tint: Theme.p2),

        Achievement(id: "power.multiball", title: "THREE'S A CROWD",
                    detail: "Score during multiball",
                    symbol: "circle.grid.2x1.fill", target: 1, tint: UIColor(hex: 0xFFB03A)),
        Achievement(id: "power.fireball", title: "SCORCHED",
                    detail: "Score with a fireball",
                    symbol: "flame.fill", target: 1, tint: UIColor(hex: 0xFF6A2C)),
        Achievement(id: "power.shield", title: "HELD THE LINE",
                    detail: "Block a shot with a shield",
                    symbol: "shield.fill", target: 1, tint: UIColor(hex: 0x7CC4FF)),
        Achievement(id: "power.ghost", title: "NOW YOU DON'T",
                    detail: "Score with the ghost ball",
                    symbol: "eye.slash.fill", target: 1, tint: UIColor(hex: 0xB8C6DE)),

        Achievement(id: "couch.ready", title: "COUCH READY",
                    detail: "Seat two controllers",
                    symbol: "person.2.fill", target: 1, tint: Theme.p1),
        Achievement(id: "time.60", title: "ALL NIGHTER",
                    detail: "Play for one hour",
                    symbol: "moon.stars.fill", target: 3600, tint: Theme.p2),
        Achievement(id: "matches.25", title: "ARCADE REGULAR",
                    detail: "Play 25 matches",
                    symbol: "gamecontroller.fill", target: 25, tint: Theme.p1)
    ]

    static func achievement(_ id: String) -> Achievement? {
        all.first { $0.id == id }
    }
}

/// Things the game reports as they happen. The tracker turns them into progress.
enum AchievementEvent {
    case matchStarted
    case pointScored(by: PlayerSlot)
    case rallyEnded(hits: Int)
    case powerUpCollected(PowerUpKind)
    case ballSpeedPeaked(CGFloat)
    case shieldBlocked
    case scoredDuringMultiball
    case scoredWithFireball
    case scoredWithGhostBall
    case twoControllersSeated
    case playTime(TimeInterval)
    case matchFinished(MatchResult, config: MatchConfig)
}

protocol AchievementTrackerDelegate: AnyObject {
    func achievementTracker(_ tracker: AchievementTracker, didUnlock achievement: Achievement)
}

/// Applies events to persistent progress and reports fresh unlocks exactly once.
final class AchievementTracker {

    static let shared = AchievementTracker()

    weak var delegate: AchievementTrackerDelegate?

    private let store = SaveStore.shared
    /// Bitmask of power-up kinds ever collected, kept under its own key.
    private let deckMaskKey = "_meta.powerupMask"
    private let streakKey = "_meta.winStreak"
    private let streakSlotKey = "_meta.winStreakSlot"

    private init() {}

    func isUnlocked(_ achievement: Achievement) -> Bool {
        store.progress(for: achievement.id) >= achievement.target
    }

    func progress(_ achievement: Achievement) -> Int {
        min(store.progress(for: achievement.id), achievement.target)
    }

    var unlockedCount: Int {
        AchievementCatalog.all.filter { isUnlocked($0) }.count
    }

    // MARK: - Event intake

    func record(_ event: AchievementEvent) {
        switch event {
        case .matchStarted:
            bump("first.serve", by: 1)
            bump("matches.25", by: 1)

        case .pointScored:
            bump("first.point", by: 1)
            bump("points.100", by: 1)
            bump("points.500", by: 1)

        case .rallyEnded(let hits):
            if hits >= 20 { unlock("rally.20") }
            if hits >= 40 { unlock("rally.40") }

        case .powerUpCollected(let kind):
            bump("power.10", by: 1)
            bump("power.50", by: 1)
            var mask = store.progress(for: deckMaskKey)
            mask |= (1 << kind.rawValue)
            store.setProgress(mask, for: deckMaskKey)
            store.setProgress(mask.nonzeroBitCount, for: "power.deck")
            checkUnlock("power.deck")

        case .ballSpeedPeaked(let speed):
            if speed >= 2000 { unlock("speed.2000") }

        case .shieldBlocked:
            unlock("power.shield")

        case .scoredDuringMultiball:
            unlock("power.multiball")

        case .scoredWithFireball:
            unlock("power.fireball")

        case .scoredWithGhostBall:
            unlock("power.ghost")

        case .twoControllersSeated:
            unlock("couch.ready")

        case .playTime(let seconds):
            bump("time.60", by: Int(seconds))

        case .matchFinished(let result, let config):
            applyMatchResult(result, config: config)
        }
    }

    private func applyMatchResult(_ result: MatchResult, config: MatchConfig) {
        if result.isShutout { unlock("win.shutout") }
        if result.wasComeback && result.largestDeficitOvercome >= 5 { unlock("win.comeback") }
        if config.targetScore >= 21 { unlock("win.long") }
        if result.margin == 1 && result.score(result.winner.opponent) >= config.targetScore - 1 {
            unlock("win.deuce")
        }
        if config.cpu[result.winner.opponent] == .ruthless { unlock("win.ruthless") }
        bump("win.10", by: 1)

        // Same seat winning three in a row.
        let previousSlot = store.progress(for: streakSlotKey)
        let streak = previousSlot == result.winner.rawValue + 1
            ? store.progress(for: streakKey) + 1
            : 1
        store.setProgress(streak, for: streakKey)
        store.setProgress(result.winner.rawValue + 1, for: streakSlotKey)
        if streak >= 3 { unlock("win.streak3") }
    }

    // MARK: - Progress helpers

    private func unlock(_ id: String) {
        guard let achievement = AchievementCatalog.achievement(id),
              store.progress(for: id) < achievement.target else { return }
        store.setProgress(achievement.target, for: id)
        announce(achievement)
    }

    private func bump(_ id: String, by amount: Int) {
        guard let achievement = AchievementCatalog.achievement(id) else { return }
        let before = store.progress(for: id)
        guard before < achievement.target else { return }
        store.setProgress(before + amount, for: id)
        if before + amount >= achievement.target { announce(achievement) }
    }

    private func checkUnlock(_ id: String) {
        guard let achievement = AchievementCatalog.achievement(id) else { return }
        // `announce` is idempotent per session because progress is clamped above.
        if store.progress(for: id) >= achievement.target, !announced.contains(id) {
            announce(achievement)
        }
    }

    private var announced: Set<String> = []

    private func announce(_ achievement: Achievement) {
        guard !announced.contains(achievement.id) else { return }
        announced.insert(achievement.id)
        delegate?.achievementTracker(self, didUnlock: achievement)
    }
}
