import SwiftData
import SwiftUI
import UIKit

/// Keeps notification permission contextual: the system prompt is never shown
/// until the athlete explicitly chooses to continue from Home.
struct NotificationPromptHomeView: View {
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]
    @AppStorage(TrainingNotificationPreferences.promptDismissedKey) private var promptDismissed = false
    @State private var authorization: TrainingNotificationAuthorization = .notDetermined
    @State private var isRequesting = false
    @State private var permissionDenied = false

    var body: some View {
        TodayView()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if shouldOfferSetup {
                    NotificationEnableCard(
                        isRequesting: isRequesting,
                        continueAction: requestPermission
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AtheviaAdaptiveStyle(.bar, gaming: .surface))
                }
            }
            .task {
                authorization = await TrainingNotificationManager.shared.authorizationStatus()
            }
            .alert("Notifications are off", isPresented: $permissionDenied) {
                Button("Open Settings") { openSystemSettings() }
                Button("OK", role: .cancel) {}
            } message: {
                Text("Athevia cannot send training reminders while notification access is off. You can enable it in iOS Settings.")
            }
    }

    private var shouldOfferSetup: Bool {
        !plans.isEmpty && !promptDismissed && authorization == .notDetermined
    }

    private func requestPermission() {
        guard !isRequesting else { return }
        isRequesting = true

        Task { @MainActor in
            let status = await TrainingNotificationManager.shared.requestAuthorization(
                hour: TrainingNotificationPreferences.reminderHour,
                minute: TrainingNotificationPreferences.reminderMinute
            )

            authorization = status
            isRequesting = false

            switch status {
            case .authorized:
                promptDismissed = true
                await TrainingNotificationManager.shared.synchronize(plans: plans)
            case .denied:
                promptDismissed = true
                permissionDenied = true
            case .notDetermined:
                break
            }
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
