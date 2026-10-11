import SwiftData
import SwiftUI

/// Personal bests, the user's results, fast runs worth adding, and settings.
struct ResultsView: View {
    let data: FitnessData

    @Query(sort: \RaceResult.date, order: .reverse) private var results: [RaceResult]
    @AppStorage(Setting.units) private var units = Units.miles
    @AppStorage(Setting.excludedMetrics) private var excludedMetrics = ""
    @AppStorage(Setting.backgroundUpdates) private var backgroundUpdates = true
    @AppStorage(Setting.goalAlerts) private var goalAlerts = false
    @Environment(AppModel.self) private var model
    @State private var draft: ResultDraft?

    /// How many results show before "Show all".
    private static let shortList = 6

    private struct Spotted {
        let workout: Workout
        let distance: (km: Double, name: String)
        let reason: String
    }

    /// Fast runs at standard distances not added yet, newest first, with why they stand out.
    private var spotted: [Spotted] {
        let added = Set(results.compactMap(\.workoutID))
        let addedDays = Set(results.map { data.startOfDay($0.date) })
        var out: [Spotted] = []
        for s in data.suggestedResults() {
            let w = s.workout
            guard !added.contains(w.id), !addedDays.contains(data.startOfDay(w.start)),
                  let d = Predictor.officialDistance(near: w.km ?? 0) else { continue }
            out.append(Spotted(workout: w, distance: d, reason: data.spottedReason(for: w, distance: d)))
        }
        return Array(out.sorted { $0.workout.start > $1.workout.start }.prefix(5))
    }

    var body: some View {
        let bests = Records.personalBests(results.map(\.benchmark))
        let pbIDs = Set(bests.values.map(\.id))

        NavigationStack {
            List {
                if !bests.isEmpty {
                    Section {
                        PersonalBests(bests: bests)
                    } header: {
                        Heading("Personal bests")
                    }
                }

                Section {
                    if results.isEmpty {
                        Text("No results yet. Add a race or time trial, or one of the fast runs below.").foregroundStyle(.secondary)
                    }
                    ResultRows(results: Array(results.prefix(Self.shortList)), pbIDs: pbIDs, data: data, units: units, draft: $draft)
                    if results.count > Self.shortList {
                        NavigationLink("Show all \(results.count)") {
                            List {
                                ResultRows(results: results, pbIDs: pbIDs, data: data, units: units, draft: $draft)
                            }
                            .navigationTitle("Your results")
                        }
                    }
                } header: {
                    Heading("Your results")
                } footer: {
                    Text("Swipe left to delete a result, or to stop it being used for predictions (a downhill course, pacing a friend).")
                }

                if !spotted.isEmpty {
                    Section {
                        ForEach(spotted, id: \.workout.id) { s in
                            HStack(spacing: 12) {
                                RouteThumbnail(workoutID: s.workout.id)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text("\(s.distance.name) · \(Format.clock(s.workout.minutes))").monospacedDigit()
                                        if data.isFastest(s.workout, distance: s.distance) { PBBadge() }
                                    }
                                    Text("\(s.workout.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())) · \(s.reason)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Add", systemImage: "plus") { draft = ResultDraft(s.workout, distance: s.distance.name) }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.bordered)
                                    .buttonBorderShape(.circle)
                                    .tint(.accentColor)
                            }
                        }
                    } header: {
                        Heading("Fast runs we spotted")
                    } footer: {
                        Text("Races aren't marked in Health. Add the ones that were, and change the time to your chip time if you have it.")
                    }
                }

                settings
            }
            .refreshable { await model.refresh() }
            .navigationTitle("Results")
            .toolbar {
                Button("Add result", systemImage: "plus") { draft = ResultDraft() }
            }
            .sheet(item: $draft) { d in
                ResultEditor(draft: d, routeID: d.existing.flatMap { data.matchingRun(for: $0.benchmark)?.id } ?? d.workoutID)
            }
        }
    }

    private var settings: some View {
        let markers = Setting.predictionMetrics(excluding: excludedMetrics).count
        return Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Health data")
                    if let last = model.lastRefreshed {
                        Text("Read \(last.formatted(.relative(presentation: .named)))")
                            .font(.caption).foregroundStyle(model.isStale ? .orange : .secondary)
                    }
                }
                Spacer()
                if model.isRefreshing {
                    ProgressView()
                } else {
                    Button("Refresh") { Task { await model.refresh() } }.buttonStyle(.bordered)
                }
            }
            Button("Re-read all history") { Task { await model.refresh(full: true) } }
                .disabled(model.isRefreshing)
            Toggle(isOn: $backgroundUpdates) {
                Text("Update in the background")
                Text("Refreshes widgets and goal alerts after each workout")
            }
            .onChange(of: backgroundUpdates) { _, on in BackgroundUpdate.setEnabled(on) }
            Toggle(isOn: Binding(get: { goalAlerts }, set: { on in
                if on {
                    Task {
                        goalAlerts = await GoalAlertsRunner.requestPermission()
                        model.publishWidgets()
                    }
                } else {
                    goalAlerts = false
                }
            })) {
                Text("Goal alerts")
                Text("When your prediction closes in on or beats a goal. At most one a day.")
            }
            Picker("Units", selection: $units) {
                Text("Miles").tag(Units.miles)
                Text("Kilometres").tag(Units.kilometres)
            }
            .pickerStyle(.navigationLink)
            NavigationLink { MarkerSettingsView() } label: {
                LabeledContent("Prediction markers", value: markers == Metric.predictionMetrics.count ? "All \(markers)" : "\(markers) of \(Metric.predictionMetrics.count)")
            }
            NavigationLink("How Splitcast works") { AboutView() }
        } header: {
            Heading("Settings")
        } footer: {
            if let error = model.refreshError {
                Text("Couldn't refresh: \(error)").foregroundStyle(.red)
            } else {
                Text("Everything is worked out on this iPhone. Nothing leaves it.")
            }
        }
    }
}

