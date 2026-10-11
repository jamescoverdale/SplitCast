import Foundation

/// The fitness markers compared between two windows. Only `drivesPrediction` ones feed the time
/// prediction; the rest are context.
nonisolated enum Metric: String, CaseIterable, Sendable, Identifiable {
    case vo2max, distancePerBeat, powerPerBeat, criticalPower, runVolume, longestRun, climb, fitness, form, restingHR, hrv, sleep

    enum ChartStyle { case line, points }

    static let predictionMetrics: Set<Metric> = [.vo2max, .distancePerBeat, .powerPerBeat, .criticalPower]

    var id: String { rawValue }
    var drivesPrediction: Bool { Self.predictionMetrics.contains(self) }
    var lowerIsBetter: Bool { self == .restingHR }
    /// Form swings either side of zero, so a percentage change means nothing.
    var showsAbsoluteChange: Bool { self == .form }

    var title: String {
        switch self {
        case .vo2max: "VO2max"
        case .distancePerBeat: "Distance per heartbeat"
        case .powerPerBeat: "Power per heartbeat"
        case .criticalPower: "Critical power"
        case .runVolume: "Running volume"
        case .longestRun: "Longest run"
        case .climb: "Climb"
        case .fitness: "Fitness (training load)"
        case .form: "Form"
        case .restingHR: "Resting HR"
        case .hrv: "HRV"
        case .sleep: "Sleep"
        }
    }

    var subtitle: String {
        switch self {
        case .vo2max: "watch estimate, 30-day average"
        case .distancePerBeat: "steady outdoor runs, adjusted for hills"
        case .powerPerBeat: "steady runs with running power"
        case .criticalPower: "from your best 3 and 12 minutes of power"
        case .runVolume: "4-week average"
        case .longestRun: "last 6 weeks"
        case .climb: "on foot, 4-week average"
        case .fitness: "42-day training load"
        case .form: "fitness minus 7-day fatigue"
        case .restingHR: "4-week average"
        case .hrv: "4-week average, SDNN"
        case .sleep: "4-week average, nights of 3 h+"
        }
    }

    /// SF Symbol name.
    var symbol: String {
        switch self {
        case .vo2max: "lungs"
        case .distancePerBeat: "ruler"
        case .powerPerBeat: "bolt.heart"
        case .criticalPower: "bolt"
        case .runVolume: "chart.bar"
        case .longestRun: "road.lanes"
        case .climb: "mountain.2"
        case .fitness: "chart.line.uptrend.xyaxis"
        case .form: "battery.75percent"
        case .restingHR: "heart"
        case .hrv: "waveform.path.ecg"
        case .sleep: "bed.double"
        }
    }

    /// What the metric needs in a window, shown when there isn't enough data.
    var requirement: String {
        switch self {
        case .vo2max: "Needs a VO2max reading from your watch in the 3 months before."
        case .distancePerBeat: "Needs 3+ steady outdoor runs (5 km+, easy to moderate effort) with heart rate."
        case .powerPerBeat: "Needs 3+ steady outdoor runs with running power from your watch."
        case .criticalPower: "Needs running power from your watch on a run with hard efforts of 3 and 12 minutes (a race, parkrun or interval session) in the 6 weeks before."
        case .runVolume, .longestRun: "Needs runs in the window."
        case .climb: "Needs walks, runs or hikes with elevation recorded by your watch."
        case .fitness, .form: "Needs workouts with heart rate."
        case .restingHR: "Needs resting heart rate readings in the 4 weeks before."
        case .hrv: "Needs HRV readings in the 4 weeks before."
        case .sleep: "Needs 7+ nights of 3 hours or more of tracked sleep in the 4 weeks before."
        }
    }

    /// How to get more of this data, shown when there isn't enough.
    var dataTip: String? {
        switch self {
        case .vo2max: "Apple Watch records VO2max on outdoor walks, runs and hikes. Garmin and some other watches only send it to Health when it changes, so readings can be months apart."
        case .distancePerBeat: "Steady runs are outdoor runs of 5 km or more at an easy to moderate effort, recorded with heart rate."
        case .powerPerBeat: "Apple Watch (Series 6 or later) records running power. Garmin and many other watches don't send it to Apple Health."
        case .criticalPower: "Apple Watch (Series 6 or later) records running power. A race, parkrun or hard interval session gives the best figure; easy runs alone understate it."
        case .climb: "Elevation comes from your watch's barometer. Some apps that sync to Health don't include it."
        case .restingHR: "Wear your watch through the day so it can measure resting heart rate."
        case .hrv: "Apple Watch records HRV, mostly overnight. Many other watches don't send it to Apple Health."
        case .sleep: "Wear your watch to bed, or use a sleep-tracking app that saves to Apple Health."
        default: nil
        }
    }

    /// What the metric means, for the detail screen.
    var explanation: String {
        switch self {
        case .vo2max: "How much oxygen your body can use when working hard. Higher is fitter. It's your watch's estimate, usually from outdoor walks, runs and hikes."
        case .distancePerBeat: "How far you travel for each heartbeat on easy runs. Higher means your heart is doing less work for the same pace."
        case .powerPerBeat: "Running power for each heartbeat on easy runs. Like distance per heartbeat, but less affected by wind and hills."
        case .criticalPower: "Roughly the power you could hold for half an hour to an hour, worked out from your best 3- and 12-minute efforts. Higher is fitter."
        case .runVolume: "How far you've been running each week. More volume usually builds endurance, especially for longer races."
        case .longestRun: "Your longest single run. Long runs build the endurance that half marathons and marathons need."
        case .climb: "How much you've climbed on foot each week. Hills build strength, but make easy runs look slower."
        case .fitness: "Your training load built up over about six weeks, from how long and how hard you've trained."
        case .form: "Fitness minus recent fatigue. Positive means fresh, as after a taper; negative means tired from recent training."
        case .restingHR: "Your heart rate at rest. It tends to fall as you get fitter and rise when you're tired, ill or stressed."
        case .hrv: "Heart rate variability: the variation between beats. Higher than your usual tends to mean well recovered."
        case .sleep: "Time asleep each night. Sleep is when training turns into fitness."
        }
    }

    /// Whether the detail chart's shape means something (cumulative totals always rise).
    var describesTrend: Bool { self != .runVolume && self != .climb }

    var note: String? {
        switch self {
        case .distancePerBeat: "Each metre climbed counts as 8 metres of flat running, so hilly runs compare fairly with flat ones."
        case .criticalPower: "Only as good as your hardest recent efforts: weeks of easy running will understate it."
        case .hrv: "Overnight readings run far higher than daytime ones, so a change in when the watch is worn moves this a lot."
        case .fitness, .form: "Training load uses each workout's average heart rate (Banister TRIMP)."
        default: nil
        }
    }

    var chartStyle: ChartStyle {
        switch self {
        case .distancePerBeat, .powerPerBeat, .criticalPower, .longestRun: .points
        default: .line
        }
    }
}
