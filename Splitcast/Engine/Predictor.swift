import Foundation

nonisolated struct Prediction: Sendable {
    let minutes: Double
    let fastest: Double
    let slowest: Double
    /// How many markers the estimate rests on.
    let markers: Int
    let fromKm: Double
    let toKm: Double
    let endurance: Endurance

    /// Predicting a marathon from a 5k (or the reverse) leans heavily on the distance exponent.
    var isLongStretch: Bool { abs(log(toKm / fromKm)) > log(2.2) }
}

/// How much slower the athlete gets as distance grows: Riegel's exponent. 1.06 is the textbook
/// value for runners trained for the distance; most recreational runners fade more over long races.
nonisolated struct Endurance: Sendable, Equatable {
    let exponent: Double
    /// Pairs of the athlete's own results it was fitted from; 0 = the textbook value.
    let pairs: Int

    static let standard = Endurance(exponent: 1.06, pairs: 0)

    var isPersonal: Bool { pairs > 0 }

    /// Exponents for the range: a fitted one is fairly sure; the textbook one could be well off,
    /// mostly on the slow side.
    var range: ClosedRange<Double> { isPersonal ? exponent - 0.01...exponent + 0.01 : 1.05...1.10 }
}

nonisolated struct BacktestRow: Sendable, Identifiable {
    let result: Benchmark
    let predicted: Double

    var id: UUID { result.id }
    var errorPercent: Double { (predicted - result.minutes) / result.minutes * 100 }
}

nonisolated enum Predictor {
    static let standardDistances: [(km: Double, name: String)] =
        [(5, "5k"), (10, "10k"), (21.0975, "Half"), (42.195, "Marathon")]

    /// Riegel's formula: time grows with distance to a power (1.06 for runners trained for the distance).
    static func riegel(minutes: Double, fromKm: Double, toKm: Double, exponent: Double = Endurance.standard.exponent) -> Double {
        minutes * pow(toKm / fromKm, exponent)
    }

    /// The benchmark time scaled by the square root of the mean marker ratio (then / now), so a 4%
    /// fitter aerobic engine is about 2% faster; then Riegel to the target distance. The range uses
    /// the most and least optimistic single marker, and the endurance exponent's range.
    static func predict(_ benchmark: Benchmark, then: [Metric: Double], now: [Metric: Double], toKm: Double? = nil,
                        using metrics: Set<Metric> = Metric.predictionMetrics, endurance: Endurance = .standard) -> Prediction? {
        let ratios = metrics.sorted { $0.rawValue < $1.rawValue }.compactMap { m -> Double? in
            guard let a = then[m], let b = now[m], a > 0, b > 0 else { return nil }
            return a / b
        }
        guard let lo = ratios.min(), let hi = ratios.max() else { return nil }
        let km = toKm ?? benchmark.km
        let scale = { (r: Double, e: Double) in
            riegel(minutes: benchmark.minutes * r.squareRoot(), fromKm: benchmark.km, toKm: km, exponent: e)
        }
        // Going up in distance a bigger exponent is slower; going down it is faster.
        let (eFast, eSlow) = km >= benchmark.km
            ? (endurance.range.lowerBound, endurance.range.upperBound)
            : (endurance.range.upperBound, endurance.range.lowerBound)
        return Prediction(minutes: scale(ratios.reduce(0, +) / Double(ratios.count), endurance.exponent),
                          fastest: scale(lo, eFast), slowest: scale(hi, eSlow), markers: ratios.count,
                          fromKm: benchmark.km, toKm: km, endurance: endurance)
    }
}

