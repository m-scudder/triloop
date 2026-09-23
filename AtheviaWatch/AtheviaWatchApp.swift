import SwiftUI
import WatchKit

@main
struct AtheviaWatchApp: App {
    @WKApplicationDelegateAdaptor(AtheviaWatchApplicationDelegate.self)
    private var appDelegate

    @StateObject private var store = WatchWorkoutStore()
    @StateObject private var workoutSession = WatchWorkoutSessionManager()

    var body: some Scene {
        WindowGroup {
            WatchWorkoutListView()
                .symbolRenderingMode(.monochrome)
                .tint(Color.white)
                .environmentObject(store)
                .environmentObject(workoutSession)
                .task {
                    await workoutSession.recoverIfNeeded()
                }
                .onReceive(
                    NotificationCenter.default.publisher(
                        for: .atheviaActiveWorkoutRecoveryRequested
                    )
                ) { _ in
                    Task { @MainActor in
                        await workoutSession.recoverIfNeeded()
                    }
                }
        }
    }
}
