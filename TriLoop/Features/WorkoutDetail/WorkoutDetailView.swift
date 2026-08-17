import SwiftData
import SwiftUI

struct WorkoutDetailView: View {
    let workout: PlannedWorkout
    var scheduler: any WorkoutScheduling = WorkoutKitScheduler()

    @State private var isPresentingFeedback = false
    @State private var isScheduling = false
    @State private var isScheduled = false
    @State private var scheduleMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if !workout.goal.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Purpose")
                            .font(.subheadline.weight(.semibold))
                        Text(workout.goal)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if workout.orderedSteps.isEmpty {
                    Text("No session today. Rest is part of the plan.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    WorkoutPrescriptionView(workout: workout)
                }

                if let rpe = workout.targetRPE {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionEyebrow(text: "Target effort")
                        Text("RPE \(TrainingFormatter.rpe(rpe)) / \(RPEScale.maximum)")
                            .font(.body.weight(.medium))
                        EffortBar(range: rpe)
                    }
                }

                if let summary = workout.importedSummary {
                    RecordedWorkoutView(workout: workout, summary: summary)
                }

                if workout.acceptsFeedback || workout.discipline.isTrainingSession {
                    actionRow
                }

                if let feedback = workout.feedback {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionEyebrow(text: "Your report")
                        FeedbackSummaryView(feedback: feedback)
                        Button("Clear report", role: .destructive) {
                            workout.clearCompletion()
                        }
                        .font(.subheadline)
                    }
                }

                if let scheduleMessage {
                    Text(scheduleMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshScheduledState() }
        .sheet(isPresented: $isPresentingFeedback) {
            FeedbackSheet(workout: workout)
        }
    }

    /// Primary completion action, with scheduling kept beside it as an icon so
    /// the screen has one obvious next step rather than two competing buttons.
    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 10) {
            if workout.acceptsFeedback {
                Button {
                    isPresentingFeedback = true
                } label: {
                    Text(workout.hasReport ? "Update Report" : "Mark as Done")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.focusSurface, in: .rect(cornerRadius: 12))
                        .foregroundStyle(Color.onFocusSurface)
                }
                .buttonStyle(.plain)
            }

            if workout.discipline.isTrainingSession {
                Button {
                    sendToWatch()
                } label: {
                    Image(systemName: isScheduled ? "checkmark.circle.fill" : "calendar.badge.plus")
                        .font(.headline)
                        .frame(width: 52, height: 52)
                        .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                        .foregroundStyle(isScheduled ? Color.green : .primary)
                }
                .buttonStyle(.plain)
                .disabled(isScheduling || isScheduled)
                .accessibilityLabel(isScheduled ? "On your Apple Watch" : "Add to Apple Watch")
            }
        }
    }

    private func refreshScheduledState() async {
        isScheduled = await scheduler.scheduledWorkoutIDs().contains(workout.id)
    }

    private func sendToWatch() {
        isScheduling = true
        let when = workout.suggestedScheduleDate()

        Task {
            defer { isScheduling = false }
            do {
                try await scheduler.schedule(workout, at: when)
                isScheduled = true
                scheduleMessage = "Scheduled for \(when.formatted(date: .abbreviated, time: .shortened)). Open the Workout app on your Watch to start it."
            } catch WorkoutSchedulingError.notAuthorized {
                scheduleMessage = "TriLoop needs permission to add workouts to your Watch."
            } catch WorkoutSchedulingError.unavailable {
                scheduleMessage = "No paired Apple Watch found."
            } catch WorkoutSchedulingError.notAccepted {
                scheduleMessage = "The Watch did not accept the workout. Check that it is paired and nearby."
            } catch {
                scheduleMessage = "This session cannot be sent to the Watch."
            }
        }
    }

    @ViewBuilder
    private var completionSection: some View {
        if let feedback = workout.feedback {
            LabeledSection(title: "Your report") {
                VStack(alignment: .leading, spacing: 12) {
                    FeedbackSummaryView(feedback: feedback)

                    Button("Clear report", role: .destructive) {
                        workout.clearCompletion()
                    }
                    .font(.subheadline)
                }
            }
        } else {
            Button {
                isPresentingFeedback = true
            } label: {
                Label("Mark complete", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: workout.discipline.symbolName)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .frame(width: 52, height: 52)
                    .background(.fill.tertiary, in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                    if let summary = WorkoutSummaryText.make(for: workout) {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct LabeledSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content
        }
    }
}

#Preview {
    NavigationStack {
        WorkoutDetailView(workout: PreviewData.workout(.running))
    }
    .modelContainer(PreviewData.container)
}
