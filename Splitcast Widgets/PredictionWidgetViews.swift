import Charts
import SwiftUI
import WidgetKit

private let thenColor = Color.orange
private let nowColor = Color.blue
private let goalColor = Color.green

struct PredictionWidgetView: View {
    let entry: PredictionEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let s = entry.snapshot {
            content(s)
        } else {
            setUp
        }
    }

    @ViewBuilder
    private func content(_ s: WidgetSnapshot) -> some View {
        switch family {
        case .accessoryInline:
            Text(s.goal.map { "\(s.distance) \(WidgetSnapshot.clock(s.predicted)) · goal \(WidgetSnapshot.clock($0))" }
                 ?? "\(s.distance) predicted \(WidgetSnapshot.clock(s.predicted))")
        case .accessoryCircular:
            Gauge(value: s.goal == nil ? 1 : s.progress) {
                Text(s.distance)
            } currentValueLabel: {
                Text(WidgetSnapshot.clock(s.predicted)).minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .containerBackground(.clear, for: .widget)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(s.goalTitle.uppercased()).font(.caption2.weight(.semibold))
                Text(toGoText(s) ?? WidgetSnapshot.clock(s.predicted)).font(.headline).monospacedDigit()
                if s.goal != nil { ProgressView(value: s.progress) } else { trend(s) }
            }
            .containerBackground(.clear, for: .widget)
        case .systemMedium:
            medium(s)
        case .systemLarge:
            large(s)
        default:
            small(s)
        }
    }

    // MARK: - Home screen

    @ViewBuilder
    private func small(_ s: WidgetSnapshot) -> some View {
        if s.isStale(now: entry.date) {
            VStack(alignment: .leading, spacing: 6) {
                caption("\(s.distance) · \(s.ageInDays(now: entry.date)) days old")
                bigTime(s.predicted).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text("Open Splitcast to refresh from Health").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(.fill.tertiary, for: .widget)
        } else if s.goalReached {
            VStack(alignment: .leading, spacing: 4) {
                caption(s.goalTitle).foregroundStyle(.white.opacity(0.85))
                Image(systemName: "checkmark").font(.title2.weight(.bold))
                Spacer(minLength: 0)
                Text("Goal within reach").font(.headline)
                Text("Predicted \(WidgetSnapshot.clock(s.predicted))").font(.caption).monospacedDigit()
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(goalColor.gradient, for: .widget)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    caption(s.distance)
                    Spacer()
                    if let goal = s.goal { caption("Goal \(WidgetSnapshot.clock(goal))").foregroundStyle(goalColor) }
                }
                bigTime(s.predicted)
                Text(toGoText(s) ?? "likely \(WidgetSnapshot.clock(s.fastest))–\(WidgetSnapshot.clock(s.slowest))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer(minLength: 0)
                if s.goal != nil { MiniLine(snapshot: s).frame(height: 14) }
                trend(s)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    private func medium(_ s: WidgetSnapshot) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                caption("\(s.distance) today")
                bigTime(s.predicted)
                Text("\(WidgetSnapshot.clock(s.fastest))–\(WidgetSnapshot.clock(s.slowest))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer(minLength: 0)
                if let goal = s.goal {
                    Text(s.goalReached ? "Within reach of \(WidgetSnapshot.clock(goal))" : "\(WidgetSnapshot.clock(s.toGo!)) to \(WidgetSnapshot.clock(goal))")
                        .font(.caption.weight(.semibold)).monospacedDigit()
                }
                trend(s)
            }
            HistoryChart(snapshot: s)
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func large(_ s: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                caption("Predicted \(s.distance)")
                Spacer()
                trend(s)
            }
            bigTime(s.predicted, size: 52)
            Text("\(s.pace) · likely \(WidgetSnapshot.clock(s.fastest))–\(WidgetSnapshot.clock(s.slowest))")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if s.goal != nil || s.best != nil { MiniLine(snapshot: s, labelled: true).frame(height: 34) }
            HistoryChart(snapshot: s)
            Divider()
            HStack {
                stat("To goal", s.toGo.map { $0 > 0 ? WidgetSnapshot.clock($0) : "There" } ?? "–")
                stat("Needs", s.needsPercent.map { $0 > 0.1 ? "\(Int($0.rounded()))% fitter" : "0%" } ?? "–")
                stat("Accuracy", s.accuracyPercent.map { "±\(Int($0.rounded()))%" } ?? "–")
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Pieces

    private var setUp: some View {
        VStack(alignment: .leading, spacing: 6) {
            caption("Splitcast")
            Spacer(minLength: 0)
            Text("Add a race in Splitcast to see your predicted time.").font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func caption(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(nowColor)
    }

    private func bigTime(_ minutes: Double, size: CGFloat = 36) -> some View {
        Text(WidgetSnapshot.clock(minutes))
            .font(.system(size: size, weight: .bold, design: .rounded)).monospacedDigit()
            .minimumScaleFactor(0.6).lineLimit(1)
    }

    private func toGoText(_ s: WidgetSnapshot) -> String? {
        guard let toGo = s.toGo else { return nil }
        return toGo > 0 ? "\(WidgetSnapshot.clock(toGo)) to go" : "Goal within reach"
    }

    @ViewBuilder
    private func trend(_ s: WidgetSnapshot) -> some View {
        if let change = s.changeSixWeeks {
            let seconds = Int((change * 60).rounded())
            Text(seconds == 0 ? "No change in 6 weeks" : "\(seconds < 0 ? "▼" : "▲") \(WidgetSnapshot.clock(Double(abs(seconds)) / 60)) in 6 weeks")
                .font(.caption2.weight(.semibold)).monospacedDigit()
                .foregroundStyle(seconds < 0 ? Color.green : seconds > 0 ? Color.red : Color.secondary)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Goal, best and now on one line, faster to the left.
private struct MiniLine: View {
    let snapshot: WidgetSnapshot
    var labelled = false

    var body: some View {
        GeometryReader { geo in
            let values = [snapshot.goal, snapshot.best, snapshot.predicted, snapshot.fastest, snapshot.slowest].compactMap { $0 }
            let lo = values.min()!, hi = values.max()!
            let pad = max((hi - lo) * 0.1, 0.05)
            let x = { (v: Double) in geo.size.width * (v - (lo - pad)) / ((hi + pad) - (lo - pad)) }
            let mid = labelled ? geo.size.height - 7 : geo.size.height / 2
            ZStack {
                Capsule().fill(.quaternary).frame(width: geo.size.width, height: 3).position(x: geo.size.width / 2, y: mid)
                Capsule().fill(nowColor.opacity(0.25))
                    .frame(width: max(x(snapshot.slowest) - x(snapshot.fastest), 6), height: 8)
                    .position(x: (x(snapshot.fastest) + x(snapshot.slowest)) / 2, y: mid)
                ForEach([(snapshot.goal, goalColor, "Goal"), (snapshot.best, thenColor, "Best")], id: \.2) { value, color, label in
                    if let value {
                        Capsule().fill(color).frame(width: 2, height: 12).position(x: x(value), y: mid)
                        if labelled {
                            Text("\(label) \(WidgetSnapshot.clock(value))").font(.caption2.weight(.semibold)).foregroundStyle(color)
                                .fixedSize().position(x: min(max(x(value), 34), geo.size.width - 34), y: mid - 16)
                        }
                    }
                }
                Circle().fill(nowColor).frame(width: 9, height: 9).position(x: x(snapshot.predicted), y: mid)
            }
        }
    }
}

/// The weekly prediction over the last year, with the goal as a dashed line.
private struct HistoryChart: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        Chart {
            ForEach(snapshot.history, id: \.self) { p in
                LineMark(x: .value("Date", p.date), y: .value("Time", p.minutes))
                    .foregroundStyle(nowColor)
                    .interpolationMethod(.monotone)
            }
            if let goal = snapshot.goal {
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(goalColor)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}
