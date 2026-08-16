import SwiftData
import SwiftUI

@main
struct TriLoopApp: App {
    private let modelContainer: ModelContainer

    init() {
        let (container, _) = TriLoopModelContainer.makeWithFallback()
        modelContainer = container
        SeedDataInstaller.installIfNeeded(in: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
