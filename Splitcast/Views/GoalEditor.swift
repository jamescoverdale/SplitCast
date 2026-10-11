import SwiftData
import SwiftUI

/// Sets or removes the goal for a distance, with quick picks and a sense of how hard it is.
struct GoalEditor: View {
    let data: FitnessData
    @Binding var km: Double

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RaceResult.date, order: .reverse) private var results: [RaceResult]
    @AppStorage(Setting.excludedMetrics) private var excludedMetrics = ""
    @State private var distance: Double
    @State private var minutes: Double

    init(data: FitnessData, km: Binding<Double>) {
        self.data = data
        _km = km
        _distance = State(initialValue: km.wrappedValue)
        _minutes = State(initialValue: Self.storedGoal(km.wrappedValue) ?? 0)
    }

    private static func storedGoal(_ km: Double) -> Double? {
        Format.parseClock(UserDefaults.standard.string(forKey: Setting.goalTime(km)) ?? "")
    }

    var body: some View {
        let context = GoalContext(data: data, results: results.map(\.benchmark), comparable: comparable, km: distance,
                                  metrics: Setting.predictionMetrics(excluding: excludedMetrics))
        NavigationStack {
            Form {
                Picker("Distance", selection: $distance) {
                    ForEach(Predictor.standardDistances, id: \.km) { Text($0.name).tag($0.km) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .onChange(of: distance) { _, new in
                    minutes = Self.storedGoal(new) ?? context.suggestions(for: new).first?.minutes ?? 0
                }

                Section("Goal time") {
                    DurationWheels(minutes: $minutes, showsHours: distance > 10)
                    FlowLayout {
                        ForEach(context.suggestions(for: distance), id: \.label) { s in
                            Button(s.label) { minutes = s.minutes }
                                .buttonStyle(.bordered)
                                .tint(abs(s.minutes - minutes) < 1.0 / 120 ? .accentColor : .secondary)
                                .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 4)
                }

                if minutes > 0, let feedback = context.feedback(for: minutes) {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(feedback.title).font(.headline)
                            Text(feedback.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }

                if Self.storedGoal(distance) != nil {
                    Section {
                        Button("Remove goal", role: .destructive) { save(nil) }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle("Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(minutes) }.disabled(minutes <= 0)
                }
            }
        }
    }

    private var comparable: [Benchmark] {
        results.filter { !$0.notComparable && $0.date < data.now }.map(\.benchmark)
    }

    private func save(_ goal: Double?) {
        UserDefaults.standard.set(goal.map(Format.clock) ?? "", forKey: Setting.goalTime(distance))
        km = distance
        dismiss()
    }
}

/// What the goal editor needs to know about one distance: today's prediction, the personal best,
/// and the best prediction of the last year.
private struct GoalContext {
    let data: FitnessData
    let results: [Benchmark]
    let comparable: [Benchmark]
    let km: Double
    let metrics: Set<Metric>

    private var benchmark: Benchmark? { Setting.benchmark(for: km, among: comparable) }

    private var endurance: Endurance { data.endurance(from: comparable, using: metrics) }

    func prediction(for km: Double) -> Prediction? {
        benchmark.flatMap { data.predict(from: $0, toKm: km, using: metrics, endurance: endurance) }
    }

    /// Round targets either side of today's prediction, the PB, and "a bit faster than today".
    func suggestions(for km: Double) -> [(label: String, minutes: Double)] {
        var out: [(label: String, minutes: Double)] = []
        if let p = prediction(for: km)?.minutes {
            let step: Double = km <= 10 ? 1 : km <= 21.1 ? 5 : 15
            let below = (p / step).rounded(.down) * step
            for target in [below, below + step] { out.append(("Sub-\(Self.roundLabel(target))", target)) }
            out.append(("Today −2%", ((p * 0.98) * 60).rounded() / 60))
        }
        if let pb = Records.personalBests(results)[km] {
            out.append(("Beat PB · \(Format.clock(pb.minutes))", pb.minutes - 1.0 / 60))
        }
        return out
    }

    /// "20" for 20:00, "1:45" for 1:45:00.
    private static func roundLabel(_ minutes: Double) -> String {
        minutes < 60 ? "\(Int(minutes))" : String(format: "%d:%02d", Int(minutes) / 60, Int(minutes) % 60)
    }

    func feedback(for goal: Double) -> (title: String, detail: String)? {
        guard let p = prediction(for: km) else { return nil }
        let gap = p.minutes - goal
        let needed = Predictor.fitnessNeeded(predicted: p.minutes, goal: goal)
        if needed <= 0 {
            return ("\(Format.clock(-gap)) slower than today", "Your prediction already beats it. Set a faster one to stretch yourself.")
        }
        let title = "\(Format.clock(gap)) faster than today"
        let need = "You'd need to be about \(Int((needed * 100).rounded()))% fitter than now."
        if needed < 0.02 { return (title, "\(need) Within reach.") }
        guard let benchmark else { return (title, need) }
        let since = data.calendar.date(byAdding: .year, value: -1, to: data.now)!
        if let best = data.weeklyPredictions(from: benchmark, toKm: km, since: since, using: metrics, endurance: endurance)
            .min(by: { $0.prediction.minutes < $1.prediction.minutes }) {
            if best.prediction.minutes <= goal * 1.01 {
                return (title, "\(need) A stretch, but you were close in \(best.date.formatted(.dateTime.month(.wide))).")
            }
            return (title, "\(need) A big step: your best prediction this year was \(Format.clock(best.prediction.minutes)).")
        }
        return (title, need)
    }
}
