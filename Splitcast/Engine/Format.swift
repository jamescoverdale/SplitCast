import Foundation

nonisolated enum Units: String, CaseIterable, Sendable, Identifiable {
    case miles = "mi"
    case kilometres = "km"

    static let kmPerMile = 1.609344

    var id: String { rawValue }
    var kmPerUnit: Double { self == .miles ? Self.kmPerMile : 1 }
}

nonisolated enum Format {
    /// "47:42" or "1:53:48".
    static func clock(_ minutes: Double) -> String {
        let total = Int((minutes * 60).rounded())
        let h = total / 3600, m = total % 3600 / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// Parses "20:00", "1:42:12" or "47" (minutes). Returns minutes.
    static func parseClock(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":").map { Int($0) }
        guard (1...3).contains(parts.count), parts.allSatisfy({ $0 != nil && $0! >= 0 }) else { return nil }
        if parts.count > 1, parts.dropFirst().contains(where: { $0! > 59 }) { return nil }
        let seconds = parts.reduce(0) { $0 * 60 + $1! } * (parts.count == 1 ? 60 : 1)
        return seconds > 0 ? Double(seconds) / 60 : nil
    }

    static func pace(_ minPerKm: Double, _ units: Units) -> String {
        "\(clock(minPerKm * units.kmPerUnit))/\(units.rawValue)"
    }

    static func distance(_ km: Double, _ units: Units, digits: Int = 1) -> String {
        "\(String(format: "%.\(digits)f", km / units.kmPerUnit)) \(units.rawValue)"
    }

    static func metric(_ m: Metric, _ v: Double, _ units: Units) -> String {
        switch m {
        case .vo2max: String(format: "%.1f", v)
        case .distancePerBeat: String(format: "%.2f m", v)
        case .powerPerBeat: String(format: "%.2f W", v)
        case .criticalPower: String(format: "%.0f W", v)
        case .runVolume: "\(String(format: "%.0f", v / units.kmPerUnit)) \(units.rawValue)/wk"
        case .longestRun: distance(v, units)
        case .climb: "\(Int(v.rounded()).formatted()) m/wk"
        case .fitness: String(format: "%.0f", v)
        case .form: (v >= 0 ? "+" : "") + String(format: "%.0f", v)
        case .restingHR: "\(Int(v.rounded())) bpm"
        case .hrv: "\(Int(v.rounded())) ms"
        case .sleep: "\(Int(v) / 60)h \(String(format: "%02d", Int(v.rounded()) % 60))m"
        }
    }

    /// Chart values in display units: distances in the user's unit, sleep in hours.
    static func chartValue(_ m: Metric, _ v: Double, _ units: Units) -> Double {
        switch m {
        case .runVolume, .longestRun: v / units.kmPerUnit
        case .sleep: v / 60
        default: v
        }
    }

    static func chartUnit(_ m: Metric, _ units: Units) -> String {
        switch m {
        case .runVolume: "\(units.rawValue), cumulative"
        case .longestRun: units.rawValue
        case .climb: "m, cumulative"
        case .sleep: "hours"
        default: ""
        }
    }
}
