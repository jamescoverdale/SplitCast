import SwiftUI

extension Color {
    static let then = Color.orange
    static let now = Color.blue
    static let goal = Color.green
}

extension Date {
    var monthYear: String { formatted(.dateTime.month(.abbreviated).year()) }
}

/// How a metric moved between two windows, worded and coloured for the list.
struct Change {
    let text: String
    let color: Color

    init(_ metric: Metric, then: Double?, now: Double?) {
        guard let then, let now else {
            text = ""
            color = .secondary
            return
        }
        if metric == .form {
            let d = now - then
            text = abs(d) < 1 ? "≈" : d < 0 ? "more tired" : "fresher"
            color = .secondary
            return
        }
        let pct = (now - then) / then * 100
        if abs(pct) < 1 {
            text = "≈"
            color = .secondary
        } else {
            text = "\(pct > 0 ? "▲" : "▼")\(String(format: "%.0f", abs(pct)))%"
            color = (metric.lowerIsBetter ? pct < 0 : pct > 0) ? .green : .red
        }
    }
}

/// "▼ 0:06 in 6 weeks": a change in a time, green when faster.
struct TrendChip: View {
    let seconds: Int
    let suffix: String

    var body: some View {
        let faster = seconds < 0
        Text(seconds == 0 ? "No change \(suffix)" : "\(faster ? "▼" : "▲") \(Format.clock(Double(abs(seconds)) / 60)) \(suffix)")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(seconds == 0 ? Color.secondary : faster ? Color.green : Color.red)
            .background((seconds == 0 ? Color.secondary : faster ? Color.green : Color.red).opacity(0.12), in: Capsule())
    }
}

/// The headline time: label and chip, the big number, then pace and likely range.
struct HeroTime: View {
    let title: String
    let prediction: Prediction
    let km: Double
    let units: Units
    var chip: TrendChip?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                chip
            }
            Text(Format.clock(prediction.minutes))
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
            Text("\(Format.pace(prediction.minutes / km, units)) · likely between \(Format.clock(prediction.fastest)) and \(Format.clock(prediction.slowest))")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

/// Times on a line, faster to the left: e.g. goal, best and now, with now's likely range shaded.
struct NumberLine: View {
    struct Marker: Identifiable {
        let label: String
        let minutes: Double
        let color: Color
        var dot = false
        var below = false
        var id: String { label }
    }

    let markers: [Marker]
    var range: ClosedRange<Double>?
    /// Written under the line, midway between the outermost markers (e.g. "0:37").
    var gap: String?

    var body: some View {
        GeometryReader { geo in
            let values = markers.map(\.minutes) + [range?.lowerBound, range?.upperBound].compactMap { $0 }
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            let pad = max((hi - lo) * 0.12, 0.1)
            let x = { (v: Double) in geo.size.width * (v - (lo - pad)) / ((hi + pad) - (lo - pad)) }
            let align = labelAlignments(x)
            // Labels sit in a fixed-width box; keep the box inside the card.
            let labelX = { (m: Marker) -> CGFloat in
                let half = Self.labelWidth / 2
                let center = switch align[m.id] ?? .center {
                case .trailing: x(m.minutes) + 6 - half
                case .leading: x(m.minutes) - 6 + half
                default: x(m.minutes)
                }
                return min(max(center, half), geo.size.width - half)
            }
            let mid = geo.size.height / 2
            ZStack {
                Capsule().fill(.quaternary).frame(width: geo.size.width, height: 4).position(x: geo.size.width / 2, y: mid)
                if let range {
                    Capsule().fill(Color.now.opacity(0.2))
                        .frame(width: max(x(range.upperBound) - x(range.lowerBound), 8), height: 12)
                        .position(x: (x(range.lowerBound) + x(range.upperBound)) / 2, y: mid)
                }
                if let first = markers.map(\.minutes).min(), let last = markers.map(\.minutes).max() {
                    Path { p in
                        p.move(to: CGPoint(x: x(first), y: mid))
                        p.addLine(to: CGPoint(x: x(last), y: mid))
                    }
                    .stroke(.secondary.opacity(0.6), lineWidth: 2)
                    if let gap {
                        Text(gap).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                            .fixedSize()
                            .position(x: (x(first) + x(last)) / 2, y: mid + 18)
                    }
                }
                ForEach(markers) { m in
                    if m.dot {
                        Circle().fill(m.color).frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.background, lineWidth: 2))
                            .position(x: x(m.minutes), y: mid)
                    } else {
                        Capsule().fill(m.color).frame(width: 3, height: 22).position(x: x(m.minutes), y: mid)
                    }
                    Text("\(m.label) \(Format.clock(m.minutes))")
                        .font(.caption2.weight(.semibold)).foregroundStyle(m.color).monospacedDigit()
                        .fixedSize()
                        .frame(width: Self.labelWidth, alignment: Alignment(horizontal: align[m.id] ?? .center, vertical: .center))
                        .position(x: labelX(m), y: m.below ? mid + 22 : mid - 22)
                }
            }
        }
        .frame(height: 74)
        .overlay(alignment: .bottomTrailing) {
            if range != nil {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.now.opacity(0.2)).frame(width: 14, height: 8)
                    Text("likely range")
                }
                .font(.caption2).foregroundStyle(.secondary)
                .offset(y: 14)
            }
        }
        .padding(.bottom, range == nil ? 0 : 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(markers.map { "\($0.label) \(Format.clock($0.minutes))" }.joined(separator: ", "))
    }

    private static let labelWidth: CGFloat = 150
    /// Closer than this, two labels on the same side would overlap if both were centred.
    private static let crowded: CGFloat = 100

    /// Each label is centred on its marker, unless a neighbour on the same side of the line is too
    /// close: then the left label ends at its marker and the right one starts at its marker.
    private func labelAlignments(_ x: (Double) -> Double) -> [String: HorizontalAlignment] {
        var out: [String: HorizontalAlignment] = [:]
        for below in [false, true] {
            let side = markers.filter { $0.below == below }.sorted { $0.minutes < $1.minutes }
            for (left, right) in zip(side, side.dropFirst()) where x(right.minutes) - x(left.minutes) < Self.crowded {
                out[left.id] = .trailing
                out[right.id] = .leading
            }
        }
        return out
    }
}

