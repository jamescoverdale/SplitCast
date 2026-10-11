import Foundation

nonisolated enum Activity: String, Sendable, Codable {
    case running, walking, hiking, other

    var isOnFoot: Bool { self != .other }
}

/// One workout after de-duplication, with the figures the engine needs.
nonisolated struct Workout: Sendable, Codable, Identifiable {
    let id: UUID
    let start: Date
    let minutes: Double
    let activity: Activity
    let km: Double?
    let hrAvg: Double?
    let hrMax: Double?
    let powerW: Double?
    let elevUpM: Double?
    let indoor: Bool
    /// Best average running power over 3 and 12 minutes, from the Watch's power samples.
    var bestPower3: Double? = nil
    var bestPower12: Double? = nil
    /// Fastest mile inside the run, from the Watch's distance samples.
    var bestMileMinutes: Double? = nil

    var paceMinPerKm: Double? { km.flatMap { $0 > 0 ? minutes / $0 : nil } }
}

/// Daily health figures. Missing values are nil, never zero.
nonisolated struct Day: Sendable, Codable {
    let date: Date
    var restingHR: Double?
    var hrv: Double?
    var vo2max: Double?
    var sleepMinutes: Double?
}

/// A past result that fitness is compared against: a race, a time trial or a hard run.
nonisolated struct Benchmark: Sendable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let date: Date
    let km: Double
    let minutes: Double
    /// The Health workout it was run in, if known.
    var workoutID: UUID? = nil
}
