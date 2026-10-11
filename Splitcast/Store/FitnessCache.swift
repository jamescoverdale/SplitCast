import Foundation

/// The last data read from Health, saved so launches don't re-read years of history. Replaced
/// whole on every refresh.
nonisolated struct FitnessCache: Codable, Sendable {
    var savedAt: Date
    var days: [Day]
    var workouts: [Workout]
    /// Bumped when the app starts reading something new from Health, so older copies get one
    /// full re-read. 2: best power and best mile per run.
    var version: Int?

    static let currentVersion = 2
    var isCurrent: Bool { version == Self.currentVersion }

    static let staleAfterDays = 30

    static var url: URL { URL.applicationSupportDirectory.appending(path: "fitness-cache.json") }

    init(savedAt: Date = Date(), days: [Day], workouts: [Workout]) {
        self.savedAt = savedAt
        self.days = days
        self.workouts = workouts
        version = Self.currentVersion
    }

    static func load(from url: URL = url) -> FitnessCache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FitnessCache.self, from: data)
    }

    func save(to url: URL = url) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    /// How far back a quick refresh re-reads: the Watch syncs some figures late (sleep, HRV,
    /// Apple's daily revisions), so the last two weeks before the previous read are read again.
    static let rereadDays = 14

    /// Where a quick refresh starts reading from.
    func refreshStart(calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -Self.rereadDays, to: calendar.startOfDay(for: savedAt))!
    }

    /// This copy with everything from `since` onwards replaced by freshly read data.
    /// Keeps this copy's version: older runs still lack whatever a newer version reads.
    func merged(days newDays: [Day], workouts newWorkouts: [Workout], since: Date, savedAt: Date = Date()) -> FitnessCache {
        var merged = FitnessCache(savedAt: savedAt,
                                  days: days.filter { $0.date < since } + newDays,
                                  workouts: workouts.filter { $0.start < since } + newWorkouts)
        merged.version = version
        return merged
    }

    static func isStale(savedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(savedAt) > Double(staleAfterDays) * FitnessData.day
    }
}
