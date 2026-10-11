import Foundation
import SwiftData

/// Results, markers and endurance as the Goal tab uses them, for work done outside the views
/// (widgets and goal alerts), so every place predicts the same time.
nonisolated struct GoalInputs {
    let results: [Benchmark]
    let comparable: [Benchmark]
    let metrics: Set<Metric>
    let endurance: Endurance

    init(data: FitnessData) {
        let stored = (try? ModelContext(SplitcastApp.container).fetch(FetchDescriptor<RaceResult>())) ?? []
        results = stored.map(\.benchmark)
        comparable = stored.filter { !$0.notComparable && $0.date < data.now }.map(\.benchmark)
        metrics = Setting.predictionMetrics(excluding: UserDefaults.standard.string(forKey: Setting.excludedMetrics) ?? "")
        endurance = data.endurance(from: comparable, using: metrics)
    }

    /// Predicts from the chosen result, or from the best mile in recent runs when there are no
    /// results yet.
    func prediction(_ data: FitnessData, km: Double) -> (benchmark: Benchmark, prediction: Prediction)? {
        guard let benchmark = Setting.benchmark(for: km, among: comparable) ?? data.bestMileBenchmark()?.benchmark,
              let prediction = data.predict(from: benchmark, toKm: km, using: metrics, endurance: endurance) else { return nil }
        return (benchmark, prediction)
    }

    /// The goal saved for a distance, if any.
    static func goal(for km: Double) -> Double? {
        Format.parseClock(UserDefaults.standard.string(forKey: Setting.goalTime(km)) ?? "")
    }
}
