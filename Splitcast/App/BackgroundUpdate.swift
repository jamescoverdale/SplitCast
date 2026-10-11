import Foundation

extension Notification.Name {
    /// Posted after the saved Health copy has been brought up to date in the background.
    static let healthDataUpdated = Notification.Name("healthDataUpdated")
}

/// Keeps the saved Health copy and the widgets current while the app isn't open: HealthKit wakes
/// the app when a workout is saved (and once a day), and this reads just the recent weeks.
enum BackgroundUpdate {
    private static let loader = HealthLoader()
    private static var running = false
    private static var observing = false

    /// Call at every launch, background launches included, so HealthKit's wake-ups are handled.
    static func start() {
        guard Setting.backgroundUpdatesOn, !observing else { return }
        observing = true
        Task { await loader.observeChanges { await run() } }
    }

    /// From the "Update in the background" switch.
    static func setEnabled(_ on: Bool) {
        if on {
            start()
        } else {
            Task { await loader.stopBackgroundDelivery() }
        }
    }

    static func run() async {
        guard Setting.backgroundUpdatesOn else { return }
        // Nothing to update until the app has read Health once in the foreground.
        guard !running, let saved = await Task.detached(operation: { FitnessCache.load() }).value else { return }
        running = true
        defer { running = false }
        let since = saved.refreshStart()
        // Fails while the phone is locked (Health data is encrypted then); the next wake-up retries.
        guard let fresh = try? await loader.read(from: since) else { return }
        let cache = saved.merged(days: fresh.days, workouts: fresh.workouts, since: since)
        try? await Task.detached { try cache.save() }.value
        let data = FitnessData(days: cache.days, workouts: cache.workouts)
        await Task.detached { WidgetPublisher.publish(data, readAt: cache.savedAt) }.value
        NotificationCenter.default.post(name: .healthDataUpdated, object: nil)
    }
}
