import Foundation

/// All persistent state: settings, lifetime stats, achievement progress and the
/// remembered controller-to-seat mapping. Backed by UserDefaults, which is the
/// right size of hammer for a local couch game.
final class SaveStore {

    static let shared = SaveStore()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let seatSignature = "seat.signature."     // + slot raw value
        static let rumble = "settings.rumble"
        static let sound = "settings.sound"
        static let crt = "settings.crt"
        static let shake = "settings.screenShake"
        static let powerUps = "settings.powerUps"
        static let targetScore = "settings.targetScore"
        static let ballSpeed = "settings.ballSpeed"
        static let stats = "stats.v1"
        static let achievements = "achievements.v1"
        static let seenIntro = "flow.seenIntro"
    }

    private init() {
        defaults.register(defaults: [
            Key.rumble: true,
            Key.sound: true,
            Key.crt: true,
            Key.shake: true,
            Key.powerUps: true,
            Key.targetScore: 11,
            Key.ballSpeed: 1
        ])
    }

    // MARK: - Settings

    var rumbleEnabled: Bool {
        get { defaults.bool(forKey: Key.rumble) }
        set { defaults.set(newValue, forKey: Key.rumble) }
    }
    var soundEnabled: Bool {
        get { defaults.bool(forKey: Key.sound) }
        set { defaults.set(newValue, forKey: Key.sound) }
    }
    var crtEnabled: Bool {
        get { defaults.bool(forKey: Key.crt) }
        set { defaults.set(newValue, forKey: Key.crt) }
    }
    var screenShakeEnabled: Bool {
        get { defaults.bool(forKey: Key.shake) }
        set { defaults.set(newValue, forKey: Key.shake) }
    }
    var powerUpsEnabled: Bool {
        get { defaults.bool(forKey: Key.powerUps) }
        set { defaults.set(newValue, forKey: Key.powerUps) }
    }
    /// Points needed to win. 5, 7, 11 or 21.
    var targetScore: Int {
        get { defaults.integer(forKey: Key.targetScore) }
        set { defaults.set(newValue, forKey: Key.targetScore) }
    }
    /// Index into `BallSpeedPreset.allCases`.
    var ballSpeedIndex: Int {
        get { defaults.integer(forKey: Key.ballSpeed) }
        set { defaults.set(newValue, forKey: Key.ballSpeed) }
    }
    var hasSeenIntro: Bool {
        get { defaults.bool(forKey: Key.seenIntro) }
        set { defaults.set(newValue, forKey: Key.seenIntro) }
    }

    // MARK: - Remembered seats

    func rememberSeat(_ slot: PlayerSlot, signature: String) {
        defaults.set(signature, forKey: Key.seatSignature + String(slot.rawValue))
    }

    func forgetSeat(_ slot: PlayerSlot) {
        defaults.removeObject(forKey: Key.seatSignature + String(slot.rawValue))
    }

    /// The seat this controller model held last time, if any.
    func rememberedSeat(forSignature signature: String) -> PlayerSlot? {
        PlayerSlot.allCases.first {
            defaults.string(forKey: Key.seatSignature + String($0.rawValue)) == signature
        }
    }

    // MARK: - Stats

    private(set) lazy var stats: LifetimeStats = load(Key.stats) ?? LifetimeStats()

    func saveStats() { save(stats, to: Key.stats) }

    func mutateStats(_ body: (inout LifetimeStats) -> Void) {
        body(&stats)
        saveStats()
    }

    // MARK: - Achievements

    private(set) lazy var achievementProgress: [String: Int] =
        (load(Key.achievements) as [String: Int]?) ?? [:]

    func progress(for id: String) -> Int { achievementProgress[id] ?? 0 }

    func setProgress(_ value: Int, for id: String) {
        achievementProgress[id] = value
        save(achievementProgress, to: Key.achievements)
    }

    func resetAchievements() {
        achievementProgress = [:]
        save(achievementProgress, to: Key.achievements)
    }

    func resetEverything() {
        resetAchievements()
        stats = LifetimeStats()
        saveStats()
    }

    // MARK: - Codable plumbing

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, to key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

/// Aggregate numbers kept across every match ever played on this Apple TV.
struct LifetimeStats: Codable {
    var matchesPlayed = 0
    var winsBySlot: [Int: Int] = [:]
    var totalRallies = 0
    var longestRally = 0
    var totalPoints = 0
    var powerUpsCollected = 0
    var shutouts = 0
    var comebacks = 0
    var fastestBallSpeed: Double = 0
    var multiballPoints = 0
    var totalPlayTime: TimeInterval = 0

    func wins(_ slot: PlayerSlot) -> Int { winsBySlot[slot.rawValue] ?? 0 }

    mutating func addWin(_ slot: PlayerSlot) {
        winsBySlot[slot.rawValue] = wins(slot) + 1
    }
}
