import AppIntents
import SwiftUI
import WidgetKit

/// The predicted time for a chosen distance, and how close it is to the goal.
struct PredictionWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "Prediction", intent: ChooseDistanceIntent.self, provider: PredictionProvider()) { entry in
            PredictionWidgetView(entry: entry)
        }
        .configurationDisplayName("Predicted time")
        .description("Your predicted race time and how close you are to your goal. Touch and hold to choose the distance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

enum WidgetDistance: String, AppEnum {
    case goalTab, fiveK, tenK, half, marathon

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Distance"
    static let caseDisplayRepresentations: [WidgetDistance: DisplayRepresentation] = [
        .goalTab: "Same as Goal tab", .fiveK: "5k", .tenK: "10k", .half: "Half marathon", .marathon: "Marathon",
    ]

    /// Nil follows the Goal tab.
    var km: Double? {
        switch self {
        case .goalTab: nil
        case .fiveK: 5
        case .tenK: 10
        case .half: 21.0975
        case .marathon: 42.195
        }
    }
}

struct ChooseDistanceIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Distance"
    static let description = IntentDescription("Choose which race distance the widget shows.")

    @Parameter(title: "Distance", default: .goalTab)
    var distance: WidgetDistance
}

struct PredictionEntry: TimelineEntry {
    let date: Date
    /// Nil until the app has a prediction to share.
    let snapshot: WidgetSnapshot?
}

/// The app reloads the widgets whenever its figures change; the daily entry only keeps the
/// "data is old" state honest.
struct PredictionProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PredictionEntry {
        PredictionEntry(date: Date(), snapshot: .sample)
    }

    func snapshot(for configuration: ChooseDistanceIntent, in context: Context) async -> PredictionEntry {
        let data = WidgetData.load() ?? (context.isPreview ? .sample : nil)
        return PredictionEntry(date: Date(), snapshot: data?.snapshot(km: configuration.distance.km))
    }

    func timeline(for configuration: ChooseDistanceIntent, in context: Context) async -> Timeline<PredictionEntry> {
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        let entry = PredictionEntry(date: now, snapshot: WidgetData.load()?.snapshot(km: configuration.distance.km))
        return Timeline(entries: [entry], policy: .after(tomorrow))
    }
}
