import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [AthleteProfile]

    var body: some View {
        NavigationStack {
            List {
                if let profile = profiles.first {
                    Section("Athlete") {
                        LabeledContent("Experience", value: profile.experienceLevel.displayName)
                        LabeledContent("Started", value: profile.trainingStartDate.formatted(date: .abbreviated, time: .omitted))
                        LabeledContent("Pool length", value: TrainingFormatter.distance(meters: profile.poolLengthMeters))
                    }
                }

                Section("Integrations") {
                    LabeledContent("Apple Health", value: "Not connected")
                    LabeledContent("Apple Watch", value: "Not connected")
                }

                #if DEBUG
                Section("Developer") {
                    Button("Reset seed data", role: .destructive) {
                        SeedDataInstaller.reset(in: modelContext)
                    }
                }
                #endif

                Section {
                    LabeledContent("Data", value: "Stored on this device")
                } footer: {
                    Text("TriLoop keeps your training data on your device. There is no account and no cloud sync.")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container)
}
