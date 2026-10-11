import Foundation
import WidgetKit

/// Works out what the widgets show for every distance and hands it to them, then checks whether a
/// goal is worth an alert. Runs after every update to the data, off the main thread (a year of
/// weekly predictions for four distances shouldn't hold up the screen).
nonisolated enum WidgetPublisher {
    /// `readAt` is when Health was last read, which the widgets use to say the data is old.
    static func publish(_ data: FitnessData, readAt: Date) {
        let inputs = GoalInputs(data: data)
        let snapshots = Predictor.standardDistances.compactMap { snapshot(data, km: $0.km, inputs: inputs, readAt: readAt) }
        if snapshots.isEmpty {
            WidgetData.clear()
        } else {
            let goalTabKm = UserDefaults.standard.object(forKey: Setting.goalKm) as? Double ?? 5
            try? WidgetData(goalTabKm: goalTabKm, snapshots: snapshots).save()
        }
        WidgetCenter.shared.reloadAllTimelines()
        GoalAlertsRunner.check(data, inputs: inputs)
    }

    static func snapshot(_ data: FitnessData, km: Double, inputs: GoalInputs, readAt: Date) -> WidgetSnapshot? {
        let defaults = UserDefaults.standard
        let units = Units(rawValue: defaults.string(forKey: Setting.units) ?? "") ?? .miles
        guard let (benchmark, now) = inputs.prediction(data, km: km) else { return nil }
        let goal = GoalInputs.goal(for: km)
        let earlier = data.calendar.date(byAdding: .day, value: -42, to: data.now)!
        let before = data.predict(from: benchmark, at: earlier, toKm: km, using: inputs.metrics, endurance: inputs.endurance)
        let yearAgo = data.calendar.date(byAdding: .year, value: -1, to: data.now)!
        let accuracy = Accuracy(data.backtest(from: benchmark, against: inputs.comparable, using: inputs.metrics))
        return WidgetSnapshot(
            dataDate: readAt,
            km: km,
            distance: Predictor.standardDistances.first { $0.km == km }?.name ?? "Race",
            predicted: now.minutes, fastest: now.fastest, slowest: now.slowest,
            pace: Format.pace(now.minutes / km, units),
            goal: goal,
            best: Records.personalBests(inputs.results)[km]?.minutes,
            changeSixWeeks: before.map { now.minutes - $0.minutes },
            needsPercent: goal.map { Predictor.fitnessNeeded(predicted: now.minutes, goal: $0) * 100 },
            accuracyPercent: accuracy.flatMap { $0.isReliable ? $0.meanPercent : nil },
            history: data.weeklyPredictions(from: benchmark, toKm: km, since: yearAgo, using: inputs.metrics, endurance: inputs.endurance)
                .map { WidgetSnapshot.Point(date: $0.date, minutes: $0.prediction.minutes) })
    }
}