/// One figure under a headline: value on top, label below; optionally tappable.
struct Stat: Identifiable {
    let label: String
    let value: String
    var suffix: String? = nil
    var color: Color = .primary
    var action: (() -> Void)? = nil

    var id: String { label }
}

/// Up to three figures side by side in equal columns, split by thin dividers.
struct StatTiles: View {
    let stats: [Stat]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stats.enumerated()), id: \.element.id) { i, stat in
                if i > 0 { Divider().frame(height: 40) }
                tile(stat)
            }
        }
    }

    @ViewBuilder
    private func tile(_ stat: Stat) -> some View {
        let content = VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(stat.value).font(.title3.weight(.semibold)).foregroundStyle(stat.color).monospacedDigit()
                if let suffix = stat.suffix { Text(suffix).font(.caption).foregroundStyle(.secondary) }
            }
            HStack(spacing: 3) {
                Text(stat.label)
                if stat.action != nil { Image(systemName: "chevron.right").imageScale(.small) }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        if let action = stat.action {
            Button(action: action) { content }.buttonStyle(.plain)
        } else {
            content
        }
    }
}

/// Then and now as two dots on a short track.
struct MarkerDotPlot: View {
    let then: Double
    let now: Double

    var body: some View {
        GeometryReader { geo in
            let center = (then + now) / 2
            let half = max(abs(then - now) * 0.8, abs(center) * 0.04, 0.0001)
            let x = { (v: Double) in geo.size.width * (0.5 + (v - center) / (2 * half)) }
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 3)
                Path { p in
                    p.move(to: CGPoint(x: x(then), y: 5))
                    p.addLine(to: CGPoint(x: x(now), y: 5))
                }
                .stroke(.secondary.opacity(0.5), lineWidth: 2)
                Circle().fill(Color.then).frame(width: 10, height: 10).offset(x: x(then) - 5)
                Circle().fill(Color.now).frame(width: 10, height: 10).offset(x: x(now) - 5)
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

/// Backtest errors as dots from "ran slower" (left) to "ran faster" (right).
struct ErrorStrip: View {
    let rows: [BacktestRow]
    let accuracy: Accuracy

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let limit = max(10, rows.map { abs($0.errorPercent) }.max() ?? 10)
                let x = { (pct: Double) in geo.size.width * (0.5 - pct / (2 * limit)) }
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 3)
                    Capsule().fill(Color.now.opacity(0.15))
                        .frame(width: x(-accuracy.meanPercent) - x(accuracy.meanPercent), height: 12)
                        .offset(x: x(accuracy.meanPercent))
                    Rectangle().fill(.secondary).frame(width: 1, height: 16).offset(x: geo.size.width / 2)
                    ForEach(rows) { r in
                        Circle().fill(Color.now).frame(width: 9, height: 9).offset(x: x(r.errorPercent) - 4.5)
                    }
                }
            }
            .frame(height: 16)
            HStack {
                Text("Ran slower")
                Spacer()
                Text("Spot on")
                Spacer()
                Text("Ran faster")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Past predictions were off by \(String(format: "%.0f", accuracy.meanPercent))% on average")
    }
}

