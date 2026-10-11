import Foundation

/// @AppStorage keys, so views agree on them.
nonisolated enum Setting {
    static let units = "units"
    static let onboarded = "onboarded"
    static let compareResult = "compareResult"
    static let goalKm = "goalKm"
    static let goalYears = "goalYears"
    /// Comma-separated `Metric` raw values left out of predictions.
    static let excludedMetrics = "excludedMetrics"
    /// On unless the user turns it off.
    static let backgroundUpdates = "backgroundUpdates"
    /// Off until the user turns it on.
    static let goalAlerts = "goalAlerts"
    static let goalAlertState = "goalAlertState"

    static var backgroundUpdatesOn: Bool { UserDefaults.standard.object(forKey: backgroundUpdates) as? Bool ?? true }

    // No dots in keys: @AppStorage observes UserDefaults by key path.
    static func goalTime(_ km: Double) -> String { "goalTime-\(Int(km * 1000))m" }
    static func goalBenchmark(_ km: Double) -> String { "goalBenchmark-\(Int(km * 1000))m" }

    /// The result a distance is predicted from: the one chosen on the Goal tab, else the one at the
    /// closest distance (most recent first).
    static func benchmark(for km: Double, among results: [Benchmark]) -> Benchmark? {
        let chosen = UserDefaults.standard.string(forKey: goalBenchmark(km))
        return results.first { $0.id.uuidString == chosen } ?? results.min { abs(log($0.km / km)) < abs(log($1.km / km)) }
    }

    static func predictionMetrics(excluding raw: String) -> Set<Metric> {
        let excluded = Set(raw.split(separator: ",").compactMap { Metric(rawValue: String($0)) })
        return Metric.predictionMetrics.subtracting(excluded)
    }

}
