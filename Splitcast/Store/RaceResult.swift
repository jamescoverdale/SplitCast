import Foundation
import SwiftData

/// A past race or time trial the user has confirmed or typed in. Stays on the device; never
/// written back to Health. Not tied to the main thread: widget and alert work reads results in
/// its own context off the main thread.
@Model
nonisolated final class RaceResult {
    var id: UUID
    var name: String
    var date: Date
    var km: Double
    var minutes: Double
    var notes: String
    /// A real result that isn't a fair benchmark (downhill course, paced a friend): still shown,
    /// never used for predictions or backtests.
    var notComparable: Bool
    /// The Health workout it came from, if any.
    var workoutID: UUID?

    init(name: String, date: Date, km: Double, minutes: Double, notes: String = "", notComparable: Bool = false, workoutID: UUID? = nil) {
        id = UUID()
        self.name = name
        self.date = date
        self.km = km
        self.minutes = minutes
        self.notes = notes
        self.notComparable = notComparable
        self.workoutID = workoutID
    }

    var benchmark: Benchmark {
        Benchmark(id: id, name: name, date: date, km: km, minutes: minutes, workoutID: workoutID)
    }
}
