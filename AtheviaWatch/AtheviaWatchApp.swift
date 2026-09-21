import SwiftUI

@main
struct AtheviaWatchApp: App {
    @StateObject private var store = WatchWorkoutStore()
    @StateObject private var workoutSession = WatchWorkoutSessionManager()

    var body: some Scene {
        WindowGroup {
            WatchWorkoutListView()
                .environmentObject(store)
                .environmentObject(workoutSession)
        }
    }
}
