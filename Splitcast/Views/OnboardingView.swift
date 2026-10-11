import SwiftData
import SwiftUI

/// First run: what the app does, connect to Health, then pick the results to compare against.
struct OnboardingView: View {
    let model: AppModel
    let finish: () -> Void

    var body: some View {
        switch model.state {
        case .notStarted:
            Welcome { Task { await model.refresh() } }
        case .loading:
            LoadingView(state: model.state)
        case .failed(let message):
            LoadFailedView(message: message) { Task { await model.refresh() } }
        case .ready(let data):
            PickResults(data: data, finish: finish)
        }
    }
}

private struct Welcome: View {
    let connect: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 72)).foregroundStyle(.tint)
            VStack(spacing: 8) {
                Text("Splitcast").font(.largeTitle.bold())
                Text("Race predictor").font(.title3).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 18) {
                point("arrow.left.arrow.right", "Then vs now",
                      "Compare your fitness today with the weeks before a past race.")
                point("target", "Predicted times",
                      "See what you could run now, and track it towards a goal.")
                point("lock.shield", "Private",
                      "Everything is worked out on your iPhone. Your Health data never leaves it.")
            }
            .padding(.horizontal, 32)
            Spacer()
            Button(action: connect) {
                Text("Connect Apple Health").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 32)
            Text("Splitcast reads workouts, heart rate, VO2max, HRV and sleep. It never writes to Health.")
                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .padding(.horizontal, 32).padding(.bottom)
        }
    }

    private func point(_ symbol: String, _ title: String, _ text: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(.tint).font(.title2).frame(width: 36)
        }
    }
}

/// Health doesn't mark which runs were races, so the user picks them from their fastest runs.
private struct PickResults: View {
    let data: FitnessData
    let finish: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \RaceResult.date, order: .reverse) private var results: [RaceResult]
    @AppStorage(Setting.units) private var units = Units.miles
    @State private var picked: Set<UUID> = []
    @State private var draft: ResultDraft?

    private var suggestions: [(workout: Workout, distance: String)] {
        let added = Set(results.compactMap(\.workoutID))
        return data.suggestedResults(perDistance: 5).filter { !added.contains($0.workout.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Predictions are scaled from your past races and time trials. Pick a few, ideally at different distances: a 5k and a half tell the app how you slow down over longer races.")
                        .foregroundStyle(.secondary)
                }

                if !results.isEmpty {
                    Section("Added") {
                        ForEach(results) { r in
                            LabeledContent(r.name, value: Format.clock(r.minutes))
                        }
                    }
                }

                ForEach(Predictor.standardDistances, id: \.km) { d in
                    let runs = suggestions.filter { $0.distance == d.name }
                    if !runs.isEmpty {
                        Section("Your fastest \(d.name) runs") {
                            ForEach(runs, id: \.workout.id) { s in row(s.workout) }
                        }
                    }
                }

                Section {
                    Button("Add a race that isn't in Health", systemImage: "plus") { draft = ResultDraft() }
                } footer: {
                    Text("You can rename results, correct times to chip times and add more later in Results.")
                }
            }
            .navigationTitle("Your races")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }.disabled(picked.isEmpty && results.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { finish() }
                }
            }
            .sheet(item: $draft) { ResultEditor(draft: $0) }
        }
    }

    private func row(_ w: Workout) -> some View {
        Button {
            if picked.contains(w.id) { picked.remove(w.id) } else { picked.insert(w.id) }
        } label: {
            HStack {
                Image(systemName: picked.contains(w.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(picked.contains(w.id) ? Color.accentColor : .secondary)
                    .font(.title3)
                RouteThumbnail(workoutID: w.id)
                VStack(alignment: .leading) {
                    HStack(spacing: 6) {
                        Text(w.start.formatted(date: .abbreviated, time: .omitted))
                        if let d = Predictor.officialDistance(near: w.km ?? 0), data.isFastest(w, distance: d) { PBBadge() }
                    }
                    Text("\(Format.distance(w.km ?? 0, units, digits: 2)) at \(Format.pace(w.paceMinPerKm ?? 0, units))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(Format.clock(w.minutes)).monospacedDigit().bold()
            }
        }
        .tint(.primary)
    }

    private func save() {
        for s in suggestions where picked.contains(s.workout.id) {
            let d = ResultDraft(s.workout, distance: s.distance)
            context.insert(RaceResult(name: d.name, date: d.date, km: d.km, minutes: d.minutes, workoutID: d.workoutID))
        }
        finish()
    }
}