/// Result rows with their swipe actions, shared by the short list and "Show all".
private struct ResultRows: View {
    let results: [RaceResult]
    let pbIDs: Set<UUID>
    let data: FitnessData
    let units: Units
    @Binding var draft: ResultDraft?

    @Environment(\.modelContext) private var context

    var body: some View {
        ForEach(results) { r in
            Button { draft = ResultDraft(r) } label: {
                ResultRow(result: r.benchmark, data: data, units: units,
                          detail: r.notComparable ? "Not used for predictions" : nil, isPB: pbIDs.contains(r.id))
            }
            .tint(.primary)
            .swipeActions {
                Button("Delete", role: .destructive) { context.delete(r) }
                Button(r.notComparable ? "Use" : "Don't use") { r.notComparable.toggle() }.tint(.gray)
            }
        }
    }
}

/// The fastest result at each standard distance, two by two.
private struct PersonalBests: View {
    let bests: [Double: Benchmark]

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 14) {
            ForEach(Predictor.standardDistances.filter { bests[$0.km] != nil }, id: \.km) { d in
                let r = bests[d.km]!
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.name).font(.caption).foregroundStyle(.secondary)
                    Text(Format.clock(r.minutes)).font(.title2.weight(.bold)).monospacedDigit()
                    Text(r.date.formatted(date: .abbreviated, time: .omitted)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

/// Lets the user leave a prediction marker out, e.g. if an old Watch over-estimated VO2max.
struct MarkerSettingsView: View {
    @AppStorage(Setting.excludedMetrics) private var excludedMetrics = ""

    var body: some View {
        let used = Setting.predictionMetrics(excluding: excludedMetrics)
        List {
            Section {
                ForEach(Metric.allCases.filter(\.drivesPrediction)) { m in
                    Toggle(isOn: Binding(get: { used.contains(m) }, set: { on in
                        let next = on ? used.union([m]) : used.subtracting([m])
                        excludedMetrics = Metric.predictionMetrics.subtracting(next).map(\.rawValue).sorted().joined(separator: ",")
                    })) {
                        Text(m.title)
                        Text(m.subtitle)
                    }
                }
            } footer: {
                Text("Turn a marker off if you think its data is wrong. Predictions use the markers left on; check \"How good is this?\" on the Goal tab to see whether it helped.")
            }
        }
        .navigationTitle("Prediction markers")
    }
}
