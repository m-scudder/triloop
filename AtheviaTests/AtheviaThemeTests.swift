import Foundation
import Testing
@testable import Athevia

@Suite("Gaming theme compatibility")
struct AtheviaThemeTests {
    @Test func preferenceDefaultsToClassicAndPersists() throws {
        let suite = "AtheviaThemeTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(AtheviaTheme.stored(in: defaults) == .classic)
        defaults.set(true, forKey: AtheviaTheme.preferenceKey)
        let reopened = try #require(UserDefaults(suiteName: suite))
        #expect(AtheviaTheme.stored(in: reopened) == .gaming)
        defaults.set(false, forKey: AtheviaTheme.preferenceKey)
        #expect(AtheviaTheme.stored(in: reopened) == .classic)
    }

    @Test func palettePersistsAndUnknownValuesFallBack() throws {
        let suite = "AtheviaPaletteTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(GamingPalette.stored(in: defaults) == .neon)
        defaults.set(true, forKey: AtheviaTheme.preferenceKey)
        for palette in GamingPalette.allCases {
            defaults.set(palette.rawValue, forKey: GamingPalette.preferenceKey)
            let reopened = try #require(UserDefaults(suiteName: suite))
            #expect(AtheviaTheme.stored(in: reopened).palette == palette)
        }
        defaults.set("future-palette", forKey: GamingPalette.preferenceKey)
        #expect(GamingPalette.stored(in: defaults) == .neon)
        #expect(GamingPalette.resolve(nil) == .neon)
    }

    @Test func watchPayloadPreservesTrainingAndSupportsOlderDevices() throws {
        let workout = WatchWorkoutPayload(
            id: UUID(), date: Date(timeIntervalSince1970: 1000), discipline: .running,
            title: "Easy run", goal: "Keep it easy", estimatedDurationSeconds: 1800,
            estimatedDistanceMeters: nil, status: .planned, steps: []
        )
        let payload = WatchWorkoutListPayload(
            weekStart: nil, workouts: [workout], coaching: .defaults, gamingThemeEnabled: true, gamingPalette: GamingPalette.ocean.rawValue
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(WatchWorkoutListPayload.self, from: data)
        #expect(decoded == payload)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "gamingThemeEnabled")
        legacy.removeValue(forKey: "gamingPalette")
        let oldData = try JSONSerialization.data(withJSONObject: legacy)
        let old = try JSONDecoder().decode(WatchWorkoutListPayload.self, from: oldData)
        #expect(old.gamingThemeEnabled == nil)
        #expect(old.gamingPalette == nil)
        #expect(old.workouts == payload.workouts)
        #expect(old.coaching == payload.coaching)
        #expect(old.schemaVersion == payload.schemaVersion)
    }

    @Test func legacyLiveActivityRetainsTimerState() throws {
        let state = WorkoutActivityAttributes.ContentState(
            stepTitle: "Recovery", stepPosition: "2 of 5", repetition: "1 of 3",
            isPaused: true, isCountdown: true, timerStartedAt: nil,
            timerEndsAt: nil, frozenSeconds: 37
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(WorkoutActivityAttributes.ContentState.self, from: data)
        #expect(decoded == state)
        #expect(decoded.gamingThemeEnabled == nil)
        #expect(decoded.gamingPalette == nil)
        var themed = decoded
        themed.gamingThemeEnabled = true
        themed.gamingPalette = GamingPalette.ember.rawValue
        let roundTrip = try JSONDecoder().decode(
            WorkoutActivityAttributes.ContentState.self, from: JSONEncoder().encode(themed)
        )
        #expect(roundTrip.gamingPalette == GamingPalette.ember.rawValue)
        #expect(roundTrip.isPaused && roundTrip.isCountdown)
        #expect(roundTrip.frozenSeconds == 37)
        #expect(roundTrip.stepTitle == state.stepTitle)
        #expect(roundTrip.repetition == state.repetition)
    }

    @Test(arguments: GamingPalette.allCases) func gamingTextContrastRemainsLegible(palette: GamingPalette) {
        let pairs: [(GamingPalette.Role, GamingPalette.Role)] = [
            (.text, .canvas), (.text, .surface), (.text, .hero),
            (.secondaryText, .surface), (.secondaryText, .hero), (.secondaryText, .raisedSurface), (.onAccent, .accent)
        ]
        for (foreground, background) in pairs {
            let first = luminance(palette.hex(foreground))
            let second = luminance(palette.hex(background))
            let contrast = (max(first, second) + 0.05) / (min(first, second) + 0.05)
            #expect(contrast >= 4.5, "Palette text contrast must stay at least 4.5:1")
        }
    }

    private func luminance(_ hex: UInt32) -> Double {
        let channels = [Double((hex >> 16) & 255), Double((hex >> 8) & 255), Double(hex & 255)]
            .map { $0 / 255 }
            .map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
    }
}
