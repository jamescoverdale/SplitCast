import Charts
import SwiftData
import SwiftUI

/// Then vs now: the 6 weeks before a past result against the last 6 weeks.
struct CompareView: View {
    let data: FitnessData

    @Query(sort: \RaceResult.date, order: .reverse) private var results: [RaceResult]
    @AppStorage(Setting.compareResult) private var selectedID = ""
    @AppStorage(Setting.units) private var units = Units.miles
    @AppStorage(Setting.excludedMetrics) private var excludedMetrics = ""
    @State private var choosing = false

    private var benchmarks: [Benchmark] {
        results.filter { !$0.notComparable && $0.date < data.now }.map(\.benchmark)
    }

    private var pbIDs: Set<UUID> { Set(Records.personalBests(results.map(\.benchmark)).values.map(\.id)) }

    var body: some View {
        NavigationStack {
            Group {
                if let benchmark = benchmarks.first(where: { $0.id.uuidString == selectedID }) ?? benchmarks.first {
                    content(benchmark)
                        .toolbar {
                            Button("Compare with another result", systemImage: "arrow.up.arrow.down") { choosing = true }
                        }
                        .navigationDestination(isPresented: $choosing) {
                            BenchmarkList(benchmarks: benchmarks, selected: benchmark, data: data, units: units, pbIDs: pbIDs) {
                                selectedID = $0.id.uuidString
                            }
                            .navigationTitle("Compare with")
                        }
                } else {
                    ContentUnavailableView("No results yet", systemImage: "flag.checkered",
                                           description: Text("Add a past race or time trial in Results, then compare your fitness now with your fitness before it."))
                }
            }
            .navigationTitle("Then vs now")
        }
    }

    private func content(_ benchmark: Benchmark) -> some View {
        let thenEnd = data.startOfDay(benchmark.date)
        let then = data.snapshot(at: thenEnd)
        let now = data.snapshot(at: data.now)
        let metrics = Setting.predictionMetrics(excluding: excludedMetrics)
        let shown = Metric.allCases.filter { then[$0] != nil && now[$0] != nil && (!$0.drivesPrediction || metrics.contains($0)) }
        let leftOut = Metric.allCases.filter { !shown.contains($0) }

        return ScrollViewReader { proxy in
            List {
                StaleDataBanner()

                Section {
                    BenchmarkPicker(title: "Then", benchmarks: benchmarks, selected: benchmark, data: data, pbIDs: pbIDs) {
                        selectedID = $0.id.uuidString
                    }
                }

                hero(benchmark, then: then, now: now, metrics: metrics, available: shown.count) {
                    withAnimation { proxy.scrollTo("leftOut", anchor: .top) }
                }

                steadyRuns(thenEnd: thenEnd)

                Section {
                    ForEach(shown.filter(\.drivesPrediction)) { m in
                        NavigationLink {
                            MetricDetailView(data: data, metric: m, benchmark: benchmark)
                        } label: {
                            DriverRow(metric: m, then: then[m]!, now: now[m]!, units: units)
                        }
                    }
                } header: {
                    Heading("What drives it", trailing: AnyView(
                        HStack(spacing: 10) {
                            Label { Text("then") } icon: { Circle().fill(Color.then).frame(width: 8, height: 8) }
                            Label { Text("now") } icon: { Circle().fill(Color.now).frame(width: 8, height: 8) }
                        }
                        .font(.caption).foregroundStyle(.secondary).textCase(nil)
                    ))
                } footer: {
                    Text("Your time then, scaled by how much these have changed.")
                }

                let context = shown.filter { !$0.drivesPrediction }
                if !context.isEmpty {
                    Section {
                        ForEach(context) { m in
                            NavigationLink {
                                MetricDetailView(data: data, metric: m, benchmark: benchmark)
                            } label: {
                                MetricRow(metric: m, then: then[m]!, now: now[m]!, units: units)
                            }
                        }
                    } header: {
                        Heading("Context")
                    }
                }

                if !leftOut.isEmpty {
                    Section {
                        ForEach(leftOut) { m in
                            NavigationLink {
                                MetricDetailView(data: data, metric: m, benchmark: benchmark)
                            } label: {
                                LeftOutRow(metric: m, reason: reason(m, then: then[m], now: now[m], used: metrics),
                                           detail: leftOutDetail(m, then: then[m], thenEnd: thenEnd, used: metrics))
                            }
                        }
                    } header: {
                        Heading("Left out")
                    } footer: {
                        Text("Missing data is left out, never counted as zero. Tap one to see what's missing.")
                    }
                    .id("leftOut")
                }
            }
        }
    }

