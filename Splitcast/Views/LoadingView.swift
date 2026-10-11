import SwiftUI

/// The first read from Health: each step ticked off, a real progress bar, and something to read
/// meanwhile. Later reads happen behind the data already on screen.
struct LoadingView: View {
    let state: AppModel.State

    @State private var tip = 0

    private static let tips = [
        "Predictions start from a real result, like a race or parkrun, scaled by how your fitness has changed since.",
        "Covering more ground for each heartbeat on easy runs means you're getting fitter. Hills are allowed for.",
        "Critical power comes from your hardest 3- and 12-minute efforts. A parkrun counts.",
        "Splitcast learns how much you slow down over longer races from your own results.",
        "Missing data is never counted as zero. The app tells you what it left out and why.",
    ]

    private var progress: LoadProgress {
        if case .loading(let p) = state { p } else { .connecting }
    }

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Image("AboutIcon").resizable().frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 19)).accessibilityHidden(true)
                Text("Reading your Health data").font(.title2.bold())
                Text("This only happens once. After this, Splitcast opens straight away.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(LoadProgress.Step.allCases) { step in
                    HStack(spacing: 10) {
                        Group {
                            if step.rawValue < progress.step.rawValue {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else if step == progress.step {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "circle").foregroundStyle(.tertiary)
                            }
                        }
                        .frame(width: 22)
                        Text(step.title).foregroundStyle(step.rawValue > progress.step.rawValue ? .secondary : .primary)
                        Spacer()
                        if step == .workouts, progress.step == .workouts, progress.total > 0 {
                            Text("\(progress.done.formatted()) of \(progress.total.formatted())")
                                .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
                ProgressView(value: progress.fraction).padding(.top, 4)
            }
            .padding(20)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))

            Label(Self.tips[tip], systemImage: "lightbulb")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                .id(tip)
                .transition(.opacity)

            Spacer(minLength: 0)
            Label("Everything stays on this iPhone", systemImage: "lock.shield")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .padding(28)
        .accessibilityElement(children: .contain)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(7))
                withAnimation(.easeInOut(duration: 0.4)) { tip = (tip + 1) % Self.tips.count }
            }
        }
    }
}
