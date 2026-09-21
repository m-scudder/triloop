import AVFoundation
import Combine
import CoreMedia
import Foundation

/// Plays real, pre-rendered coaching as one finite media programme. The audio
/// hardware owns its clock, so locking the screen cannot delay the next cue.
@MainActor
final class WorkoutAudioCoach: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var isPreparing = false
    @Published private(set) var isPlaying = false
    @Published private(set) var message: String?
    var onPause: (() -> Void)?
    var onFinished: (() -> Void)?

    private var player: AVAudioPlayer?
    private var directory: URL?
    private var windows: [ClosedRange<TimeInterval>] = []
    private var duckTimer: Timer?
    private var isDucking = false
    private(set) var timeline: WorkoutCoachingTimeline?
    var position: TimeInterval { player?.currentTime ?? 0 }
    var isPrepared: Bool { player != nil }

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(interrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        center.addObserver(self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(mediaReset), name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
    }

    func prepare(plan: WorkoutExecutionPlan, countdowns: Bool, volume: Float) async throws {
        guard let timeline = WorkoutCoachingTimeline(plan: plan, countdowns: countdowns) else {
            throw CoachError.unsupported
        }
        isPreparing = true
        message = nil
        defer { isPreparing = false }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("AtheviaAudio-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let rendered = try await CoachingAudioRenderer.render(timeline, in: folder)
            try Task.checkCancellation()
            let player = try AVAudioPlayer(contentsOf: rendered.url)
            player.volume = min(max(volume, 0.1), 1)
            player.delegate = self
            guard player.prepareToPlay() else { throw CoachError.playback }
            self.player = player
            self.timeline = timeline
            self.windows = rendered.windows
            self.directory = folder
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    @discardableResult
    func play() -> Bool {
        guard let player else { return false }
        do {
            try configureSession(duck: shouldDuck(at: position))
            try AVAudioSession.sharedInstance().setActive(true)
            guard player.play() else { throw CoachError.playback }
            isPlaying = true
            message = nil
            duckTimer?.invalidate()
            duckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.updateDucking() }
            }
            return true
        } catch {
            pause()
            message = "Audio could not start. Resume to retry, or turn off coaching."
            return false
        }
    }

    func pause() {
        guard player != nil else { return }
        player?.pause()
        isPlaying = false
        duckTimer?.invalidate()
        duckTimer = nil
        isDucking = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func seekToStep(_ index: Int) {
        guard let timeline, timeline.stepStarts.indices.contains(index) else { return }
        seek(to: timeline.stepStarts[index])
    }

    func seek(to position: TimeInterval) {
        guard let player else { return }
        let upperBound = max(player.duration - 0.05, 0)
        player.currentTime = min(max(position, 0), upperBound)
        updateDucking()
    }

    func setVolume(_ volume: Float) {
        player?.volume = min(max(volume, 0.1), 1)
    }

    func stop() {
        pause()
        player?.stop()
        player = nil
        timeline = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        onPause = nil
        onFinished = nil
    }

    private func shouldDuck(at time: TimeInterval) -> Bool {
        windows.contains { $0.contains(time) }
    }

    private func updateDucking() {
        guard isPlaying else { return }
        let duck = shouldDuck(at: position)
        guard duck != isDucking else { return }
        do { try configureSession(duck: duck) }
        catch {
            // Failure to change music mixing must not stop the coach clock.
            message = "Music volume could not be adjusted. Coach cues are still playing."
        }
    }

    private func configureSession(duck: Bool) throws {
        var options: AVAudioSession.CategoryOptions = [.mixWithOthers]
        if duck { options.insert(.duckOthers) }
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: options)
        isDucking = duck
    }

    @objc private func interrupted(_ notification: Notification) {
        guard isPlaying,
              let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        // Require an explicit resume after calls/alarms; never silently skip sets.
        onPause?()
        message = "Workout paused by an audio interruption. Resume when ready."
    }

    @objc private func routeChanged(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable,
              isPlaying else { return }
        onPause?()
        message = "Headphones disconnected. Workout paused."
    }

    @objc private func mediaReset() {
        guard isPrepared else { return }
        onPause?()
        stop()
        message = "Audio was reset by iOS. Coaching has stopped; continue with the on-screen timer."
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard self.player === player else { return }
            if flag {
                self.isPlaying = false
                self.onFinished?()
            } else {
                self.onPause?()
                self.message = "Audio stopped unexpectedly. Resume to retry."
            }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            guard self.player === player else { return }
            self.onPause?()
            self.stop()
            self.message = "Audio could not continue. Resume with the on-screen timer."
        }
    }

    enum CoachError: Error { case unsupported, rendering, playback }
}

