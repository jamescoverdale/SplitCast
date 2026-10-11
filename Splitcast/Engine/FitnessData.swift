import Foundation

/// Everything the app knows about the athlete, with the window calculations on top.
/// A window "ending at" a date covers the days before it; the date itself is excluded.
nonisolated struct FitnessData: Sendable {
    static let window = 42.0
    /// Each metre climbed counts as this many metres of flat running in distance per heartbeat.
    /// Tested against the user's races: 6, 8 and 10 all helped about equally.
    static let climbEquivalent = 8.0
    static let shortWindow = 28.0
    /// One or two slow jogs in a quiet spell would swing the efficiency metrics.
    static let minSteadyRuns = 3

    let days: [Day]
    let workouts: [Workout]
    let hrRest: Double
    let hrMax: Double
    /// Start of the day after the latest data: "now" windows end here.
    let now: Date
    let calendar: Calendar
    private let loadByDay: [Date: Load]

    struct Load: Sendable {
        var fitness = 0.0
        var fatigue = 0.0
    }

    init(days: [Day], workouts: [Workout], hrRest: Double? = nil, hrMax: Double? = nil,
         now: Date? = nil, calendar: Calendar = .current) {
        self.calendar = calendar
        self.days = days.sorted { $0.date < $1.date }
        self.workouts = workouts.sorted { $0.start < $1.start }
        let latest = [self.days.last?.date, self.workouts.last?.start].compactMap { $0 }.max() ?? Date()
        let now = now ?? calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: latest))!
        self.now = now
        let hrRest = hrRest ?? Self.derivedRestingHR(self.days, now: now)
        let hrMax = hrMax ?? Self.derivedMaxHR(self.workouts, now: now)
        self.hrRest = hrRest
        self.hrMax = hrMax
        loadByDay = Self.banister(self.workouts, hrRest: hrRest, hrMax: hrMax, until: now, calendar: calendar)
    }

    // MARK: - Snapshots

    func snapshot(at end: Date) -> [Metric: Double] {
        var out: [Metric: Double] = [:]
        for m in Metric.allCases {
            out[m] = value(m, at: end)
        }
        return out
    }

    func value(_ metric: Metric, at end: Date) -> Double? {
        switch metric {
        case .vo2max:
            guard let last = days.last(where: { $0.date < end && $0.vo2max != nil }),
                  last.date >= end.addingTimeInterval(-90 * Self.day) else { return nil }
            return mean(days.filter { $0.date <= last.date && $0.date > last.date.addingTimeInterval(-30 * Self.day) }
                .compactMap(\.vo2max))
        case .distancePerBeat:
            return mean(steadyRuns(endingAt: end, needingCount: true).map(distancePerBeat))
        case .powerPerBeat:
            return mean(steadyRuns(endingAt: end, withPower: true, needingCount: true).map(powerPerBeat))
        case .criticalPower:
            return criticalPower(runs(endingAt: end).filter { !$0.indoor })
        case .runVolume:
            return runs(endingAt: end, days: Self.shortWindow).compactMap(\.km).reduce(0, +) / 4
        case .longestRun:
            return runs(endingAt: end).compactMap(\.km).max()
        case .climb:
            let w = onFoot(endingAt: end, days: Self.shortWindow).compactMap(\.elevUpM)
            return w.isEmpty ? nil : w.reduce(0, +) / 4
        case .fitness:
            return load(before: end)?.fitness
        case .form:
            return load(before: end).map { $0.fitness - $0.fatigue }
        case .restingHR:
            return mean(daysIn(endingAt: end, days: Self.shortWindow).compactMap(\.restingHR))
        case .hrv:
            return mean(daysIn(endingAt: end, days: Self.shortWindow).compactMap(\.hrv))
        case .sleep:
            let nights = daysIn(endingAt: end, days: Self.shortWindow).compactMap(\.sleepMinutes).filter { $0 >= 180 }
            return nights.count >= 7 ? mean(nights) : nil
        }
    }

    /// The window before `end` as chart points (x = days before `end`), for the detail charts.
    func points(_ metric: Metric, endingAt end: Date) -> [ChartPoint] {
        let x = { (d: Date) in d.timeIntervalSince(end) / Self.day }
        switch metric {
        case .vo2max:
            return daysIn(endingAt: end).compactMap { d in d.vo2max.map { ChartPoint(x: x(d.date), value: $0) } }
        case .distancePerBeat:
            return steadyRuns(endingAt: end).map { ChartPoint(x: x($0.start), value: distancePerBeat($0), workoutID: $0.id) }
        case .powerPerBeat:
            return steadyRuns(endingAt: end, withPower: true).map { ChartPoint(x: x($0.start), value: powerPerBeat($0), workoutID: $0.id) }
        case .criticalPower:
            return runs(endingAt: end).filter { !$0.indoor }.compactMap { w in criticalPower([w]).map { ChartPoint(x: x(w.start), value: $0, workoutID: w.id) } }
        case .runVolume:
            return cumulative(runs(endingAt: end), end: end) { $0.km }
        case .longestRun:
            return runs(endingAt: end).compactMap { w in w.km.map { ChartPoint(x: x(w.start), value: $0, workoutID: w.id) } }
        case .climb:
            return cumulative(onFoot(endingAt: end), end: end) { $0.elevUpM }
        case .fitness, .form:
            return daysBetween(end.addingTimeInterval(-Self.window * Self.day), end).compactMap { d in
                loadByDay[d].map { ChartPoint(x: x(d), value: metric == .fitness ? $0.fitness : $0.fitness - $0.fatigue) }
            }
        case .restingHR:
            return daysIn(endingAt: end).compactMap { d in d.restingHR.map { ChartPoint(x: x(d.date), value: $0) } }
        case .hrv:
            return daysIn(endingAt: end).compactMap { d in d.hrv.map { ChartPoint(x: x(d.date), value: $0) } }
        case .sleep:
            return daysIn(endingAt: end).compactMap { d in
                d.sleepMinutes.flatMap { $0 >= 180 ? ChartPoint(x: x(d.date), value: $0) : nil }
            }
        }
    }

    // MARK: - Workout filters

    /// Steady outdoor runs: 5 km+ at an easy-to-moderate effort, so pace per heartbeat compares
    /// run to run. The HR band is 67-86% of max (120-154 bpm at a 180 max).
    func isSteady(_ w: Workout) -> Bool {
        guard w.activity == .running, !w.indoor, (w.km ?? 0) >= 5, let hr = w.hrAvg else { return false }
        return hr >= hrMax * 0.667 && hr <= hrMax * 0.856
    }

    func steadyRuns(endingAt end: Date, withPower: Bool = false, needingCount: Bool = false) -> [Workout] {
        let list = runs(endingAt: end).filter { isSteady($0) && (!withPower || $0.powerW != nil) }
        return needingCount && list.count < Self.minSteadyRuns ? [] : list
    }

    func runs(endingAt end: Date, days: Double = window) -> [Workout] {
        workouts(endingAt: end, days: days).filter { $0.activity == .running }
    }

    func onFoot(endingAt end: Date, days: Double = window) -> [Workout] {
        workouts(endingAt: end, days: days).filter { $0.activity.isOnFoot }
    }

    func workouts(endingAt end: Date, days: Double = window) -> [Workout] {
        let start = end.addingTimeInterval(-days * Self.day)
        return workouts.filter { $0.start < end && $0.start >= start }
    }

    /// Metres per heartbeat, with climbing counted as extra flat distance.
    func distancePerBeat(_ w: Workout) -> Double {
        ((w.km ?? 0) * 1000 + Self.climbEquivalent * (w.elevUpM ?? 0)) / (w.minutes * (w.hrAvg ?? .infinity))
    }

    /// Critical power from the best 3- and 12-minute power across `runs`: the two-point model
    /// (work = CP × time + reserve) solved for CP. Nil without both efforts.
    func criticalPower(_ runs: [Workout]) -> Double? {
        let p3 = runs.compactMap(\.bestPower3).max(), p12 = runs.compactMap(\.bestPower12).max()
        guard let p3, let p12 else { return nil }
        let cp = (12 * p12 - 3 * p3) / 9
        return cp > 0 ? cp : nil
    }
    func powerPerBeat(_ w: Workout) -> Double { (w.powerW ?? 0) / (w.hrAvg ?? .infinity) }

    // MARK: - Helpers

    static let day: TimeInterval = 86_400

    func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    private func daysIn(endingAt end: Date, days count: Double = window) -> [Day] {
        let start = end.addingTimeInterval(-count * Self.day)
        return days.filter { $0.date < end && $0.date >= start }
    }

    private func daysBetween(_ start: Date, _ end: Date) -> [Date] {
        var out: [Date] = []
        var d = startOfDay(start)
        while d < end {
            out.append(d)
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        return out
    }

    private func load(before end: Date) -> Load? {
        loadByDay[startOfDay(end.addingTimeInterval(-1))]
    }

    private func cumulative(_ list: [Workout], end: Date, value: (Workout) -> Double?) -> [ChartPoint] {
        var total = 0.0
        return list.compactMap { w in
            guard let v = value(w) else { return nil }
            total += v
            return ChartPoint(x: w.start.timeIntervalSince(end) / Self.day, value: total, workoutID: w.id)
        }
    }

    private func mean(_ xs: [Double]) -> Double? {
        xs.isEmpty ? nil : xs.reduce(0, +) / Double(xs.count)
    }

    // MARK: - Derived settings

    /// Median resting HR over the last 90 days of data.
    static func derivedRestingHR(_ days: [Day], now: Date) -> Double {
        let recent = days.filter { $0.date >= now.addingTimeInterval(-90 * day) }.compactMap(\.restingHR).sorted()
        return recent.isEmpty ? 60 : recent[recent.count / 2]
    }

    /// Near-highest running HR in the last two years. Workout maxima above 205 are treated as
    /// sensor spikes; the 98th percentile drops the odd stray reading below that.
    static func derivedMaxHR(_ workouts: [Workout], now: Date) -> Double {
        let maxima = workouts
            .filter { $0.activity == .running && $0.start >= now.addingTimeInterval(-730 * day) }
            .compactMap(\.hrMax).filter { $0 <= 205 }.sorted()
        return maxima.isEmpty ? 185 : maxima[min(maxima.count - 1, Int(Double(maxima.count) * 0.98))]
    }

    /// Banister fitness (42-day) and fatigue (7-day) from daily TRIMP, keyed by day.
    static func banister(_ workouts: [Workout], hrRest: Double, hrMax: Double, until end: Date,
                         calendar: Calendar) -> [Date: Load] {
        guard let first = workouts.first else { return [:] }
        var trimpByDay: [Date: Double] = [:]
        for w in workouts {
            guard let hr = w.hrAvg, hrMax > hrRest else { continue }
            let hrr = min(max((hr - hrRest) / (hrMax - hrRest), 0), 1)
            trimpByDay[calendar.startOfDay(for: w.start), default: 0] += w.minutes * hrr * 0.64 * exp(1.92 * hrr)
        }
        var out: [Date: Load] = [:]
        var load = Load()
        var d = calendar.startOfDay(for: first.start)
        while d < end {
            let t = trimpByDay[d] ?? 0
            load.fitness += (t - load.fitness) / 42
            load.fatigue += (t - load.fatigue) / 7
            out[d] = load
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        return out
    }
}

nonisolated struct ChartPoint: Sendable, Hashable {
    var x: Double
    var value: Double
    var workoutID: UUID? = nil
}
