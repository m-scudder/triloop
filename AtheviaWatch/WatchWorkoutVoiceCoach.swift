import AVFoundation
import Foundation

@MainActor
final class WatchWorkoutVoiceCoach {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var settings: WatchCoachingSettingsPayload = .defaults
    private(set) var isEnabled = true

    func configure(_ settings: WatchCoachingSettingsPayload) {
        self.settings = settings
        isEnabled = settings.enabled
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled {
            stop()
        }
    }

    func announceStart(_ step: WatchExecutableWorkoutStep?) {
        guard let step else { return }
        speak(stepAnnouncement(step, prefix: "Workout started."))
    }

    func announceStep(_ step: WatchExecutableWorkoutStep?) {
        guard let step else { return }
        speak(stepAnnouncement(step, prefix: nil))
    }

    func announceResume(_ step: WatchExecutableWorkoutStep?) {
        guard let step else { return }
        speak(stepAnnouncement(step, prefix: "Resume."))
    }

    func announceCountdown(nextStep: WatchExecutableWorkoutStep?) {
        guard settings.countdowns else { return }

        var text = "Ten seconds remaining."
        if let nextStep {
            text += " Next: \(nextStep.title)."
        } else {
            text += " Then your workout is complete."
        }
        speak(text)
    }

    func announceCompletion() {
        speak("Workout complete. Well done.")
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func stepAnnouncement(
        _ step: WatchExecutableWorkoutStep,
        prefix: String?
    ) -> String {
        var parts: [String] = []
        if let prefix {
            parts.append(prefix)
        }

        parts.append(step.title + ".")

        if let duration = step.durationSeconds {
            parts.append(spokenDuration(duration) + ".")
        } else if let distance = step.distanceMeters {
            parts.append(spokenDistance(distance) + ".")
        }

        if let repetition = step.repetitionLabel {
            parts.append(repetition + ".")
        }

        if let intensity = step.targetIntensity {
            parts.append(intensity.displayName + " effort.")
        }

        if let instructions = step.instructions,
           !instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(String(instructions.prefix(180)))
        }

        return parts.joined(separator: " ")
    }

    private func speak(_ text: String) {
        guard isEnabled, !text.isEmpty else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.mixWithOthers, .duckOthers]
            )
            try session.setActive(true)
        } catch {
            // Speech can still succeed with the current route/session.
        }

        synthesizer.stopSpeaking(at: .immediate)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = Float(min(max(settings.volume, 0.1), 1))
        synthesizer.speak(utterance)
    }

    private func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 1)
        let minutes = total / 60
        let remainder = total % 60
        var parts: [String] = []

        if minutes > 0 {
            parts.append("\(minutes) " + (minutes == 1 ? "minute" : "minutes"))
        }
        if remainder > 0 {
            parts.append("\(remainder) " + (remainder == 1 ? "second" : "seconds"))
        }
        return parts.joined(separator: " and ")
    }

    private func spokenDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            let kilometres = meters / 1000
            return String(format: "%.1f kilometres", kilometres)
        }
        return "\(Int(meters.rounded())) metres"
    }
}
