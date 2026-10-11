import Charts
import SwiftData
import SwiftUI

/// Predicted time for a distance, how it's moving, and what a goal would take.
struct GoalView: View {
    let data: FitnessData

    @AppStorage(Setting.goalKm) private var km = 5.0
    @State private var editingGoal = false

    var body: some View {
        NavigationStack {
            List {
                Picker("Distance", selection: $km) {
                    ForEach(Predictor.standardDistances, id: \.km) { Text($0.name).tag($0.km) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                StaleDataBanner()
                GoalDistanceSections(data: data, km: km) { editingGoal = true }.id(km)
            }
            .navigationTitle("Goal")
            .toolbar {
                Button("Edit goal", systemImage: "pencil") { editingGoal = true }
            }
            .sheet(isPresented: $editingGoal) { GoalEditor(data: data, km: $km) }
        }
    }
}

/// Everything for one distance, so the goal and the result predicted from are kept per distance.
private struct GoalDistanceSections: View {
    let data: FitnessData
    let km: Double
    let editGoal: () -> Void

    @Query(sort: \RaceResult.date, order: .reverse) private var results: [RaceResult]
    @AppStorage private var goalText: String
    @AppStorage private var benchmarkID: String
    @AppStorage(Setting.goalYears) private var years = 1
    @AppStorage(Setting.units) private var units = Units.miles
    @AppStorage(Setting.excludedMetrics) private var excludedMetrics = ""
    @State private var addingResult: ResultDraft?

    init(data: FitnessData, km: Double, editGoal: @escaping () -> Void) {
        self.data = data
        self.km = km
        self.editGoal = editGoal
        _goalText = AppStorage(wrappedValue: "", Setting.goalTime(km))
        _benchmarkID = AppStorage(wrappedValue: "", Setting.goalBenchmark(km))
    }

    private var name: String { Predictor.standardDistances.first { $0.km == km }?.name ?? "race" }
    private var shortName: String { name == "Half" || name == "Marathon" ? name.lowercased() : name }

    private var benchmarks: [Benchmark] {
        results.filter { !$0.notComparable && $0.date < data.now }.map(\.benchmark)
    }

    /// The chosen result, else the one at the closest distance (most recent first), else (with
    /// no results at all) the best mile in recent runs.
    private var benchmark: Benchmark? {
        benchmarks.first { $0.id.uuidString == benchmarkID }
            ?? benchmarks.min { abs(log($0.km / km)) < abs(log($1.km / km)) }
            ?? data.bestMileBenchmark()?.benchmark
    }

    var body: some View {
        let metrics = Setting.predictionMetrics(excluding: excludedMetrics)
        let endurance = data.endurance(from: benchmarks, using: metrics)
        let goal = Format.parseClock(goalText)

        if let benchmark, let now = data.predict(from: benchmark, toKm: km, using: metrics, endurance: endurance) {
            let rows = data.backtest(from: benchmark, against: benchmarks, using: metrics)
            hero(now, benchmark: benchmark, goal: goal, accuracy: Accuracy(rows), metrics: metrics, endurance: endurance)

            Section {
                PredictionChart(data: data, benchmark: benchmark, km: km, years: years, goal: goal,
                                results: results.map(\.benchmark), metrics: metrics, endurance: endurance)
                    .frame(height: 230)
                    .padding(.vertical, 6)
            } header: {
                Heading("Over time", trailing: AnyView(
                    Picker("Range", selection: $years) {
                        Text("1Y").tag(1)
                        Text("2Y").tag(2)
                        Text("5Y").tag(5)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                ))
            }

            if let goal, Predictor.fitnessNeeded(predicted: now.minutes, goal: goal) > 0.001 {
                closesTheGap(now: now, goal: goal, metrics: metrics)
            }

            if benchmarks.isEmpty {
                fromBestMile(benchmark)
            } else {
                Section {
                    BenchmarkPicker(title: "Predicting from", benchmarks: benchmarks, selected: benchmark, data: data,
                                    pbIDs: Set(Records.personalBests(results.map(\.benchmark)).values.map(\.id))) {
                        benchmarkID = $0.id.uuidString
                    }
                }
            }

            howGood(rows, now: now, benchmark: benchmark)
        } else if benchmarks.isEmpty {
            noResults(goal: goal)
        } else {
            Section {
                Text("Not enough running data around your results to predict yet. Steady runs with heart rate in the 6 weeks before a race are what it needs.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Sections

    private func hero(_ now: Prediction, benchmark: Benchmark, goal: Double?, accuracy: Accuracy?,
                      metrics: Set<Metric>, endurance: Endurance) -> some View {
        let earlier = data.calendar.date(byAdding: .day, value: -42, to: data.now)!
        let before = data.predict(from: benchmark, at: earlier, toKm: km, using: metrics, endurance: endurance)
        let chip = before.map { TrendChip(seconds: Int(((now.minutes - $0.minutes) * 60).rounded()), suffix: "in 6 weeks") }
        let best = Records.personalBests(results.map(\.benchmark))[km]
        var markers: [NumberLine.Marker] = []
        if let goal { markers.append(.init(label: "Goal", minutes: goal, color: .goal)) }
        if let best { markers.append(.init(label: "Best", minutes: best.minutes, color: .then, below: true)) }
        markers.append(.init(label: "Now", minutes: now.minutes, color: .now, dot: true))
        let needed = goal.map { Predictor.fitnessNeeded(predicted: now.minutes, goal: $0) }

        return Section {
            VStack(alignment: .leading, spacing: 14) {
                HeroTime(title: "Predicted \(shortName) today", prediction: now, km: km, units: units, chip: chip)
                if now.isLongStretch {
                    Label(stretchNote(benchmark, endurance), systemImage: endurance.isPersonal ? "info.circle" : "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                NumberLine(markers: markers, range: now.fastest...now.slowest)
                Divider()
                StatTiles(stats: [
                    Stat(label: "To goal", value: goal.map { $0 < now.minutes ? Format.clock(now.minutes - $0) : "There" } ?? "–",
                         color: goal.map { $0 < now.minutes ? Color.primary : Color.green } ?? .primary),
                    Stat(label: "Needs", value: needed.map { $0 > 0.001 ? "\(Int(($0 * 100).rounded()))%" : "0%" } ?? "–",
                         suffix: needed.map { $0 > 0.001 ? "fitter" : nil } ?? nil),
                    Stat(label: "Accuracy", value: accuracy.flatMap { $0.isReliable ? "±\(Int($0.meanPercent.rounded()))%" : nil } ?? "–"),
                ])
                if goal == nil {
                    Button("Set a goal", systemImage: "target", action: editGoal).font(.subheadline)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func closesTheGap(now: Prediction, goal: Double, metrics: Set<Metric>) -> some View {
        let needed = Predictor.fitnessNeeded(predicted: now.minutes, goal: goal)
        let current = data.snapshot(at: data.now)
        return Section {
            Text("\(Format.clock(goal)) needs about \(Int((needed * 100).rounded()))% more aerobic fitness than you have now. Roughly, these would need to reach:")
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(Metric.allCases.filter { metrics.contains($0) && current[$0] != nil }) { m in
                HStack {
                    Label(m.title, systemImage: m.symbol)
                    Spacer()
                    Text("\(Text(Format.metric(m, current[m]!, units)).foregroundStyle(.secondary)) → \(Text(Format.metric(m, current[m]! * (1 + needed), units)).bold().foregroundStyle(Color.now))")
                        .font(.subheadline).monospacedDigit()
                }
            }
        } header: {
            Heading("What closes the gap")
        } footer: {
            Text("The prediction follows the average of these, so a bigger gain in one makes up for less in another.")
        }
    }

    private func howGood(_ rows: [BacktestRow], now: Prediction, benchmark: Benchmark) -> some View {
        let accuracy = Accuracy(rows)
        return Section {
            NavigationLink {
                BacktestList(rows: rows, benchmark: benchmark)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("How good is this?").font(.headline)
                    if let accuracy, accuracy.isReliable {
                        let seconds = accuracy.meanPercent / 100 * now.minutes
                        Text("On your last \(accuracy.count) races it was off by \(Int(accuracy.meanPercent.rounded()))% on average, about ±\(seconds < 1 ? "\(Int((seconds * 60).rounded())) s" : Format.clock(seconds)) on a \(shortName).")
                            .font(.subheadline).foregroundStyle(.secondary)
                        ErrorStrip(rows: rows, accuracy: accuracy)
                    } else {
                        let missing = Accuracy.minimumResults - (accuracy?.count ?? 0)
                        Text("Add \(missing) more race\(missing == 1 ? "" : "s") to see how accurate predictions are for you.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .disabled(rows.isEmpty)
        }
    }

    /// No results yet, so the prediction comes from the fastest mile in recent runs.
    private func fromBestMile(_ benchmark: Benchmark) -> some View {
        Section {
            ResultRow(result: benchmark, data: data, units: units)
            Text("Rough estimate from your fastest mile in the last 8 weeks. Add a race or time trial for a much better prediction.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Add a result", systemImage: "plus") { addingResult = ResultDraft() }
        } header: {
            Heading("Predicting from")
        }
        .sheet(item: $addingResult) { ResultEditor(draft: $0) }
    }

    @ViewBuilder
    private func noResults(goal: Double?) -> some View {
        Section {
            VStack(spacing: 12) {
                Image("AboutIcon").resizable().frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityHidden(true)
                Text("Nothing to predict from yet").font(.title3.bold())
                Text("Predictions start from one real result: a race, parkrun or hard solo effort. One is enough.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button { addingResult = ResultDraft() } label: {
                    Text("Add a result").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Text("Or pick one of your fast runs in Results.").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .sheet(item: $addingResult) { ResultEditor(draft: $0) }

        Section {
            LabeledContent("Distance", value: name)
            Button(action: editGoal) {
                LabeledContent("Goal time", value: goal.map(Format.clock) ?? "Set")
            }
            .tint(.primary)
        } header: {
            Heading("Set a goal anyway")
        } footer: {
            Text("We'll show how close you are as soon as there's a result.")
        }
    }

    private func stretchNote(_ benchmark: Benchmark, _ endurance: Endurance) -> String {
        if endurance.isPersonal {
            return "Predicted from \(benchmark.name) using how much you slow down over longer races, worked out from \(endurance.pairs) pairs of your results."
        }
        return "Rough estimate: a \(shortName) predicted from \(benchmark.name). Add results at two distances so Splitcast can learn how you slow down over longer races."
    }
}

/// Predicted against actual for each past result.
private struct BacktestList: View {
    let rows: [BacktestRow]
    let benchmark: Benchmark

    var body: some View {
        List {
            Section {
                ForEach(rows) { row in
                    LabeledContent {
                        VStack(alignment: .trailing) {
                            Text("\(Format.clock(row.predicted)) vs \(Format.clock(row.result.minutes))").monospacedDigit()
                            Text(row.errorPercent < 0 ? String(format: "ran %.1f%% slower", -row.errorPercent) : String(format: "ran %.1f%% faster", row.errorPercent))
                                .font(.caption)
                                .foregroundStyle(abs(row.errorPercent) <= 2 ? .green : abs(row.errorPercent) <= 5 ? .secondary : .red)
                        }
                    } label: {
                        Text(row.result.name)
                        Text(row.result.date.monthYear)
                    }
                }
            } footer: {
                Text("What \(benchmark.name) would have predicted for each of your other results, using only data from before it. Predictions assume a flat course, so hilly races come out optimistic.")
            }
        }
        .navigationTitle("How good is this?")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PredictionChart: View {
    let data: FitnessData
    let benchmark: Benchmark
    let km: Double
    let years: Int
    let goal: Double?
    let results: [Benchmark]
    let metrics: Set<Metric>
    let endurance: Endurance

    var body: some View {
        let since = data.calendar.date(byAdding: .year, value: -years, to: data.now)!
        let weekly = data.weeklyPredictions(from: benchmark, toKm: km, since: since, using: metrics, endurance: endurance)
        let efforts = data.fastEfforts(nearKm: km, since: since, from: benchmark, using: metrics, endurance: endurance)
        let races = results.filter { $0.date >= since && abs(log($0.km / km)) < 0.1 }

        Chart {
            ForEach(weekly, id: \.date) { w in
                AreaMark(x: .value("Date", w.date), yStart: .value("Fastest", w.prediction.fastest), yEnd: .value("Slowest", w.prediction.slowest))
                    .foregroundStyle(by: .value("Series", "Likely range"))
            }
            ForEach(weekly, id: \.date) { w in
                LineMark(x: .value("Date", w.date), y: .value("Time", w.prediction.minutes), series: .value("Series", "Predicted"))
                    .foregroundStyle(by: .value("Series", "Predicted"))
                    .interpolationMethod(.monotone)
            }
            ForEach(efforts, id: \.workout.id) { e in
                PointMark(x: .value("Date", e.workout.start), y: .value("Time", e.minutes))
                    .foregroundStyle(by: .value("Series", "Fast run"))
                    .symbol(.circle)
            }
            ForEach(races) { r in
                PointMark(x: .value("Date", r.date), y: .value("Time", Predictor.riegel(minutes: r.minutes, fromKm: r.km, toKm: km, exponent: endurance.exponent)))
                    .foregroundStyle(by: .value("Series", "Race"))
                    .symbol(.diamond)
            }
            if let goal {
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(Color.goal)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 4]))
                    .annotation(position: .bottom, alignment: .leading) {
                        Text("Goal \(Format.clock(goal))").font(.caption2.weight(.semibold)).foregroundStyle(Color.goal)
                    }
            }
        }
        .chartForegroundStyleScale(["Predicted": Color.now, "Likely range": Color.now.opacity(0.18),
                                    "Fast run": Color.secondary, "Race": Color.primary])
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { if let v = value.as(Double.self) { Text(Format.clock(v)) } }
            }
        }
    }
}