/// A metric row: icon and name on the left; today's value, with "was … · change" under it, on
/// the right so values line up down the list.
struct MetricRow: View {
    let metric: Metric
    let then: Double
    let now: Double
    let units: Units

    var body: some View {
        let change = Change(metric, then: then, now: now)
        HStack {
            Label(metric.title, systemImage: metric.symbol)
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.metric(metric, now, units)).fontWeight(.semibold).monospacedDigit()
                Text("was \(Format.metric(metric, then, units))\(change.text.isEmpty ? "" : " · ")\(Text(change.text).foregroundStyle(change.color))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

/// A prediction marker: the metric row plus a then/now dot plot.
struct DriverRow: View {
    let metric: Metric
    let then: Double
    let now: Double
    let units: Units

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MetricRow(metric: metric, then: then, now: now, units: units)
            MarkerDotPlot(then: then, now: now).padding(.leading, 38)
        }
        .padding(.vertical, 4)
    }
}

/// A metric that was left out, and why.
struct LeftOutRow: View {
    let metric: Metric
    let reason: String
    let detail: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(metric.title)
                    Spacer()
                    Text(reason).font(.caption)
                }
                Text(detail).font(.caption)
            }
        } icon: {
            Image(systemName: metric.symbol)
        }
        .foregroundStyle(.secondary)
    }
}

/// Bold section headings, as in the design.
struct Heading: View {
    let title: String
    var trailing: AnyView?

    init(_ title: String, trailing: AnyView? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title).font(.title3.bold()).foregroundStyle(.primary).textCase(nil)
            Spacer()
            trailing
        }
    }
}

/// A finishing time picked on wheels. Tap to open the wheels; `large` shows the time big.
struct DurationField: View {
    let title: String
    @Binding var minutes: Double
    var showsHours = true
    var large = false

    @State private var expanded = false

    var body: some View {
        Button {
            withAnimation { expanded.toggle() }
        } label: {
            if large {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline).foregroundStyle(.secondary)
                    Text(minutes > 0 ? Format.clock(minutes) : "Set a time")
                        .font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(expanded ? Color.accentColor : .primary)
                }
            } else {
                LabeledContent(title) {
                    Text(minutes > 0 ? Format.clock(minutes) : "Set")
                        .monospacedDigit()
                        .foregroundStyle(expanded ? Color.accentColor : .secondary)
                }
            }
        }
        .tint(.primary)
        if expanded {
            DurationWheels(minutes: $minutes, showsHours: showsHours)
        }
    }
}

struct DurationWheels: View {
    @Binding var minutes: Double
    let showsHours: Bool

    private var total: Int { Int((minutes * 60).rounded()) }

    var body: some View {
        HStack(spacing: 0) {
            if showsHours { wheel(0..<10, "h", total / 3600) { set(h: $0) } }
            wheel(0..<60, "min", total % 3600 / 60) { set(m: $0) }
            wheel(0..<60, "sec", total % 60) { set(s: $0) }
        }
        .frame(height: 150)
    }

    private func set(h: Int? = nil, m: Int? = nil, s: Int? = nil) {
        let seconds = (h ?? total / 3600) * 3600 + (m ?? total % 3600 / 60) * 60 + (s ?? total % 60)
        minutes = Double(seconds) / 60
    }

    private func wheel(_ range: Range<Int>, _ unit: String, _ value: Int, _ set: @escaping (Int) -> Void) -> some View {
        Picker(unit, selection: Binding(get: { value }, set: set)) {
            ForEach(range, id: \.self) { Text("\($0) \(unit)").tag($0) }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

/// Lays chips out in rows, wrapping when a row is full.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in arrange(bounds.width, subviews).points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += row + spacing; row = 0 }
            points.append(CGPoint(x: x, y: y))
            x += s.width + spacing
            row = max(row, s.height)
            widest = max(widest, x - spacing)
        }
        return (points, CGSize(width: widest, height: y + row))
    }
}

/// Shown on Compare and Goal when the saved Health data is over 30 days old.
struct StaleDataBanner: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isStale, let last = model.lastRefreshed {
            Section {
                HStack {
                    Label("Health data last read \(last.formatted(.relative(presentation: .named)))",
                          systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                    Spacer()
                    if model.isRefreshing {
                        ProgressView()
                    } else {
                        Button("Refresh") { Task { await model.refresh() } }
                            .buttonStyle(.bordered)
                    }
                }
            }
        }
    }
}
