import SwiftUI

enum AudioCoachingPreferences {
    static let enabledKey = SharedAudioCoachingPreferences.enabledKey
    static let countdownsKey = SharedAudioCoachingPreferences.countdownsKey
    static let volumeKey = SharedAudioCoachingPreferences.volumeKey
}

struct AudioCoachingSettingsView: View {
    @AppStorage(AudioCoachingPreferences.enabledKey) private var enabled = true
    @AppStorage(AudioCoachingPreferences.countdownsKey) private var countdowns = true
    @AppStorage(AudioCoachingPreferences.volumeKey) private var volume = 0.8

    var body: some View {
        Form {
            Group {
            Section {
                Toggle("Spoken workout guidance", isOn: $enabled)
                    .toggleStyle(AtheviaToggleStyle())
                Toggle("Ten-second countdowns", isOn: $countdowns)
                    .toggleStyle(AtheviaToggleStyle())
                    .disabled(!enabled)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Coach volume")
                    Slider(value: $volume, in: 0.1...1)
                        .accessibilityLabel("Coach volume")
                        .disabled(!enabled)
                }
            }
            }
            .atheviaListRow()
        }
        .atheviaList()
        .atheviaScreen()
        .navigationTitle("Audio coaching")
        .navigationBarTitleDisplayMode(.inline)
    }
}

