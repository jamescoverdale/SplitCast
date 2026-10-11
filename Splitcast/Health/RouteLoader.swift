import CoreLocation
import HealthKit

nonisolated struct Coordinate: Sendable, Hashable, Codable {
    let latitude: Double
    let longitude: Double

    var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

/// Reads a workout's GPS route from Health on demand, thinned for drawing. Kept in memory and in
/// the Caches folder (iOS may clear that; routes are then read again).
actor RouteLoader {
    static let shared = RouteLoader()
    /// Detail kept in the caches; enough for a full-screen map.
    static let storedPoints = 400

    private let store = HKHealthStore()
    private var cache: [UUID: [Coordinate]] = [:]
    private let directory = URL.cachesDirectory.appending(path: "routes")

    /// Empty when the workout has no route (treadmill runs, runs recorded without GPS).
    func route(for workoutID: UUID, maxPoints: Int = storedPoints) async -> [Coordinate] {
        if let cached = cache[workoutID] { return Self.thin(cached, to: maxPoints) }
        let file = directory.appending(path: "\(workoutID).json")
        let stored: [Coordinate]
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([Coordinate].self, from: data) {
            stored = saved
        } else {
            guard let all = try? await load(workoutID) else { return [] }
            stored = Self.thin(all, to: Self.storedPoints)
            // An empty route may only mean route access isn't granted yet, so don't keep it on disk.
            if !stored.isEmpty {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? JSONEncoder().encode(stored).write(to: file, options: .atomic)
            }
        }
        cache[workoutID] = stored
        return Self.thin(stored, to: maxPoints)
    }

    /// Every nth point, keeping the last so the route ends where the run did.
    static func thin(_ points: [Coordinate], to maxPoints: Int) -> [Coordinate] {
        let step = max(1, Int((Double(points.count) / Double(maxPoints)).rounded(.up)))
        var out = stride(from: 0, to: points.count, by: step).map { points[$0] }
        if let last = points.last, out.last != last { out.append(last) }
        return out
    }

    private func load(_ workoutID: UUID) async throws -> [Coordinate] {
        let workouts = try await HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForObject(with: workoutID))], sortDescriptors: []
        ).result(for: store)
        guard let workout = workouts.first else { return [] }
        let routes = try await HKSampleQueryDescriptor(
            predicates: [.sample(type: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout))],
            sortDescriptors: [SortDescriptor(\.startDate)]
        ).result(for: store)
        var out: [Coordinate] = []
        for case let route as HKWorkoutRoute in routes {
            for try await location in HKWorkoutRouteQueryDescriptor(route).results(for: store) {
                out.append(Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
            }
        }
        return out
    }
}
