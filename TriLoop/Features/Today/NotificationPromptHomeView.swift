import SwiftData
import SwiftUI

/// Keeps notification permission contextual: the system prompt is never shown
/// until the athlete explicitly chooses reminders from Home.
struct NotificationPromptHomeView: View {
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]
    @AppStorage(TrainingNotificationPreferences.promptDismissedKey) private var promptDismissed = false
    @State private var authorization: TrainingNotificationAuthorization = .notDetermined
    @State private var showingSetup = false

    var body: some View {
        TodayView()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if shouldOfferSetup {
                    NotificationEnableCard(
                        enable: { showingSetup = true },
                        dismiss: { promptDismissed = true }
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.bar)
                }
            }
            .sheet(isPresented: $showingSetup) {
                NotificationSetupSheet {
                    authorization = .authorized
                    promptDismissed = true
                }
                .presentationDetents([.medium])
            }
            .task {
                authorization = await TrainingNotificationManager.shared.authorizationStatus()
            }
    }

    private var shouldOfferSetup: Bool {
        !plans.isEmpty && !promptDismissed && authorization == .notDetermined
    }
}
