import Foundation

// Explanations built on the predictions: what a goal needs, how accurate the model has been,
// personal bests, and plain-English trends.

nonisolated extension Predictor {
    /// How much fitter the aerobic markers must get (0.04 = 4%) to turn `predicted` into `goal`.
    /// Time scales with the square root of the marker ratio, so the markers must move by the
    /// square of the time gap. Negative when the prediction already beats the goal.
    static func fitnessNeeded(predicted: Double, goal: Double) -> Double {
        pow(predicted / goal, 2) - 1
    }

    /// The official race distance a measured distance is meant to be (GPS reads a little long or
    /// short), or nil if it isn't close to one.
    static func officialDistance(near km: Double) -> (km: Double, name: String)? {
        standardDistances.first { abs(km / $0.km - 1) <= 0.06 }
    }
}

/// How far off the backtest predictions were.
nonisolated struct Accuracy: Sendable {
    /// Mean absolute error, in percent.
    let meanPercent: Double
    let count: Int

    /// Fewer results than this and the average says little.
    static let minimumResults = 3

    var isReliable: Bool { count >= Self.minimumResults }

    init?(_ rows: [BacktestRow]) {
        guard !rows.isEmpty else { return nil }
        meanPercent = rows.map { abs($0.errorPercent) }.reduce(0, +) / Double(rows.count)
        count = rows.count
    }
}

nonisolated enum Trend: Sendable {
    case rising, falling, flat

    /// Compares the first and last third of a window. Changes under 2% count as flat.
    static func of(_ points: [ChartPoint]) -> Trend? {
        guard points.count >= 4 else { return nil }
        let sorted = points.sorted { $0.x < $1.x }
        let third = max(1, sorted.count / 3)
        let first = sorted.prefix(third).map(\.value).reduce(0, +) / Double(third)
        let last = sorted.suffix(third).map(\.value).reduce(0, +) / Double(third)
        let scale = max(abs(first), abs(last), 1)
        let change = (last - first) / scale
        return change > 0.02 ? .rising : change < -0.02 ? .falling : .flat
    }
}

nonisolated enum Records {
    /// The fastest result at each standard distance, keyed by distance in km. Results a little
    /// off the official distance are compared at it. Every result counts, so the user removes one
    /// that wasn't real.
    static func personalBests(_ results: [Benchmark]) -> [Double: Benchmark] {
        var out: [Double: Benchmark] = [:]
        let atDistance = { (r: Benchmark, km: Double) in Predictor.riegel(minutes: r.minutes, fromKm: r.km, toKm: km) }
        for r in results {
            guard let d = Predictor.officialDistance(near: r.km) else { continue }
            if out[d.km].map({ atDistance(r, d.km) < atDistance($0, d.km) }) ?? true { out[d.km] = r }
        }
        return out
    }
}

nonisolated extension FitnessData {
    /// How much harder the heart works at the same pace now than then, in bpm (positive = harder).
    /// Fits heart rate against pace on the steady runs of both windows with one shared slope, so
    /// the difference isn't just the two windows being run at different paces.
    func heartRateShift(thenEnd: Date, nowEnd: Date) -> Double? {
        let groups = [steadyRuns(endingAt: thenEnd, needingCount: true), steadyRuns(endingAt: nowEnd, needingCount: true)]
            .map { runs in runs.compactMap { w -> (pace: Double, hr: Double)? in
                guard let pace = w.paceMinPerKm, let hr = w.hrAvg else { return nil }
                return (pace, hr)
            } }
        guard groups.allSatisfy({ !$0.isEmpty }) else { return nil }
        let means = groups.map { g in (pace: g.map(\.pace).reduce(0, +) / Double(g.count), hr: g.map(\.hr).reduce(0, +) / Double(g.count)) }
        var sxy = 0.0, sxx = 0.0
        for (g, m) in zip(groups, means) {
            for p in g {
                sxy += (p.pace - m.pace) * (p.hr - m.hr)
                sxx += (p.pace - m.pace) * (p.pace - m.pace)
            }
        }
        let slope = sxx > 0 ? sxy / sxx : 0
        return (means[1].hr - means[0].hr) - slope * (means[1].pace - means[0].pace)
    }

    /// For someone with no results yet: their fastest mile inside any run in the 8 weeks before
    /// `end`, used as a stand-in benchmark. Backtested at about 6% error, against about 3% from
    /// real races, so the app labels predictions from it as rough.
    func bestMileBenchmark(before end: Date? = nil) -> (benchmark: Benchmark, run: Workout)? {
        let end = end ?? now
        let start = end.addingTimeInterval(-56 * Self.day)
        guard let run = workouts
            .filter({ $0.activity == .running && !$0.indoor && $0.start >= start && $0.start < end && $0.bestMileMinutes != nil })
            .min(by: { $0.bestMileMinutes! < $1.bestMileMinutes! }) else { return nil }
        // Dated the day after the run, so the fitness window it's compared from includes the run.
        let date = calendar.date(byAdding: .day, value: 1, to: startOfDay(run.start))!
        return (Benchmark(id: run.id, name: "Best mile", date: date, km: 1.609344, minutes: run.bestMileMinutes!, workoutID: run.id), run)
    }

    /// Runs at the same official distance as `distance`, other than `run`.
    private func runs(atDistance distance: (km: Double, name: String), except run: Workout) -> [Workout] {
        workouts.filter { w in
            w.id != run.id && w.activity == .running && !w.indoor && Predictor.officialDistance(near: w.km ?? 0)?.km == distance.km
        }
    }

    private func pace(_ w: Workout, _ km: Double) -> Double { w.minutes / (w.km ?? km) }

    /// Whether no run at this distance has ever been quicker: a personal best still standing.
    func isFastest(_ run: Workout, distance: (km: Double, name: String)) -> Bool {
        !runs(atDistance: distance, except: run).contains { pace($0, distance.km) < pace(run, distance.km) }
    }

    /// Why a run is worth a look, e.g. "fastest 5k since May 2025": measured against the most
    /// recent earlier run at that distance that was quicker.
    func spottedReason(for run: Workout, distance: (km: Double, name: String)) -> String {
        let name = distance.name.lowercased()
        let others = runs(atDistance: distance, except: run)
        if let quicker = others.last(where: { $0.start < run.start && pace($0, distance.km) < pace(run, distance.km) }) {
            return "fastest \(name) since \(quicker.start.formatted(.dateTime.month(.wide).year()))"
        }
        return isFastest(run, distance: distance) ? "your fastest \(name)" : "your fastest \(name) at the time"
    }
}
