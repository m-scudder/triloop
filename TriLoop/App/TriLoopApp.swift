import SwiftData
import SwiftUI

@main
struct TriLoopApp: App {
    private let modelContainer: ModelContainer
    private let storeOutcome: StoreOutcome

    init() {
        let (container, outcome) = TriLoopModelContainer.makeWithFallback()
        modelContainer = container
        storeOutcome = outcome
        SeedDataInstaller.installIfNeeded(in: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView(storeOutcome: storeOutcome)
        }
        .modelContainer(modelContainer)
    }
}
