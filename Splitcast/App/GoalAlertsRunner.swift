import Foundation
import UserNotifications

/// Sends goal alerts as local notifications, created on the iPhone. The rules (when something is
/// worth saying, and how not to repeat it) live in `GoalAlerts`.
nonisolated enum GoalAlertsRunner {
    static func check(_ data: FitnessData, inputs: GoalInputs) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Setting.goalAlerts) else { return }
        let checks = Predictor.standardDistances.compactMap { d -> GoalAlerts.Check? in
            guard let goal = GoalInputs.goal(for: d.km), let (_, prediction) = inputs.prediction(data, km: d.km) else { return nil }
            let name = d.km > 10 ? d.name.lowercased() : d.name
            return GoalAlerts.Check(km: d.km, distance: name, goal: goal, predicted: prediction.minutes)
        }
        var state = defaults.data(forKey: Setting.goalAlertState)
            .flatMap { try? JSONDecoder().decode(GoalAlertState.self, from: $0) } ?? GoalAlertState()
        let alert = GoalAlerts.evaluate(checks, state: &state)
        defaults.set(try? JSONEncoder().encode(state), forKey: Setting.goalAlertState)
        guard let alert else { return }

        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "goal-\(GoalAlerts.key(alert.km, alert.level))", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Asks for permission to notify. False if the user declines (or declined before).
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
}