@MainActor
private enum CoachingAudioRenderer {
    struct Output {
        let url: URL
        let windows: [ClosedRange<TimeInterval>]
    }

    static func render(_ timeline: WorkoutCoachingTimeline, in folder: URL) async throws -> Output {
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw WorkoutAudioCoach.CoachError.rendering
        }
        var cached: [String: URL] = [:]
        var windows: [ClosedRange<TimeInterval>] = []
        for (index, cue) in timeline.cues.enumerated() {
            try Task.checkCancellation()
            let available = min(10, index + 1 < timeline.cues.count
                ? timeline.cues[index + 1].time - cue.time : 10)
            var selected: AVURLAsset?
            // Never overlap the next set or cut a spoken word in half. Short
            // sets use the step title; if even that cannot fit, offer the timer.
            for text in [cue.text, cue.summaryText, cue.briefText] {
                let url: URL
                if let existing = cached[text] {
                    url = existing
                } else {
                    url = folder.appendingPathComponent(UUID().uuidString + ".caf")
                    try await SpeechFileRenderer.render(text, to: url)
                    cached[text] = url
                }
                let asset = AVURLAsset(url: url)
                let duration = try await asset.load(.duration).seconds
                if duration > 0, duration.isFinite, duration <= available {
                    selected = asset
                    break
                }
            }
            guard let asset = selected else { throw WorkoutAudioCoach.CoachError.unsupported }
            guard let source = try await asset.loadTracks(withMediaType: .audio).first else {
                throw WorkoutAudioCoach.CoachError.rendering
            }
            let length = try await asset.load(.duration).seconds
            guard length > 0, length.isFinite else { throw WorkoutAudioCoach.CoachError.rendering }
            try track.insertTimeRange(
                CMTimeRange(start: .zero, duration: CMTime(seconds: length, preferredTimescale: 600)),
                of: source,
                at: CMTime(seconds: cue.time, preferredTimescale: 600)
            )
            windows.append(cue.time...(cue.time + length))
        }
        let url = folder.appendingPathComponent("coaching.m4a")
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw WorkoutAudioCoach.CoachError.rendering
        }
        try await exporter.export(to: url, as: .m4a)
        let exportedDuration = try await AVURLAsset(url: url).load(.duration).seconds
        guard let expectedDuration = windows.last?.upperBound,
              exportedDuration.isFinite,
              abs(exportedDuration - expectedDuration) < 0.25 else {
            throw WorkoutAudioCoach.CoachError.rendering
        }
        return Output(url: url, windows: windows)
    }
}

/// The synthesizer's buffer callback is not guaranteed to run on the main
/// actor. Serialize file writes and exactly-once continuation completion.
private final class SpeechFileRenderer: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false
    private let url: URL

    private init(url: URL) { self.url = url }

    @MainActor
    static func render(_ text: String, to url: URL) async throws {
        let job = SpeechFileRenderer(url: url)
        let synth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        // Cancels stalled system synthesis as well as user-aborted preparation.
        let timeout = Task {
            try await Task.sleep(for: .seconds(30))
            job.finish(WorkoutAudioCoach.CoachError.rendering)
            synth.stopSpeaking(at: .immediate)
        }
        defer {
            timeout.cancel()
            synth.stopSpeaking(at: .immediate)
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if job.begin(continuation) {
                    synth.write(utterance) { buffer in job.consume(buffer) }
                }
            }
        } onCancel: {
            job.finish(CancellationError())
            Task { @MainActor in synth.stopSpeaking(at: .immediate) }
        }
    }

    private func begin(_ continuation: CheckedContinuation<Void, Error>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if finished {
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        return true
    }

    private func consume(_ buffer: AVAudioBuffer) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        do {
            guard let pcm = buffer as? AVAudioPCMBuffer else { throw WorkoutAudioCoach.CoachError.rendering }
            if pcm.frameLength == 0 {
                let hasAudio = file != nil
                lock.unlock()
                finish(hasAudio ? nil : WorkoutAudioCoach.CoachError.rendering)
                return
            }
            if file == nil {
                file = try AVAudioFile(forWriting: url, settings: pcm.format.settings,
                                       commonFormat: pcm.format.commonFormat,
                                       interleaved: pcm.format.isInterleaved)
            }
            try file?.write(from: pcm)
            lock.unlock()
        } catch {
            lock.unlock()
            finish(error)
        }
    }

    private func finish(_ error: Error? = nil) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        file = nil
        let pending = continuation
        continuation = nil
        lock.unlock()
        if let error { pending?.resume(throwing: error) }
        else { pending?.resume() }
    }
}
