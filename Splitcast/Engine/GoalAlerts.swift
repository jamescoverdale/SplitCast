import Foundation

/// How close a prediction is to its goal, in steps worth telling the user about.
nonisolated enum GoalLevel: Int, Codable, Sendable, Comparable {
    case far, within10, within5, within2, reached

    static func < (a: GoalLevel, b: GoalLevel) -> Bool { a.rawValue < b.rawValue }

    static func of(predicted: Double, goal: Double) -> GoalLevel {
        let gap = (predicted - goal) / goal * 100
        return gap <= 0 ? .reached : gap <= 2 ? .within2 : gap <= 5 ? .within5 : gap <= 10 ? .within10 : .far
    }
}

/// What the alerts remember between checks. Saved by the app.
nonisolated struct GoalAlertState: Codable, Sendable {
    struct Tracked: Codable, Sendable {
        var goal: Double
        var level: GoalLevel
    }

    /// Last level seen for each distance, keyed by `GoalAlerts.key(km)`.
    var tracked: [String: Tracked] = [:]
    /// When each distance and level last sent an alert, keyed by `GoalAlerts.key(km, level)`.
    var lastSent: [String: Date] = [:]
    var lastAnySent: Date?
}

nonisolated struct GoalAlert: Sendable, Equatable {
    let km: Double
    let level: GoalLevel
    let title: String
    let body: String
}

/// Decides when a goal is worth an alert, without spamming: only when the prediction moves up
/// into a closer level, each level at most once every 30 days per distance, and at most one alert
/// a day. Getting less fit never alerts. Setting or changing a goal quietly resets the baseline.
nonisolated enum GoalAlerts {
    static let levelCooldown: TimeInterval = 30 * 86_400
    static let anyCooldown: TimeInterval = 86_400

    struct Check: Sendable {
        let km: Double
        let distance: String
        let goal: Double
        let predicted: Double
    }

    static func key(_ km: Double) -> String { "\(Int(km * 1000))m" }
    static func key(_ km: Double, _ level: GoalLevel) -> String { "\(key(km))-\(level.rawValue)" }

    /// Updates `state` with the latest predictions and returns the alert to send, if any. News held
    /// back by the one-a-day limit keeps its old level, so it's sent on a later day instead.
    static func evaluate(_ checks: [Check], state: inout GoalAlertState, now: Date = Date()) -> GoalAlert? {
        var candidates: [(check: Check, level: GoalLevel, previous: GoalAlertState.Tracked)] = []
        for c in checks {
            let level = GoalLevel.of(predicted: c.predicted, goal: c.goal)
            let previous = state.tracked[key(c.km)]
            state.tracked[key(c.km)] = .init(goal: c.goal, level: level)
            guard let previous, previous.goal == c.goal, level > previous.level, level != .far else { continue }
            if let sent = state.lastSent[key(c.km, level)], now.timeIntervalSince(sent) < levelCooldown { continue }
            candidates.append((c, level, previous))
        }
        let canSend = state.lastAnySent.map { now.timeIntervalSince($0) >= anyCooldown } ?? true
        let best = canSend ? candidates.max(by: { $0.level < $1.level }) : nil
        for held in candidates where held.check.km != best?.check.km {
            state.tracked[key(held.check.km)] = held.previous
        }
        guard let best else { return nil }
        state.lastSent[key(best.check.km, best.level)] = now
        state.lastAnySent = now
        return message(best.check, best.level)
    }

    static func message(_ c: Check, _ level: GoalLevel) -> GoalAlert {
        let title = goalTitle(goal: c.goal, distance: c.distance)
        let Title = title.prefix(1).uppercased() + title.dropFirst()
        let predicted = Format.clock(c.predicted)
        let toGo = Format.clock(max(c.predicted - c.goal, 0))
        switch level {
        case .reached:
            return GoalAlert(km: c.km, level: level, title: "\(Title) is on",
                             body: "Your predicted \(c.distance) is \(predicted), inside your \(Format.clock(c.goal)) goal.")
        case .within2:
            return GoalAlert(km: c.km, level: level, title: "Almost there: \(title)",
                             body: "Predicted \(predicted), just \(toGo) from your goal.")
        case .within5:
            return GoalAlert(km: c.km, level: level, title: "Closing in on \(title)",
                             body: "Predicted \(predicted), \(toGo) to go.")
        case .within10, .far:
            return GoalAlert(km: c.km, level: level, title: "\(Title) is in sight",
                             body: "Predicted \(predicted), within 10% of your goal.")
        }
    }

    /// "Sub-20 5k" for round goals, else "your 5k goal".
    static func goalTitle(goal: Double, distance: String) -> String {
        let whole = (goal * 60).rounded().truncatingRemainder(dividingBy: 60) == 0
        guard whole else { return "your \(distance) goal" }
        let minutes = Int(goal.rounded())
        let label = minutes < 60 ? "\(minutes)" : String(format: "%d:%02d", minutes / 60, minutes % 60)
        return "Sub-\(label) \(distance)"
    }
}
