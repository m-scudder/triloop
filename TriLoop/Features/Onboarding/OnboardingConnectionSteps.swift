import SwiftUI

/// Explains before it asks. The permission sheet on its own tells the athlete
/// nothing about why TriLoop wants the data.
struct HealthStepView: View {
    @Bindable var model: OnboardingModel
    @State private var status: HealthAuthorizationStatus = .notDetermined
    @State private var message: String?
    @Environment(\.healthProvider) private var health

    private struct DataUse: Identifiable {
        let symbol: String
        let title: String
        let detail: String

        var id: String { title }
    }

    private let uses = [
        DataUse(symbol: "figure.run", title: "Completed workouts", detail: "So a session you have done links itself to the plan."),
        DataUse(symbol: "heart.fill", title: "Heart rate", detail: "To show how hard a session actually was."),
        DataUse(symbol: "ruler", title: "Distance and steps", detail: "To compare what you did against what was prescribed."),
        DataUse(symbol: "figure.pool.swim", title: "Swim lengths", detail: "To read your sets and rests in the pool.")
    ]

    private var skip: OnboardingSecondaryAction? {
        status == .authorized ? nil : OnboardingSecondaryAction("Skip for now", action: model.advance)
    }

    var body: some View {
        OnboardingStep(
            primaryTitle: status == .authorized ? "Continue" : "Connect Apple Health",
            secondary: skip,
            primary: primaryAction
        ) {
            OnboardingHeader(
                title: "Connect Apple Health",
                subtitle: "TriLoop reads what you have already recorded, so you never log a workout twice."
            )

            VStack(spacing: 12) {
                ForEach(uses) { use in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: use.symbol)
                            .font(.body)
                            .foregroundStyle(.tint)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(use.title).font(.subheadline.weight(.medium))
                            Text(use.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            Text("TriLoop only reads. Nothing is written back to Health, and nothing leaves your device.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task { status = await health.authorizationStatus }
    }

    private func primaryAction() {
        guard status != .authorized else {
            model.advance()
            return
        }
        connect()
    }

    /// A refusal is not a dead end: onboarding continues and Settings can
    /// connect later.
    private func connect() {
        Task {
            do {
                try await health.requestAuthorization()
                status = await health.authorizationStatus
                model.advance()
            } catch HealthDataError.unavailableOnThisDevice {
                message = "Apple Health is not available on this device. You can still use TriLoop and report sessions yourself."
            } catch {
                message = "Could not connect to Apple Health: \(error.localizedDescription). You can connect later in Settings."
            }
        }
    }
}

struct WatchStepView: View {
    @Bindable var model: OnboardingModel
    @State private var authorization: WorkoutSchedulingAuthorization = .notDetermined
    @State private var message: String?

    private let scheduler = WorkoutKitScheduler()

    private var skip: OnboardingSecondaryAction? {
        authorization == .authorized ? nil : OnboardingSecondaryAction("Not now", action: model.advance)
    }

    var body: some View {
        OnboardingStep(
            primaryTitle: authorization == .authorized ? "Continue" : "Allow Workout Scheduling",
            secondary: skip,
            primary: primaryAction
        ) {
            OnboardingHeader(
                title: "Train with Apple Watch",
                subtitle: "TriLoop can send each session to the Workout app, so your watch already knows the intervals."
            )

            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Structured sessions on your wrist", systemImage: "applewatch")
                        .font(.subheadline.weight(.medium))
                    Text("You still start and record workouts in Apple's Workout app. TriLoop just puts the right session there.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if !scheduler.isSupported {
                Text("Workout scheduling is not available on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let message {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task { authorization = await scheduler.authorizationState() }
    }

    private func primaryAction() {
        guard authorization != .authorized, scheduler.isSupported else {
            model.advance()
            return
        }
        request()
    }

    private func request() {
        Task {
            authorization = await scheduler.requestAuthorization()

            switch authorization {
            case .authorized:
                model.advance()
            case .denied:
                message = "Workout scheduling was declined. You can turn it on later in Settings."
            case .restricted:
                message = "Workout scheduling is not available on this device."
            case .notDetermined:
                message = "Workout scheduling could not be set up. You can try again later in Settings."
            }
        }
    }
}
