import SwiftData
import SwiftUI

@main
struct TriLoopApp: App {
    private let modelContainer: ModelContainer
    private let storeOutcome: StoreOutcome
    private let autoImporter: WorkoutAutoImporter

    init() {
        let (container, outcome) = TriLoopModelContainer.makeWithFallback()
        modelContainer = container
        storeOutcome = outcome
        autoImporter = WorkoutAutoImporter(container: container)
        SeedDataInstaller.installIfNeeded(in: container.mainContext)

        // Registered here rather than from a view: HealthKit can launch the app
        // straight into the background, where no scene appears and a view's
        // `task` would never run to re-establish the observer.
        let importer = autoImporter
        if WorkoutAutoImporter.isEnabledByPreference {
            Task { await importer.setEnabled(true) }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(storeOutcome: storeOutcome, autoImporter: autoImporter)
        }
        .modelContainer(modelContainer)
    }
}
