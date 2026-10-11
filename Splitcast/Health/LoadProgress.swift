import Foundation

/// How far a read from Health has got, for the first-run loading screen.
nonisolated struct LoadProgress: Sendable {
    enum Step: Int, CaseIterable, Sendable, Identifiable {
        case connecting, restingHeartRate, hrv, vo2max, sleep, workouts

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .connecting: "Connecting to Apple Health"
            case .restingHeartRate: "Resting heart rate"
            case .hrv: "Heart rate variability"
            case .vo2max: "VO2max"
            case .sleep: "Sleep"
            case .workouts: "Workouts"
            }
        }
    }

    var step: Step
    /// Workouts read so far, and how many there are (once known).
    var done = 0
    var total = 0

    static let connecting = LoadProgress(step: .connecting)

    /// 0 to 1. The daily figures are quick; reading each workout is most of the wait.
    var fraction: Double {
        switch step {
        case .workouts: 0.12 + 0.88 * (total > 0 ? Double(done) / Double(total) : 0)
        default: 0.03 * Double(step.rawValue)
        }
    }
}
