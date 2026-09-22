import SwiftUI

struct ConnectionsStepView: View {
    @Bindable var model: OnboardingModel
    @Environment(\.healthProvider) private var health
    @StateObject private var watch = WatchAvailability.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var healthStatus: HealthAuthorizationStatus = .notDetermined
    @State private var watchStatus: WorkoutSchedulingAuthorization = .notDetermined
    @State private var message: String?
    @State private var isConnecting = false
    private let scheduler = WorkoutKitScheduler()

    private var healthDone: Bool {
        healthStatus == .authorized || healthStatus == .unavailable
    }

    private var watchDone: Bool {
        !watch.canSchedule
            || !scheduler.isSupported
            || watchStatus == .authorized
            || watchStatus == .restricted
    }

    private var shouldShowNotNow: Bool {
        !(healthDone && watchDone)
    }

    var body: some View {
        OnboardingStep(primaryTitle: "See My Week", primary: model.advance) {
            OnboardingHeader(
                title: "Connect your training",
                subtitle: "Optional. Connect anytime."
            )

            VStack(alignment: .leading, spacing: 10) {
                Label("Apple Health", systemImage: "heart.fill")
                    .font(.headline)

                Text("Import completed workouts.")
                    .foregroundStyle(.secondary)

                if healthStatus == .authorized {
                    Label("Connected", systemImage: "checkmark.circle")
                } else if healthStatus == .unavailable {
                    Text("Unavailable on this device.")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Connect Apple Health", action: connectHealth)
                        .buttonStyle(SecondaryActionButtonStyle())
                        .disabled(isConnecting)
                }
            }

            if watch.canSchedule {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Label("Apple Watch", systemImage: "applewatch")
                        .font(.headline)

                    Text("Send workouts to Watch.")
                        .foregroundStyle(.secondary)

                    if !scheduler.isSupported || watchStatus == .restricted {
                        Text("Workout scheduling unavailable.")
                            .foregroundStyle(.secondary)
                    } else if watchStatus == .authorized {
                        Label("Connected", systemImage: "checkmark.circle")
                    } else {
                        Button("Set Up Apple Watch", action: connectWatch)
                            .buttonStyle(SecondaryActionButtonStyle())
                            .disabled(isConnecting)
                    }
                }
            }

            if let message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote)
            }

            if shouldShowNotNow {
                Button("Not Now", action: model.advance)
                    .frame(minHeight: 44)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            watch.refresh()
            healthStatus = await health.authorizationStatus
            watchStatus = await scheduler.authorizationState()
        }
    }

    private func connectHealth() {
        isConnecting = true
        Task {
            defer { isConnecting = false }
            do {
                try await health.requestAuthorization()
                healthStatus = await health.authorizationStatus
                message = healthStatus == .authorized ? nil : "Health not connected."
            } catch {
                message = "Health connection failed."
            }
        }
    }

    private func connectWatch() {
        guard watch.canSchedule else { return }
        isConnecting = true

        Task {
            defer { isConnecting = false }
            watchStatus = await scheduler.requestAuthorization()
            message = watchStatus == .authorized ? nil : "Watch setup incomplete."
        }
    }
}
