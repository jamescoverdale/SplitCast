import SwiftUI

/// How the app works, in plain words. Numbers come from the engine so the text can't drift.
struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Image("AboutIcon")
                        .resizable()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .accessibilityHidden(true)
                    Text("Splitcast").font(.title2.bold())
                    Text("Race predictor").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .listRowBackground(Color.clear)

            topic("arrow.left.arrow.right", "Then vs now",
                  "Pick a past race. Splitcast looks at the \(Int(FitnessData.window)) days before it and your last \(Int(FitnessData.window)) days, and compares the two: aerobic fitness, training, recovery and sleep.")

            topic("gauge.with.needle", "The prediction",
                  "Four markers measure your aerobic engine: VO2max, distance and power per heartbeat on steady runs (with climbing counted as extra distance), and critical power from your hardest 3- and 12-minute efforts. Each was tested against real race results. If they're 4% better than before your race, your time is predicted about 2% faster: the race time is scaled by the square root of the change. The range shows the most and least hopeful single marker.")

            topic("arrow.up.right", "Other distances",
                  "To predict a different distance, Splitcast uses Riegel's formula: time grows with distance to a power. The textbook power is \(String(format: "%.2f", Endurance.standard.exponent)), which assumes you're trained for the distance. Most runners slow down more over long races, so when you have results at two distances within a year, Splitcast works out your own power from them. Add a few races at different distances for the best predictions.")

            topic("checkmark.seal", "How good is it?",
                  "On the Goal tab, \"How good is this?\" shows what the app would have predicted for each of your past races, using only data from before them. It's the honest test: if it's often far off, treat predictions as a rough guide.")

            topic("minus.circle", "Missing data",
                  "Missing data is never counted as zero. A metric without enough data is left out and the app says why. Distance and power per heartbeat need at least \(FitnessData.minSteadyRuns) steady outdoor runs, so one or two slow jogs can't swing them. You can turn a marker off in Results › Prediction markers if you think its data is wrong.")

            topic("lock.shield", "Your data",
                  "Everything is worked out on your iPhone. Splitcast reads Apple Health and never writes to it, and nothing is sent anywhere. Results you add are stored on this iPhone. A copy of your Health data is kept so the app opens quickly; refresh it from Results, and the app reminds you after \(FitnessCache.staleAfterDays) days.")

            topic("exclamationmark.triangle", "Limits",
                  "Predictions assume a flat course in mild weather: hills, heat and wind add time. Watch VO2max readings are estimates and can shift with software updates or a new watch. HRV jumps if you start wearing your Watch overnight. Splitcast is a training guide, not medical advice.")

            Section {
                LabeledContent("Version", value: version)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func topic(_ symbol: String, _ title: String, _ text: String) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol).font(.headline)
                Text(text).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}
