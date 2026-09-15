import SwiftUI

struct ConnectionsStepView: View {
    @Bindable var model: OnboardingModel
    @Environment(\.healthProvider) private var health
    @State private var healthStatus: HealthAuthorizationStatus = .notDetermined
    @State private var watchStatus: WorkoutSchedulingAuthorization = .notDetermined
    @State private var message: String?
    @State private var isConnecting = false
    private let scheduler = WorkoutKitScheduler()

    var body: some View {
        OnboardingStep(primaryTitle: "See My Week", primary: model.advance) {
            OnboardingHeader(title: "Connect your training", subtitle: "Optional. You can connect later in Settings.")
            VStack(alignment: .leading, spacing: 12) {
                Label("Apple Health", systemImage: "heart.fill").font(.headline)
                Text("Let TriLoop learn from your workouts automatically.")
                if healthStatus == .authorized {
                    Label("Connected", systemImage: "checkmark.circle")
                } else if healthStatus == .unavailable {
                    Text("Not available on this device. You can report sessions yourself.")
                } else {
                    Button("Connect Apple Health", action: connectHealth)
                        .buttonStyle(SecondaryActionButtonStyle())
                        .disabled(isConnecting)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Label("Apple Watch", systemImage: "applewatch").font(.headline)
                Text("Send your sessions to the Workout app on your wrist.")
                if !scheduler.isSupported || watchStatus == .restricted {
                    Text("Workout scheduling is unavailable on this device.")
                } else if watchStatus == .authorized {
                    Label("Scheduling allowed", systemImage: "checkmark.circle")
                } else {
                    Button("Set Up Apple Watch", action: connectWatch)
                        .buttonStyle(SecondaryActionButtonStyle())
                        .disabled(isConnecting)
                }
            }
            if let message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote)
            }
            Button("Not Now", action: model.advance)
                .frame(minHeight: 44)
        }
        .task {
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
                message = healthStatus == .authorized ? nil : "Health is not connected. You can continue without it."
            } catch {
                message = "Could not connect Apple Health. You can continue and try later in Settings."
            }
        }
    }

    private func connectWatch() {
        isConnecting = true
        Task {
            defer { isConnecting = false }
            watchStatus = await scheduler.requestAuthorization()
            message = watchStatus == .authorized ? nil : "Watch scheduling is not enabled. You can continue without it."
        }
    }
}