nonisolated extension FitnessData {
    /// Prediction for the window ending at `end` (default: now), from fitness before the benchmark.
    func predict(from benchmark: Benchmark, at end: Date? = nil, toKm: Double? = nil,
                 using metrics: Set<Metric> = Metric.predictionMetrics, endurance: Endurance = .standard) -> Prediction? {
        Predictor.predict(benchmark, then: snapshot(at: startOfDay(benchmark.date)), now: snapshot(at: end ?? now),
                          toKm: toKm, using: metrics, endurance: endurance)
    }

    /// Fits the endurance exponent to the athlete's own results: for each pair of results at
    /// distances 1.5x+ apart within a year, the shorter one is first moved to the longer one's date
    /// (so a change in fitness between them isn't mistaken for endurance), then the exponent that
    /// links the two is worked out. The median of those, kept within 1.03-1.20.
    func endurance(from results: [Benchmark], using metrics: Set<Metric> = Metric.predictionMetrics) -> Endurance {
        let sorted = results.sorted { $0.km < $1.km }
        var exponents: [Double] = []
        for (i, short) in sorted.enumerated() {
            for long in sorted[(i + 1)...] where long.km / short.km >= 1.5
                && abs(long.date.timeIntervalSince(short.date)) <= 365 * Self.day {
                let shortThen = predict(from: short, at: startOfDay(long.date), using: metrics)?.minutes ?? short.minutes
                exponents.append(log(long.minutes / shortThen) / log(long.km / short.km))
            }
        }
        guard !exponents.isEmpty else { return .standard }
        let sortedExp = exponents.sorted()
        let n = sortedExp.count
        let median = n % 2 == 1 ? sortedExp[n / 2] : (sortedExp[n / 2 - 1] + sortedExp[n / 2]) / 2
        return Endurance(exponent: min(max(median, 1.03), 1.20), pairs: n)
    }

    /// One prediction (with its likely range) per week from `since` to now.
    func weeklyPredictions(from benchmark: Benchmark, toKm: Double, since: Date,
                           using metrics: Set<Metric> = Metric.predictionMetrics,
                           endurance: Endurance = .standard) -> [(date: Date, prediction: Prediction)] {
        let then = snapshot(at: startOfDay(benchmark.date))
        let at = { (d: Date) in
            Predictor.predict(benchmark, then: then, now: self.snapshot(at: d), toKm: toKm, using: metrics, endurance: endurance)
        }
        var out: [(date: Date, prediction: Prediction)] = []
        var d = startOfDay(since)
        while d <= now {
            if let p = at(d) { out.append((d, p)) }
            d = calendar.date(byAdding: .day, value: 7, to: d)!
        }
        if out.last?.date != now, let p = at(now) { out.append((now, p)) }
        return out
    }

    /// What the model would have predicted for each other result, using only fitness data from
    /// before it, and an endurance exponent fitted without it (so a result can't predict itself).
    func backtest(from benchmark: Benchmark, against results: [Benchmark],
                  using metrics: Set<Metric> = Metric.predictionMetrics) -> [BacktestRow] {
        let then = snapshot(at: startOfDay(benchmark.date))
        return results.filter { $0.id != benchmark.id }.compactMap { r in
            let endurance = endurance(from: results.filter { $0.id != r.id }, using: metrics)
            return Predictor.predict(benchmark, then: then, now: snapshot(at: startOfDay(r.date)), toKm: r.km,
                                     using: metrics, endurance: endurance)
                .map { BacktestRow(result: r, predicted: $0.minutes) }
        }
    }

    /// Hard runs near a distance, converted to it: anything within 8% of that week's prediction.
    func fastEfforts(nearKm km: Double, since: Date, from benchmark: Benchmark,
                     using metrics: Set<Metric> = Metric.predictionMetrics,
                     endurance: Endurance = .standard) -> [(workout: Workout, minutes: Double)] {
        let then = snapshot(at: startOfDay(benchmark.date))
        return workouts.compactMap { w in
            guard w.activity == .running, !w.indoor, w.start >= since, let wkm = w.km,
                  wkm >= km * 0.96, wkm <= km * 1.15 else { return nil }
            let equivalent = Predictor.riegel(minutes: w.minutes, fromKm: wkm, toKm: km, exponent: endurance.exponent)
            let end = calendar.date(byAdding: .day, value: 1, to: startOfDay(w.start))!
            guard let p = Predictor.predict(benchmark, then: then, now: snapshot(at: end), toKm: km,
                                            using: metrics, endurance: endurance),
                  equivalent <= p.minutes * 1.08 else { return nil }
            return (w, equivalent)
        }
    }

    /// The run a result was most likely recorded in: a run on the same day within 10% of the
    /// distance, closest first. Lets results typed in by hand show their route.
    func matchingRun(for result: Benchmark) -> Workout? {
        if let id = result.workoutID, let w = workouts.first(where: { $0.id == id }) { return w }
        let day = startOfDay(result.date)
        return workouts
            .filter { $0.activity == .running && startOfDay($0.start) == day && abs(($0.km ?? 0) / result.km - 1) <= 0.1 }
            .min { abs(($0.km ?? 0) - result.km) < abs(($1.km ?? 0) - result.km) }
    }

    /// Likely races or time trials: the fastest outdoor runs at each standard distance.
    func suggestedResults(perDistance: Int = 3) -> [(workout: Workout, distance: String)] {
        Predictor.standardDistances.flatMap { d in
            workouts
                .filter { $0.activity == .running && !$0.indoor && ($0.km ?? 0) >= d.km * 0.98 && ($0.km ?? 0) <= d.km * 1.06 }
                .sorted { Predictor.riegel(minutes: $0.minutes, fromKm: $0.km!, toKm: d.km) < Predictor.riegel(minutes: $1.minutes, fromKm: $1.km!, toKm: d.km) }
                .prefix(perDistance)
                .map { ($0, d.name) }
        }
    }
}
