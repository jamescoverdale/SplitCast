import Foundation

/// Everything the widgets can show: one snapshot per distance, plus which distance the Goal tab
/// shows (for widgets set to follow it). Written by the app into the shared App Group folder.
/// Finished figures only: no raw health data is shared. Belongs to both the app and the widgets.
nonisolated struct WidgetData: Codable, Sendable {
    static let appGroup = "group.com.jcoverdale.split-cast"

    var goalTabKm: Double
    var snapshots: [WidgetSnapshot]

    /// The snapshot for a distance, or the Goal tab's distance when `km` is nil.
    func snapshot(km: Double?) -> WidgetSnapshot? {
        let target = km ?? goalTabKm
        return snapshots.first { $0.km == target }
    }

    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?.appending(path: "widget.json")
    }

    static func load() -> WidgetData? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetData.self, from: data)
    }

    func save() throws {
        guard let url = Self.url else { return }
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }

    static func clear() {
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    static let sample = WidgetData(goalTabKm: 5, snapshots: [.sample])
}

/// What a widget shows for one distance.
nonisolated struct WidgetSnapshot: Codable, Sendable {
    static let staleAfterDays = 30.0

    struct Point: Codable, Sendable, Hashable {
        let date: Date
        let minutes: Double
    }

    /// When Health was last read.
    var dataDate: Date
    var km: Double
    /// "5k", "10k", "Half", "Marathon".
    var distance: String
    var predicted: Double
    var fastest: Double
    var slowest: Double
    /// Pace in the user's units, e.g. "6:43/mi".
    var pace: String
    var goal: Double?
    var best: Double?
    /// Change in the prediction over 6 weeks, in minutes; negative is faster.
    var changeSixWeeks: Double?
    /// How much fitter the goal needs, in percent.
    var needsPercent: Double?
    var accuracyPercent: Double?
    /// Weekly predictions for the last year.
    var history: [Point]

    // MARK: - Display

    /// Minutes still to find; zero or less once the prediction beats the goal.
    var toGo: Double? { goal.map { predicted - $0 } }
    var goalReached: Bool { (toGo ?? 1) <= 0 }

    /// How close the prediction is to the goal, 0 to 1: full once within reach, empty 10% away.
    var progress: Double {
        guard let goal, let toGo else { return 0 }
        return min(max(1 - toGo / (goal * 0.1), 0), 1)
    }

    func ageInDays(now: Date = Date()) -> Int { Int(now.timeIntervalSince(dataDate) / 86_400) }
    func isStale(now: Date = Date()) -> Bool { Double(ageInDays(now: now)) > Self.staleAfterDays }

    /// "Sub-20 5k" for round goals, else "5k goal".
    var goalTitle: String {
        guard let goal else { return "\(distance) today" }
        let whole = (goal * 60).rounded().truncatingRemainder(dividingBy: 60) == 0
        guard whole else { return "\(distance) goal" }
        let minutes = Int(goal.rounded())
        let label = minutes < 60 ? "\(minutes)" : String(format: "%d:%02d", minutes / 60, minutes % 60)
        return "Sub-\(label) \(distance)"
    }

    /// "20:52" or "1:53:48".
    static func clock(_ minutes: Double) -> String {
        let total = Int((minutes * 60).rounded())
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// For widget previews and the placeholder.
    static let sample: WidgetSnapshot = {
        let now = Date()
        let history = (0..<52).map { i in
            Point(date: now.addingTimeInterval(Double(i - 51) * 7 * 86_400), minutes: 21.2 - 0.5 * sin(Double(i) / 8) - Double(i) * 0.006)
        }
        return WidgetSnapshot(dataDate: now, km: 5, distance: "5k", predicted: 20 + 52.0 / 60, fastest: 20 + 37.0 / 60,
                              slowest: 21, pace: "6:43/mi", goal: 20, best: 20 + 33.0 / 60, changeSixWeeks: -0.1,
                              needsPercent: 4, accuracyPercent: 2, history: history)
    }()
}
