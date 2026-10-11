import Foundation
import Observation

@Observable
final class AppModel {
    enum State {
        case notStarted
        case loading(LoadProgress)
        case ready(FitnessData)
        case failed(String)
    }

    /// How much history a full read covers. Comparisons and the Goal chart look back at most 5 years.
    static let years = 5

    var state: State = .notStarted
    /// When the data on screen was read from Health.
    private(set) var lastRefreshed: Date?
    private(set) var isRefreshing = false
    /// Set when a refresh fails while older data is still on screen.
    private(set) var refreshError: String?

    private let loader = HealthLoader()

    var isStale: Bool {
        lastRefreshed.map { FitnessCache.isStale(savedAt: $0) } ?? false
    }

    var data: FitnessData? {
        if case .ready(let data) = state { data } else { nil }
    }

    /// Shows the saved copy if there is one (background updates keep it current); reads Health
    /// only when there isn't.
    func start() async {
        if case .ready = state { return }
        if let cache = await Task.detached(operation: { FitnessCache.load() }).value {
            apply(cache)
            // Saved by an older version that didn't read everything the app now uses.
            if !cache.isCurrent { await refresh(full: true) }
        } else {
            await refresh()
        }
    }

    /// Picks up a copy saved by a background update since the app last looked.
    func reloadIfNewer() async {
        guard let cache = await Task.detached(operation: { FitnessCache.load() }).value,
              cache.savedAt > (lastRefreshed ?? .distantPast) else { return }
        apply(cache)
    }

    /// Reads Health and saves the result. Normally just the last few weeks, merged into the saved
    /// copy; `full` re-reads all history. Data already on screen stays there meanwhile.
    func refresh(full: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        refreshError = nil
        defer { isRefreshing = false }
        let hasData = data != nil
        if !hasData { state = .loading(.connecting) }
        do {
            try await loader.requestAccess()
            let saved = full ? nil : await Task.detached(operation: { FitnessCache.load() }).value
            let cache: FitnessCache
            if let saved {
                let since = saved.refreshStart()
                let fresh = try await loader.read(from: since)
                cache = saved.merged(days: fresh.days, workouts: fresh.workouts, since: since)
            } else {
                let calendar = Calendar.current
                let start = calendar.date(byAdding: .year, value: -Self.years, to: calendar.startOfDay(for: Date()))!
                let fresh = try await loader.read(from: start) { progress in
                    await MainActor.run { if !hasData { self.state = .loading(progress) } }
                }
                cache = FitnessCache(days: fresh.days, workouts: fresh.workouts)
            }
            try? await Task.detached { try cache.save() }.value
            apply(cache)
        } catch {
            if hasData { refreshError = error.localizedDescription } else { state = .failed(error.localizedDescription) }
        }
    }

    /// Updates the widgets from what's on screen, e.g. after a goal or result changes.
    func publishWidgets() {
        guard let data, let lastRefreshed else { return }
        Task.detached(priority: .utility) { WidgetPublisher.publish(data, readAt: lastRefreshed) }
    }

    private func apply(_ cache: FitnessCache) {
        lastRefreshed = cache.savedAt
        state = .ready(FitnessData(days: cache.days, workouts: cache.workouts))
        publishWidgets()
    }
}