    // MARK: - Sections

    private func hero(_ benchmark: Benchmark, then: [Metric: Double], now: [Metric: Double], metrics: Set<Metric>,
                      available: Int, showLeftOut: @escaping () -> Void) -> some View {
        let prediction = Predictor.predict(benchmark, then: then, now: now, using: metrics)
        let distance = Predictor.officialDistance(near: benchmark.km)?.name ?? Format.distance(benchmark.km, units)
        return Section {
            if let prediction {
                let gap = Int(((prediction.minutes - benchmark.minutes) * 60).rounded())
                let score = Int((100 * benchmark.minutes / prediction.minutes).rounded())
                VStack(alignment: .leading, spacing: 14) {
                    HeroTime(title: "That \(distance) today", prediction: prediction, km: benchmark.km, units: units,
                             chip: TrendChip(seconds: gap, suffix: gap < 0 ? "faster" : "slower"))
                    NumberLine(markers: [.init(label: "Then", minutes: benchmark.minutes, color: .then, dot: true),
                                         .init(label: "Now", minutes: prediction.minutes, color: .now, dot: true)],
                               range: prediction.fastest...prediction.slowest,
                               gap: gap == 0 ? nil : Format.clock(Double(abs(gap)) / 60))
                    Divider()
                    StatTiles(stats: [
                        Stat(label: "Fitness score", value: "\(score)", suffix: "/100"),
                        Stat(label: "vs then", value: score == 100 ? "Same" : "\(score > 100 ? "+" : "−")\(abs(score - 100))%",
                             color: score > 100 ? .green : score < 100 ? .red : .primary),
                        Stat(label: "Data used", value: "\(available)", suffix: "/\(Metric.allCases.count)",
                             action: available == Metric.allCases.count ? nil : showLeftOut),
                    ])
                }
                .padding(.vertical, 6)
            } else {
                Text("Not enough running data around that date to predict a time.").foregroundStyle(.secondary)
            }
        }
    }

    private func steadyRuns(thenEnd: Date) -> some View {
        let shift = data.heartRateShift(thenEnd: thenEnd, nowEnd: data.now)
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                RunsScatter(data: data, thenEnd: thenEnd, units: units).frame(height: 200)
                if let shift {
                    let bpm = Int(abs(shift).rounded())
                    Text(bpm == 0 ? "At the same pace, your heart is working about as hard as it was."
                         : "At the same pace, your heart is working about \(bpm) bpm \(shift > 0 ? "harder" : "less") than it was.")
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 6)
        } header: {
            Heading("Steady runs", trailing: AnyView(Text("heart rate at each pace").font(.caption).foregroundStyle(.secondary).textCase(nil)))
        }
    }

    /// The shortfall on the side that's missing, e.g. "Then: 1 of 3 steady runs".
    private func leftOutDetail(_ m: Metric, then: Double?, thenEnd: Date, used: Set<Metric>) -> String {
        if m.drivesPrediction && !used.contains(m) { return "Turned off in Results › Prediction markers." }
        let side = then == nil ? ("Then", thenEnd) : ("Now", data.now)
        return "\(side.0): \(data.coverage(m, endingAt: side.1).summary)"
    }

    private func reason(_ m: Metric, then: Double?, now: Double?, used: Set<Metric>) -> String {
        if m.drivesPrediction && !used.contains(m) { return "Turned off" }
        return then == nil && now == nil ? "Not enough data" : then == nil ? "Not enough data then" : "Not enough data now"
    }
}

/// Pace against average HR for the steady runs in both windows.
private struct RunsScatter: View {
    let data: FitnessData
    let thenEnd: Date
    let units: Units

    var body: some View {
        Chart {
            ForEach([("6 weeks before then", thenEnd), ("Last 6 weeks", data.now)], id: \.0) { name, end in
                ForEach(data.steadyRuns(endingAt: end)) { w in
                    PointMark(x: .value("Pace", (w.paceMinPerKm ?? 0) * units.kmPerUnit), y: .value("HR", w.hrAvg ?? 0))
                        .foregroundStyle(by: .value("Window", name))
                }
            }
        }
        .chartForegroundStyleScale(["6 weeks before then": Color.then, "Last 6 weeks": Color.now])
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { if let v = value.as(Double.self) { Text(Format.clock(v)) } }
            }
        }
        .chartXAxisLabel("min/\(units.rawValue)")
        .chartYAxisLabel("bpm")
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXScale(domain: .automatic(includesZero: false))
    }
}
