import SwiftData
import SwiftUI
import UIKit

@main
struct SplitcastApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    /// Shared so background updates can read results without the UI, from any thread.
    nonisolated static let container: ModelContainer = {
        do {
            return try ModelContainer(for: RaceResult.self)
        } catch {
            fatalError("Could not open the results store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(Self.container)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BackgroundUpdate.start()
        return true
    }
}
