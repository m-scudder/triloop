import SwiftData
import SwiftUI

struct NotificationEnableCard: View {
    let enable: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.badge")
                    .font(.title3)
                    .frame(width: 34, height: 34)
                    .background(.fill.tertiary, in: .circle)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Never miss a workout")
                        .font(.subheadline.weight(.semibold))
                    Text("Get a reminder on training days and when your next week is ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button("Enable reminders", action: enable)
                    .buttonStyle(PrimaryActionButtonStyle())
                Button("Not now", action: dismiss)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(.fill.tertiary, in: .rect(cornerRadius: 16))
    }
}

struct NotificationSetupSheet: View {
    let onComplete: () -> Void

    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]
    @Environment(\.dismiss) private var dismiss
    @State private var reminderTime: Date
    @State private var isRequesting = false
    @State private var permissionDenied = false

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
                        .foregroundStyle(.secondary)
                }

                DatePicker(
                    "Training-day reminder",
                    selection: $reminderTime,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.compact)

                Text("Workout reminders move automatically when your plan changes. Completed or skipped sessions are removed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Spacer()

                Button(isRequesting ? "Enabling…" : "Enable reminders") { enable() }
                    .buttonStyle(PrimaryActionButtonStyle())
                    .disabled(isRequesting)
            }
            .padding(20)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Notifications are off", isPresented: $permissionDenied) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("iOS did not grant notification access. You can enable it later from Settings.")
            }
        }
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
