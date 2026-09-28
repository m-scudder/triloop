import SwiftData
import SwiftUI

struct NotificationEnableCard: View {
    let isRequesting: Bool
    let continueAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.badge")
                    .font(.title3)
                    .frame(width: 34, height: 34)
                    .background(AtheviaAdaptiveStyle(.fill.tertiary, gaming: .raisedSurface), in: .circle)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Never miss a workout")
                        .font(.subheadline.weight(.semibold))
                    Text("Get a reminder on training days and when your next week is ready.")
                        .font(.caption)
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                }
            }

            Button(action: continueAction) {
                HStack(spacing: 8) {
                    if isRequesting {
                        ProgressView()
                    }
                    Text("Continue")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(isRequesting)
            .accessibilityIdentifier("notifications.permission.continue")
        }
        .padding(16)
        .background(AtheviaAdaptiveStyle(.fill.tertiary, gaming: .raisedSurface), in: .rect(cornerRadius: 16))
    }
}

struct NotificationSetupSheet: View {
    let onComplete: () -> Void

    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]
    @Environment(\.dismiss) private var dismiss
    @State private var reminderTime: Date
    @State private var isRequesting = false
    @State private var permissionDenied = false
    @State private var hasRequestedPermission = false

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        let calendar = Calendar.current
        _reminderTime = State(
            initialValue: calendar.date(
                bySettingHour: TrainingNotificationPreferences.reminderHour,
                minute: TrainingNotificationPreferences.reminderMinute,
                second: 0,
                of: .now
            ) ?? .now
        )
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "bell.badge.fill")
                        .font(.largeTitle)
                    Text("Training reminders")
                        .font(.title2.weight(.semibold))
                    Text("Choose when Athevia should remind you on days that have a planned workout.")
                        .font(.subheadline)
                        .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))
                }

                DatePicker(
                    "Training-day reminder",
                    selection: $reminderTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)

                Text("Workout reminders move automatically when your plan changes. Completed or skipped sessions are removed.")
                    .font(.footnote)
                    .foregroundStyle(AtheviaAdaptiveStyle(.secondary, gaming: .secondaryText))

                Spacer()

                Button("Continue") { enable() }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(isRequesting)
                    .accessibilityIdentifier("notifications.setup.continue")
            }
            .padding(20)
            .atheviaScreen()
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Notifications are off", isPresented: $permissionDenied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("iOS did not grant notification access. You can enable it later from Settings.")
            }
        }
        .atheviaScreen()
        .interactiveDismissDisabled(!hasRequestedPermission)
    }

    private func enable() {
        isRequesting = true
        let components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        Task {
            let status = await TrainingNotificationManager.shared.requestAuthorization(
                hour: components.hour ?? 8,
                minute: components.minute ?? 0
            )
            isRequesting = false
            hasRequestedPermission = true

            guard status == .authorized else {
                permissionDenied = true
                return
            }

            await TrainingNotificationManager.shared.synchronize(plans: plans)
            onComplete()
            dismiss()
        }
    }
}
