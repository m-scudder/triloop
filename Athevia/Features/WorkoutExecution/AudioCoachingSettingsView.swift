import SwiftUI

enum AudioCoachingPreferences {
    static let enabledKey = "audioCoachingEnabled"
    static let countdownsKey = "audioCoachingCountdowns"
    static let volumeKey = "audioCoachingVolume"
}

struct AudioCoachingSettingsView: View {
    @AppStorage(AudioCoachingPreferences.enabledKey) private var enabled = true
    @AppStorage(AudioCoachingPreferences.countdownsKey) private var countdowns = true
    @AppStorage(AudioCoachingPreferences.volumeKey) private var volume = 0.8

    var body: some View {
        Form {
            Section {
                Toggle("Spoken workout guidance", isOn: $enabled)
                Toggle("Ten-second countdowns", isOn: $countdowns)
                    .disabled(!enabled)
                VStack(alignment: .leading) {
                    Text("Coach volume")
                    Slider(value: $volume, in: 0.1...1)
                        .accessibilityLabel("Coach volume")
                        .disabled(!enabled)
                }
            } footer: {
                Text("Spoken cues guide timed runs and rides, including repeats and recovery, with your screen locked. Music lowers during cues. Your phone's media volume also controls what you hear.")
            }
            Section {
                Text("Changes apply to your next workout. During a workout, use the speaker button to adjust cue volume. Calls and disconnected headphones pause coaching and the workout; resume when ready.")
                Text("Swimming and workouts with distance-only or manual steps use the on-screen player. Audio coaching currently speaks English. Longer instructions are shortened to fit the set; the full instructions stay on screen.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("Audio coaching")
    }
}
