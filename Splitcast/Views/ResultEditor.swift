import SwiftData
import SwiftUI

/// Form state for adding or editing a result.
struct ResultDraft: Identifiable {
    let id = UUID()
    var existing: RaceResult?
    var name = ""
    var date = Date()
    var km = 5.0
    /// What the Watch measured, when the result came from a workout and was snapped to an
    /// official distance.
    var measuredKm: Double?
    var minutes = 0.0
    var notes = ""
    var usedForPredictions = true
    var workoutID: UUID?

    init() {}

    init(_ result: RaceResult) {
        existing = result
        name = result.name
        date = result.date
        km = result.km
        minutes = result.minutes
        notes = result.notes
        usedForPredictions = !result.notComparable
        workoutID = result.workoutID
    }

    /// A race spotted in Health: GPS distances read a little long or short, so a run close to an
    /// official distance is stored at it.
    init(_ workout: Workout, distance: String) {
        let measured = workout.km ?? 5
        let official = Predictor.officialDistance(near: measured)
        name = "\(official?.name ?? distance), \(workout.start.formatted(.dateTime.day().month(.abbreviated).year()))"
        date = workout.start
        km = official?.km ?? measured
        measuredKm = official == nil ? nil : measured
        minutes = workout.minutes
        workoutID = workout.id
    }
}

struct ResultEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(Setting.units) private var units = Units.miles
    @State private var draft: ResultDraft
    @State private var otherKmText: String
    /// The workout whose route is shown at the top, if any.
    let routeID: UUID?

    /// Marks "Other" in the distance picker.
    private static let other = 0.0

    init(draft: ResultDraft, routeID: UUID? = nil) {
        _draft = State(initialValue: draft)
        self.routeID = routeID ?? draft.workoutID
        _otherKmText = State(initialValue: String(format: "%g", (draft.km * 1000).rounded() / 1000))
    }

    private var isStandard: Bool { Predictor.standardDistances.contains { $0.km == draft.km } }

    var body: some View {
        NavigationStack {
            Form {
                if let routeID {
                    RouteMap(workoutID: routeID)
                        .frame(height: 200)
                        .listRowInsets(EdgeInsets())
                }

                Section {
                    LabeledContent("Name") {
                        TextField("e.g. Leeds Half", text: $draft.name).multilineTextAlignment(.trailing)
                    }
                    DatePicker("Date", selection: $draft.date, in: ...Date(), displayedComponents: .date)
                }

                Section {
                    Picker("Distance", selection: Binding(get: { isStandard ? draft.km : Self.other }, set: { choice in
                        draft.km = choice == Self.other ? (Double(otherKmText) ?? draft.km) : choice
                    })) {
                        ForEach(Predictor.standardDistances, id: \.km) { Text($0.name).tag($0.km) }
                        Text("Other").tag(Self.other)
                    }
                    .pickerStyle(.segmented)
                    if !isStandard {
                        LabeledContent("Kilometres") {
                            TextField("7.5", text: $otherKmText)
                                .multilineTextAlignment(.trailing).keyboardType(.decimalPad)
                                .onChange(of: otherKmText) { _, text in
                                    if let km = Double(text.replacingOccurrences(of: ",", with: ".")), km > 0 { draft.km = km }
                                }
                        }
                    }
                } header: {
                    Text("Distance")
                } footer: {
                    if let measured = draft.measuredKm, isStandard, abs(measured - draft.km) > 0.005 {
                        Text("Your watch measured \(Format.distance(measured, units, digits: 2)). Splitcast uses the official \(Format.distance(draft.km, units, digits: 1)).")
                    }
                }

                Section {
                    DurationField(title: "Time", minutes: $draft.minutes, showsHours: draft.km > 10, large: true)
                } footer: {
                    if draft.workoutID != nil { Text("From your Health workout. Tap to change it to your chip time.") }
                }

                Section {
                    Toggle(isOn: $draft.usedForPredictions) {
                        Text("Use for predictions")
                        Text("Turn off for downhill or short courses")
                    }
                }

                Section("Notes") {
                    TextField("Course, conditions, how it felt", text: $draft.notes, axis: .vertical)
                }

                if let existing = draft.existing {
                    Section {
                        Button("Delete result", role: .destructive) {
                            context.delete(existing)
                            dismiss()
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(draft.existing == nil ? "Add result" : "Edit result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(draft.minutes <= 0 || draft.km <= 0)
                }
            }
        }
    }

    private func save() {
        guard draft.minutes > 0, draft.km > 0 else { return }
        let name = draft.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Result" : draft.name
        if let r = draft.existing {
            r.name = name
            r.date = draft.date
            r.km = draft.km
            r.minutes = draft.minutes
            r.notes = draft.notes
            r.notComparable = !draft.usedForPredictions
        } else {
            context.insert(RaceResult(name: name, date: draft.date, km: draft.km, minutes: draft.minutes, notes: draft.notes,
                                      notComparable: !draft.usedForPredictions, workoutID: draft.workoutID))
        }
        dismiss()
    }
}
