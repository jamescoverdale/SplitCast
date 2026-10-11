import Charts
import SwiftUI

/// One metric: then and now, what it means, and the 6 weeks before each overlaid.
struct MetricDetailView: View {
    let data: FitnessData
    let metric: Metric
    let benchmark: Benchmark

    @AppStorage(Setting.units) private var units = Units.miles

    var body: some View {
        let thenEnd = data.startOfDay(benchmark.date)
        let thenValue = data.value(metric, at: thenEnd), nowValue = data.value(metric, at: data.now)
        let thenPoints = data.points(metric, endingAt: thenEnd), nowPoints = data.points(metric, endingAt: data.now)
        let beforeLabel = "Before \(benchmark.date.formatted(date: .abbreviated, time: .omitted))"

        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        figure("Then", thenValue, .then)
                        figure("Now", nowValue, .now)
                    }
                    HStack(spacing: 8) {
                        let change = Change(metric, then: thenValue, now: nowValue)
                        if !change.text.isEmpty {
                            Text(change.text).font(.caption.weight(.semibold)).foregroundStyle(change.color)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(change.color.opacity(0.12), in: Capsule())
                        }
                        Text(metric.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(metric.explanation).font(.subheadline)
                }
                .padding(.vertical, 6)
            }

            let missing = thenValue == nil || nowValue == nil
            if missing { dataSection(thenEnd: thenEnd, missing: true) }

            if !thenPoints.isEmpty || !nowPoints.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Chart {
                            ForEach([(beforeLabel, thenPoints), ("Last 6 weeks", nowPoints)], id: \.0) { name, points in
                                ForEach(points, id: \.self) { p in
                                    let y = Format.chartValue(metric, p.value, units)
                                    if metric.chartStyle == .line {
                                        LineMark(x: .value("Days before", p.x), y: .value(metric.title, y), series: .value("Window", name))
                                            .foregroundStyle(by: .value("Window", name))
                                    } else {
                                        PointMark(x: .value("Days before", p.x), y: .value(metric.title, y))
                                            .foregroundStyle(by: .value("Window", name))
                                    }
                                }
                            }
                        }
                        .chartForegroundStyleScale([beforeLabel: Color.then, "Last 6 weeks": Color.now])
                        .chartXScale(domain: -FitnessData.window...0)
                        .chartXAxis {
                            AxisMarks(values: [-42, -21, 0]) { value in
                                AxisGridLine()
                                AxisValueLabel {
                                    if let d = value.as(Double.self) { Text(d == 0 ? "race / today" : "\(Int(-d / 7)) wk before") }
                                }
                            }
                        }
                        .chartYAxisLabel(Format.chartUnit(metric, units))
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 230)

                        if metric.describesTrend, let sentence = trendSentence(then: Trend.of(thenPoints), now: Trend.of(nowPoints)) {
                            Text(sentence).font(.subheadline)
                        }
                    }
                    .padding(.vertical, 6)
                } header: {
                    Heading("The 6 weeks before")
                } footer: {
                    if let note = metric.note { Text(note) }
                }
            }
            if !missing { dataSection(thenEnd: thenEnd, missing: false) }
        }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// What each window has against what the metric needs. Shown first when something's missing,
    /// otherwise lower down for anyone curious.
    private func dataSection(thenEnd: Date, missing: Bool) -> some View {
        Section {
            ForEach([("Then", thenEnd, Color.then), ("Now", data.now, Color.now)], id: \.0) { label, end, color in
                let c = data.coverage(metric, endingAt: end)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(color)
                        Spacer()
                        Label(c.isEnough ? "Enough" : "Not enough", systemImage: c.isEnough ? "checkmark.circle.fill" : "xmark.circle")
                            .font(.caption).foregroundStyle(c.isEnough ? .green : .secondary)
                    }
                    ProgressView(value: Double(min(c.have, c.need)), total: Double(max(c.need, 1))).tint(color)
                    Text(c.summary).font(.subheadline).monospacedDigit()
                    if let detail = c.detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Heading("Data")
        } footer: {
            Text([metric.requirement, missing ? metric.dataTip : nil].compactMap { $0 }.joined(separator: " "))
        }
    }

    private func figure(_ label: String, _ value: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(value.map { Format.metric(metric, $0, units) } ?? "No data")
                .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trendSentence(then: Trend?, now: Trend?) -> String? {
        let past: [Trend: String] = [.rising: "climbed", .falling: "dropped", .flat: "held steady"]
        let recent: [Trend: String] = [.rising: "been rising", .falling: "been falling", .flat: "been flat"]
        switch (then, now) {
        case let (t?, n?): return "Then, it \(past[t]!) into the race. Lately it's \(recent[n]!)."
        case let (t?, nil): return "Then, it \(past[t]!) into the race."
        case let (nil, n?): return "Lately it's \(recent[n]!)."
        default: return nil
        }
    }
}
