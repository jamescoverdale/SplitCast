import SwiftUI

struct ContentView: View {
    @State private var model = AppModel()
    @AppStorage(Setting.onboarded) private var onboarded = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !onboarded {
                OnboardingView(model: model) { onboarded = true }
            } else {
                switch model.state {
                case .ready(let data):
                    TabView {
                        Tab("Compare", systemImage: "arrow.left.arrow.right") { CompareView(data: data) }
                        Tab("Goal", systemImage: "target") { GoalView(data: data) }
                        Tab("Results", systemImage: "flag.checkered") { ResultsView(data: data) }
                    }
                case .notStarted, .loading:
                    LoadingView(state: model.state)
                case .failed(let message):
                    LoadFailedView(message: message) { Task { await model.refresh() } }
                }
            }
        }
        .environment(model)
        .task {
            if onboarded { await model.start() }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .healthDataUpdated) {
                await model.reloadIfNewer()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: Task { await model.reloadIfNewer() }
            // Goals and results may have changed while the app was open.
            case .background: model.publishWidgets()
            default: break
            }
        }
    }
}

struct LoadFailedView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn't read Health data", systemImage: "heart.slash")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: retry)
        }
    }
}
