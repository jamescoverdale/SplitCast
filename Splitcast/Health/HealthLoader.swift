import Foundation
import HealthKit

/// Reads Health data into the engine's models, and wakes the app when new data arrives. Runs off
/// the main thread.
actor HealthLoader {
    private let store = HKHealthStore()

    static let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKSeriesType.workoutRoute(),
        HKQuantityType(.heartRate),
        HKQuantityType(.restingHeartRate),
        HKQuantityType(.heartRateVariabilitySDNN),
        HKQuantityType(.vo2Max),
        HKQuantityType(.runningPower),
        HKQuantityType(.distanceWalkingRunning),
        HKCategoryType(.sleepAnalysis),
    ]

    func requestAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw LoadError.healthUnavailable }
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    /// Reads everything from `start` to now. The caller merges it into the saved copy.
    func read(from start: Date, progress: @escaping @Sendable (LoadProgress) async -> Void = { _ in }) async throws -> (days: [Day], workouts: [Workout]) {
        let end = Date()
        var days: [Date: Day] = [:]
        func update(_ values: [Date: Double], _ set: (inout Day, Double) -> Void) {
            for (date, v) in values {
                set(&days[date, default: Day(date: date)], v)
            }
        }
        await progress(LoadProgress(step: .restingHeartRate))
        update(try await dailyAverages(.restingHeartRate, .count().unitDivided(by: .minute()), from: start, to: end)) { $0.restingHR = $1 }
        await progress(LoadProgress(step: .hrv))
        update(try await dailyAverages(.heartRateVariabilitySDNN, .secondUnit(with: .milli), from: start, to: end)) { $0.hrv = $1 }
        await progress(LoadProgress(step: .vo2max))
        update(try await dailyAverages(.vo2Max, HKUnit(from: "ml/kg*min"), from: start, to: end)) { $0.vo2max = $1 }
        await progress(LoadProgress(step: .sleep))
        update(try await sleepByNight(from: start, to: end)) { $0.sleepMinutes = $1 }

        await progress(LoadProgress(step: .workouts))
        let found = try await workouts(from: start, to: end)
        await progress(LoadProgress(step: .workouts, done: 0, total: found.count))
        let workouts = try await withThrowingTaskGroup(of: Workout.self) { group in
            var out: [Workout] = []
            var next = found.makeIterator()
            for _ in 0..<8 {
                if let w = next.next() { group.addTask { try await self.details(for: w) } }
            }
            while let w = try await group.next() {
                out.append(w)
                if out.count % 10 == 0 || out.count == found.count {
                    await progress(LoadProgress(step: .workouts, done: out.count, total: found.count))
                }
                if let w = next.next() { group.addTask { try await self.details(for: w) } }
            }
            return out
        }
        return (Array(days.values), workouts)
    }

    // MARK: - Background delivery

    /// Stops HealthKit waking the app.
    func stopBackgroundDelivery() async {
        try? await store.disableAllBackgroundDelivery()
    }

    /// Asks iOS to wake the app when a workout is saved, and once a day for the overnight figures.
    /// The observers must be set up at every launch, including background ones.
    func observeChanges(_ onChange: @escaping @Sendable () async -> Void) async {
        let types: [(HKSampleType, HKUpdateFrequency)] = [(HKObjectType.workoutType(), .immediate),
                                                          (HKQuantityType(.restingHeartRate), .daily)]
        for (type, frequency) in types {
            try? await store.enableBackgroundDelivery(for: type, frequency: frequency)
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else { return completion() }
                Task {
                    await onChange()
                    completion()
                }
            }
            store.execute(query)
        }
    }

    // MARK: - Daily figures

    private func dailyAverages(_ id: HKQuantityTypeIdentifier, _ unit: HKUnit, from start: Date, to end: Date) async throws -> [Date: Double] {
        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: start, end: end)),
            options: .discreteAverage, anchorDate: start, intervalComponents: DateComponents(day: 1))
        var out: [Date: Double] = [:]
        try await query.result(for: store).enumerateStatistics(from: start, to: end) { stats, _ in
            if let q = stats.averageQuantity() { out[stats.startDate] = q.doubleValue(for: unit) }
        }
        return out
    }

    /// Minutes asleep per night, dated by the wake-up day. Where two apps (say the Watch and
    /// AutoSleep) both recorded a night, the larger total wins rather than adding them up.
    private func sleepByNight(from start: Date, to end: Date) async throws -> [Date: Double] {
        let samples = try await HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        ).result(for: store)
        let asleep = Set(HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue))
        var bySource: [Date: [String: Double]] = [:]
        for s in samples where asleep.contains(s.value) {
            let night = Calendar.current.startOfDay(for: s.endDate)
            bySource[night, default: [:]][s.sourceRevision.source.bundleIdentifier, default: 0] += s.endDate.timeIntervalSince(s.startDate) / 60
        }
        return bySource.mapValues { $0.values.max() ?? 0 }
    }

    // MARK: - Workouts

    private struct Found: Sendable {
        let id: UUID
        let start: Date
        let end: Date
        let activity: Activity
        let km: Double?
        let elevUpM: Double?
        let indoor: Bool
        let isApple: Bool
    }

    /// One workout per session: the same run is often saved by the Watch and by Strava or
    /// WorkOutDoors. Overlapping workouts are grouped and the Watch's one kept, else the one with
    /// a distance, else the longest.
    private func workouts(from start: Date, to end: Date) async throws -> [Found] {
        let list = try await HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForSamples(withStart: start, end: end))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        ).result(for: store)
        let found = list.map { w in
            Found(id: w.uuid, start: w.startDate, end: w.endDate, activity: Self.activity(w.workoutActivityType),
                  km: w.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo)),
                  elevUpM: (w.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter()),
                  indoor: (w.metadata?[HKMetadataKeyIndoorWorkout] as? NSNumber)?.boolValue ?? false,
                  isApple: w.sourceRevision.source.bundleIdentifier.hasPrefix("com.apple.health"))
        }
        return Self.deduplicated(found)
    }

    private static func deduplicated(_ list: [Found]) -> [Found] {
        func better(_ a: Found, _ b: Found) -> Bool {
            if a.isApple != b.isApple { return a.isApple }
            if (a.km != nil) != (b.km != nil) { return a.km != nil }
            return a.end.timeIntervalSince(a.start) > b.end.timeIntervalSince(b.start)
        }
        var out: [Found] = []
        var clusterEnd = Date.distantPast
        for w in list {
            if let last = out.last, w.start < clusterEnd {
                if better(w, last) { out[out.count - 1] = w }
                clusterEnd = max(clusterEnd, w.end)
            } else {
                out.append(w)
                clusterEnd = w.end
            }
        }
        return out
    }

    /// HR and power come from every source's samples inside the workout's time window, so they
    /// work whichever app saved the workout.
    private func details(for w: Found) async throws -> Workout {
        let window = HKQuery.predicateForSamples(withStart: w.start, end: w.end, options: .strictStartDate)
        let hr = try? await HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.heartRate), predicate: window),
            options: [.discreteAverage, .discreteMax]
        ).result(for: store)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        var power: Double?
        if w.activity == .running {
            power = try? await HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: HKQuantityType(.runningPower), predicate: window), options: .discreteAverage
            ).result(for: store)?.averageQuantity()?.doubleValue(for: .watt())
        }
        var km = w.km
        if km == nil, w.activity.isOnFoot {
            km = try? await HKStatisticsQueryDescriptor(
                predicate: .quantitySample(type: HKQuantityType(.distanceWalkingRunning), predicate: window), options: .cumulativeSum
            ).result(for: store)?.sumQuantity()?.doubleValue(for: .meterUnit(with: .kilo))
        }
        var workout = Workout(id: w.id, start: w.start, minutes: w.end.timeIntervalSince(w.start) / 60, activity: w.activity,
                              km: km, hrAvg: hr?.averageQuantity()?.doubleValue(for: bpm), hrMax: hr?.maximumQuantity()?.doubleValue(for: bpm),
                              powerW: power, elevUpM: w.elevUpM, indoor: w.indoor)
        if w.activity == .running, !w.indoor {
            if power != nil, let samples = try? await quantitySamples(.runningPower, in: window) {
                let watts = samples.map { (time: $0.startDate, value: $0.quantity.doubleValue(for: .watt())) }
                workout.bestPower3 = Efforts.bestAverage(watts, over: 180)
                workout.bestPower12 = Efforts.bestAverage(watts, over: 720)
            }
            if (km ?? 0) >= 1.7, let samples = try? await quantitySamples(.distanceWalkingRunning, in: window) {
                // The Watch's own samples only: the phone records the same run too, and adding both
                // would count the distance twice.
                let watch = samples.filter { $0.sourceRevision.productType?.hasPrefix("Watch") == true }
                workout.bestMileMinutes = Efforts.fastest(watch.map { (end: $0.endDate, metres: $0.quantity.doubleValue(for: .meter())) },
                                                          metres: 1609.344)
            }
        }
        return workout
    }

    private func quantitySamples(_ id: HKQuantityTypeIdentifier, in window: NSPredicate) async throws -> [HKQuantitySample] {
        try await HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(id), predicate: window)], sortDescriptors: [SortDescriptor(\.startDate)]
        ).result(for: store)
    }

    private static func activity(_ type: HKWorkoutActivityType) -> Activity {
        switch type {
        case .running: .running
        case .walking: .walking
        case .hiking: .hiking
        default: .other
        }
    }

    enum LoadError: LocalizedError {
        case healthUnavailable

        var errorDescription: String? { "Health data isn't available on this device." }
    }
}
