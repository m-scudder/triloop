import SwiftData
import SwiftUI
import UIKit

struct NotificationSettingsView: View {
    @Query(sort: \WeeklyPlan.startDate) private var plans: [WeeklyPlan]

    @AppStorage(TrainingNotificationPreferences.enabledKey) private var enabled = false
    @AppStorage(TrainingNotificationPreferences.workoutRemindersKey) private var workoutReminders = false
    @AppStorage(TrainingNotificationPreferences.feedbackRemindersKey) private var feedbackReminders = false
    @AppStorage(TrainingNotificationPreferences.planReadyKey) private var planReady = false
    @AppStorage(TrainingNotificationPreferences.reminderHourKey) private var reminderHour = 8
    @AppStorage(TrainingNotificationPreferences.reminderMinuteKey) private var reminderMinute = 0

    @State private var authorization: TrainingNotificationAuthorization = .notDetermined
    @State private var isRequesting = false

    var body: some View {
        List {
            Section {
                LabeledContent("Permission", value: authorizationText)

                switch authorization {
                case .notDetermined:
                    Button("Enable notifications") { requestPermission() }
                        .disabled(isRequesting)
                case .denied:
                    Button("Open iOS Settings") { openSystemSettings() }
                case .authorized:
                    Toggle("Training notifications", isOn: $enabled)
                }
            } footer: {
                Text("TriLoop asks only after you choose to enable reminders.")
            }

            if authorization == .authorized && enabled {
                Section("Training days") {
                    Toggle("Workout reminders", isOn: $workoutReminders)
                    if workoutReminders {
                        DatePicker(
                            "Reminder time",
                            selection: reminderTime,
                            displayedComponents: .hourAndMinute
                        )
                    }
                }

                Section("Training loop") {
                    Toggle("Report reminders", isOn: $feedbackReminders)
                    Toggle("Next week ready", isOn: $planReady)
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task { authorization = await TrainingNotificationManager.shared.authorizationStatus() }
        .onChange(of: enabled) { _, _ in reschedule() }
        .onChange(of: workoutReminders) { _, _ in reschedule() }
        .onChange(of: feedbackReminders) { _, _ in reschedule() }
        .onChange(of: reminderHour) { _, _ in reschedule() }
        .onChange(of: reminderMinute) { _, _ in reschedule() }
    }

    private var authorizationText: String {
        switch authorization {
        case .notDetermined: "Not set up"
        case .denied: "Off in iOS"
        case .authorized: enabled ? "On" : "Paused"
        }
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: reminderHour,
                    minute: reminderMinute,
                    second: 0,
                    of: .now
                ) ?? .now
            },
            set: { value in
                let components = Calendar.current.dateComponents([.hour, .minute], from: value)
                reminderHour = components.hour ?? 8
                reminderMinute = components.minute ?? 0
            }
        )
    }

    private func requestPermission() {
        isRequesting = true
        Task {
            authorization = await TrainingNotificationManager.shared.requestAuthorization(
                hour: reminderHour,
                minute: reminderMinute
            )
            isRequesting = false
            if authorization == .authorized {
                enabled = true
                workoutReminders = true
                feedbackReminders = true
                planReady = true
                await TrainingNotificationManager.shared.synchronize(plans: plans)
            }
        }
    }

    private func reschedule() {
        Task { await TrainingNotificationManager.shared.synchronize(plans: plans) }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
