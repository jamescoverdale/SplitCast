import SwiftUI
import WidgetKit

/// The predicted time for the Goal tab's distance, and how close it is to the goal.
struct PredictionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Prediction", provider: PredictionProvider()) { entry in
            PredictionWidgetView(entry: entry)
        }
        .configurationDisplayName("Predicted time")
        .description("Your predicted race time and how close you are to your goal.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

struct PredictionEntry: TimelineEntry {
    let date: Date
    /// Nil until the app has a prediction to share.
    let snapshot: WidgetSnapshot?
}

/// The app reloads the widgets whenever its figures change; the daily entry only keeps the
/// "data is old" state honest.
struct PredictionProvider: TimelineProvider {
    func placeholder(in context: Context) -> PredictionEntry {
        PredictionEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (PredictionEntry) -> Void) {
        completion(PredictionEntry(date: Date(), snapshot: context.isPreview ? WidgetSnapshot.load() ?? .sample : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PredictionEntry>) -> Void) {
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        completion(Timeline(entries: [PredictionEntry(date: now, snapshot: WidgetSnapshot.load())], policy: .after(tomorrow)))
    }
}
