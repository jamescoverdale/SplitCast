import Foundation

/// How much data a metric has in a window against what it needs, so the app can say why
/// something was left out ("1 of 3 steady runs").
nonisolated struct Coverage: Sendable {
    let have: Int
    let need: Int
    /// What's being counted, e.g. "steady runs", "nights of 3 h+".
    let unit: String
    /// Extra context, e.g. why some runs didn't count, or when the last reading was.
    var detail: String?

    var isEnough: Bool { have >= need }
    var summary: String { "\(have) of \(need) \(unit)" }
}

nonisolated extension FitnessData {
    func coverage(_ metric: Metric, endingAt end: Date) -> Coverage {
        switch metric {
        case .vo2max:
            let recent = days.filter { $0.date < end && $0.date >= end.addingTimeInterval(-90 * Self.day) && $0.vo2max != nil }
            var c = Coverage(have: recent.count, need: 1, unit: recent.count == 1 ? "reading in the 3 months before" : "readings in the 3 months before")
            if recent.isEmpty, let last = days.last(where: { $0.date < end && $0.vo2max != nil }) {
                c.detail = "Last reading \(Self.monthsBefore(last.date, end)) before."
            }
            return c
        case .distancePerBeat:
            return steadyCoverage(endingAt: end, withPower: false)
        case .powerPerBeat:
            return steadyCoverage(endingAt: end, withPower: true)
        case .criticalPower:
            let outdoor = runs(endingAt: end).filter { !$0.indoor }
            let withPower = outdoor.filter { $0.powerW != nil }
            let have = outdoor.filter { $0.bestPower3 != nil && $0.bestPower12 != nil }.count
            let detail = withPower.isEmpty ? "No runs with running power in the 6 weeks before."
                : "\(withPower.count) run\(withPower.count == 1 ? "" : "s") with running power; \(have) long enough for a 12-minute effort."
            return Coverage(have: have, need: 1, unit: have == 1 ? "run with 3 and 12 minute power" : "runs with 3 and 12 minute power", detail: detail)
        case .runVolume:
            return Coverage(have: runs(endingAt: end, days: Self.shortWindow).count, need: 1, unit: "runs in the 4 weeks before")
        case .longestRun:
            return Coverage(have: runs(endingAt: end).count, need: 1, unit: "runs in the 6 weeks before")
        case .climb:
            let all = onFoot(endingAt: end, days: Self.shortWindow)
            let withElevation = all.filter { $0.elevUpM != nil }.count
            return Coverage(have: withElevation, need: 1, unit: "workouts with elevation",
                            detail: all.isEmpty ? nil : "\(withElevation) of \(all.count) walks, runs and hikes in the 4 weeks before have elevation.")
        case .fitness, .form:
            return Coverage(have: workouts(endingAt: end).filter { $0.hrAvg != nil }.count, need: 1, unit: "workouts with heart rate")
        case .restingHR:
            return dayCoverage(endingAt: end, unit: "days with resting heart rate") { $0.restingHR != nil }
        case .hrv:
            return dayCoverage(endingAt: end, unit: "days with HRV") { $0.hrv != nil }
        case .sleep:
            let window = days.filter { $0.date < end && $0.date >= end.addingTimeInterval(-Self.shortWindow * Self.day) }
            let full = window.filter { ($0.sleepMinutes ?? 0) >= 180 }.count
            let short = window.filter { ($0.sleepMinutes ?? 0) > 0 && ($0.sleepMinutes ?? 0) < 180 }.count
            return Coverage(have: full, need: 7, unit: "nights of 3 h+ tracked",
                            detail: short > 0 ? "\(short) shorter night\(short == 1 ? "" : "s") not counted (under 3 hours)." : nil)
        }
    }

    /// Steady runs in the window, and why the other runs didn't count.
    private func steadyCoverage(endingAt end: Date, withPower: Bool) -> Coverage {
        let all = runs(endingAt: end)
        let steady = all.filter { isSteady($0) }
        let have = withPower ? steady.filter { $0.powerW != nil }.count : steady.count
        var reasons: [String] = []
        let count = { (n: Int, text: String) in if n > 0 { reasons.append("\(n) \(text)") } }
        count(all.filter(\.indoor).count, "indoor")
        count(all.filter { !$0.indoor && ($0.km ?? 0) < 5 }.count, "under 5 km")
        count(all.filter { !$0.indoor && ($0.km ?? 0) >= 5 && $0.hrAvg == nil }.count, "without heart rate")
        count(all.filter { !$0.indoor && ($0.km ?? 0) >= 5 && $0.hrAvg != nil && !isSteady($0) }.count, "too hard or too easy")
        if withPower { count(steady.count - have, "steady but without running power") }
        let detail = all.isEmpty ? "No runs in the 6 weeks before."
            : "\(all.count) run\(all.count == 1 ? "" : "s") in the 6 weeks before" + (reasons.isEmpty ? "." : ": " + reasons.joined(separator: ", ") + ".")
        return Coverage(have: have, need: Self.minSteadyRuns, unit: withPower ? "steady runs with power" : "steady runs", detail: detail)
    }

    private func dayCoverage(endingAt end: Date, unit: String, has: (Day) -> Bool) -> Coverage {
        let n = days.filter { $0.date < end && $0.date >= end.addingTimeInterval(-Self.shortWindow * Self.day) && has($0) }.count
        return Coverage(have: n, need: 1, unit: unit)
    }

    private static func monthsBefore(_ date: Date, _ end: Date) -> String {
        let months = Int((end.timeIntervalSince(date) / (30.4 * day)).rounded())
        return months <= 1 ? "about a month" : "\(months) months"
    }
}
