import Foundation
import Testing
@testable import Athevia

@MainActor
struct ProductAnalyticsTests {
    private final class Clock {
        var date = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private final class Transport: AnalyticsTransport {
        var deliveries: [[AnalyticsRecord]] = []
        var result: AnalyticsDelivery = .accepted
        var hold = false
        var pending: CheckedContinuation<AnalyticsDelivery, Never>?
        var pendingWaiter: CheckedContinuation<Void, Never>?

        func send(_ records: [AnalyticsRecord], configuration: AnalyticsConfiguration) async -> AnalyticsDelivery {
            deliveries.append(records)
            if hold {
                return await withCheckedContinuation {
                    pending = $0
                    pendingWaiter?.resume()
                    pendingWaiter = nil
                }
            }
            return result
        }

        func waitUntilPending() async {
            guard pending == nil else { return }
            await withCheckedContinuation { pendingWaiter = $0 }
        }
    }

    @MainActor private struct Fixture {
        let defaults: UserDefaults
        let suite: String
        let directory: URL
        let queueURL: URL
        let transport: Transport
        let clock: Clock
        let analytics: ProductAnalytics

        init(configured: Bool = true, suppressed: Bool = false) {
            suite = "analytics-tests-\(UUID().uuidString)"
            defaults = UserDefaults(suiteName: suite)!
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
            queueURL = directory.appendingPathComponent("queue.json")
            transport = Transport()
            clock = Clock()
            let clock = self.clock
            analytics = ProductAnalytics(configuration: configured ? Self.configuration : nil,
                                         defaults: defaults, queueURL: queueURL, transport: transport,
                                         suppressed: suppressed, now: { clock.date },
                                         appVersion: "1.0", appBuild: "test")
        }

        static var configuration: AnalyticsConfiguration {
            AnalyticsConfiguration(projectToken: "phc_TestProjectToken123456", host: "https://eu.i.posthog.com",
                                   environment: .development)!
        }

        func cleanUp() {
            analytics.setConsent(.declined)
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test func noCollectionBeforeConsentOrWithoutConfiguration() async {
        for configured in [true, false] {
            let f = Fixture(configured: configured)
            defer { f.cleanUp() }
            f.analytics.track(.screenViewed(.home))
            await f.analytics.flush()?.value
            #expect(f.transport.deliveries.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: f.queueURL.path))
            if !configured {
                f.analytics.setConsent(.allowed)
                f.analytics.track(.whyTapped)
                await f.analytics.flush()?.value
                #expect(f.transport.deliveries.isEmpty)
            }
        }
    }

    @Test func testProcessesRemainSuppressedEvenWithConsent() async {
        let f = Fixture(suppressed: true)
        defer { f.cleanUp() }
        f.analytics.setConsent(.allowed)
        f.analytics.track(.appOpened)
        await f.analytics.flush()?.value
        #expect(f.transport.deliveries.isEmpty)
        #expect(!f.analytics.shouldOfferConsent)
    }

    @Test func optOutPurgesQueueAndRotatesIdentity() async throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.analytics.setConsent(.allowed)
        f.analytics.track(.whyTapped)
        let before = try JSONDecoder().decode([AnalyticsRecord].self, from: Data(contentsOf: f.queueURL))
        f.analytics.setConsent(.declined)
        #expect(!FileManager.default.fileExists(atPath: f.queueURL.path))
        f.analytics.track(.infoTapped)
        await f.analytics.flush()?.value
        #expect(f.transport.deliveries.isEmpty)
        f.analytics.setConsent(.allowed)
        f.analytics.track(.calendarOpened)
        await f.analytics.flush()?.value
        let delivered = try #require(f.transport.deliveries.first?.first)
        #expect(delivered.name == "calendar_opened")
        #expect(delivered.distinctID != before.first?.distinctID)
    }

    @Test func retryKeepsEventUUIDAndHonorsBackoff() async throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.analytics.setConsent(.allowed)
        f.analytics.track(.action(.importWorkouts, .requested))
        f.transport.result = .retry(after: 120)
        await f.analytics.flush()?.value
        #expect(f.transport.deliveries.count == 1)
        await f.analytics.flush()?.value
        #expect(f.transport.deliveries.count == 1)
        f.clock.date.addTimeInterval(121)
        f.transport.result = .accepted
        await f.analytics.flush()?.value
        #expect(f.transport.deliveries.count == 2)
        #expect(f.transport.deliveries[0] == f.transport.deliveries[1])
        #expect(!FileManager.default.fileExists(atPath: f.queueURL.path))
    }

    @Test func queueIsBoundedAndExpiredEventsAreDropped() async throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.analytics.setConsent(.allowed)
        f.transport.result = .retry(after: 60)
        for _ in 0..<250 { f.analytics.track(.whyTapped) }
        await f.analytics.flush()?.value
        let records = try JSONDecoder().decode([AnalyticsRecord].self, from: Data(contentsOf: f.queueURL))
        #expect(records.count == ProductAnalytics.queueLimit)
        f.clock.date.addTimeInterval(ProductAnalytics.retention + 1)
        f.transport.result = .accepted
        let previousCount = f.transport.deliveries.count
        await f.analytics.flush()?.value
        #expect(f.transport.deliveries.count == previousCount)
        #expect(!FileManager.default.fileExists(atPath: f.queueURL.path))
    }

    @Test func accountResetRequiresNewChoice() async {
        let f = Fixture()
        defer { f.cleanUp() }
        f.analytics.setConsent(.allowed)
        f.analytics.track(.appOpened)
        f.analytics.resetForAccountChange()
        #expect(f.analytics.consent == .undecided)
        #expect(f.analytics.shouldOfferConsent)
        await f.analytics.flush()?.value
        #expect(f.transport.deliveries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: f.queueURL.path))
    }

    @Test func sessionRotatesAfterInactivityButIdentityPersists() async throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.analytics.setConsent(.allowed)
        f.analytics.track(.screenViewed(.home))
        f.clock.date.addTimeInterval(10)
        f.analytics.track(.screenViewed(.plan))
        f.clock.date.addTimeInterval(1801)
        f.analytics.track(.screenViewed(.progress))
        await f.analytics.flush()?.value
        let records = try #require(f.transport.deliveries.first)
        #expect(records.count == 3)
        #expect(records[0].sessionID == records[1].sessionID)
        #expect(records[1].sessionID != records[2].sessionID)
        #expect(Set(records.map(\.distinctID)).count == 1)
    }

    @Test func queueRestoresOnlyAllowedEventsForCurrentIdentity() async throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.analytics.setConsent(.allowed)
        f.analytics.track(.whyTapped)
        let good = try #require(JSONDecoder().decode([AnalyticsRecord].self, from: Data(contentsOf: f.queueURL)).first)
        let bad = AnalyticsRecord(id: UUID(), distinctID: good.distinctID, sessionID: good.sessionID,
                                  timestamp: good.timestamp, name: "$screen", properties: ["email": "private@example.com"],
                                  appVersion: "1.0", appBuild: "test")
        try JSONEncoder().encode([good, bad]).write(to: f.queueURL)
        let restored = ProductAnalytics(configuration: Fixture.configuration, defaults: f.defaults,
                                        queueURL: f.queueURL, transport: f.transport, now: { f.clock.date })
        await restored.flush()?.value
        #expect(f.transport.deliveries.first == [good])
    }

    @Test func cancelledOldDeliveryCannotDeleteNewConsentQueue() async throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.analytics.setConsent(.allowed)
        f.transport.hold = true
        f.analytics.track(.whyTapped)
        let oldRequest = f.analytics.flush()
        await f.transport.waitUntilPending()
        let pending = try #require(f.transport.pending)
        f.analytics.setConsent(.declined)
        f.analytics.setConsent(.allowed)
        f.analytics.track(.infoTapped)
        pending.resume(returning: .accepted)
        await oldRequest?.value
        f.transport.hold = false
        await f.analytics.flush()?.value
        #expect(f.transport.deliveries.count == 2)
        #expect(f.transport.deliveries.last?.map(\.name) == ["info_tapped"])
    }

    @Test func payloadContainsOnlyApprovedProperties() throws {
        let config = Fixture.configuration
        let event = AnalyticsRecord(id: UUID(), distinctID: UUID(), sessionID: UUID(), timestamp: .now,
                                    name: "$screen", properties: ["$screen_name": "home"],
                                    appVersion: "1.0", appBuild: "test")
        let request = try PostHogTransport.request([event], configuration: config)
        #expect(request.url?.absoluteString == "https://eu.i.posthog.com/batch/")
        #expect(request.httpMethod == "POST")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let batch = try #require(body["batch"] as? [[String: Any]])
        let properties = try #require(batch.first?["properties"] as? [String: Any])
        #expect(Set(properties.keys) == ["$screen_name", "$session_id", "$process_person_profile",
                                         "$geoip_disable", "$app_version", "$app_build", "schema_version", "environment"])
        #expect(properties["$geoip_disable"] as? Bool == true)
        #expect(properties["$process_person_profile"] as? Bool == false)
        #expect(body["api_key"] as? String == config.projectToken)
        #expect(batch.first?["distinct_id"] as? String == event.distinctID.uuidString)
    }

    @Test func environmentConfigurationFailsClosed() {
        #expect(AnalyticsEnvironment.resolve(isDebug: true, receiptName: "receipt") == .development)
        #expect(AnalyticsEnvironment.resolve(isDebug: false, receiptName: "sandboxReceipt") == .testflight)
        #expect(AnalyticsEnvironment.resolve(isDebug: false, receiptName: nil) == .development)
        #expect(AnalyticsEnvironment.resolve(isDebug: false, receiptName: "receipt") == .production)
        let info = ["PostHogProductionToken": "phc_ProductionTestToken123", "PostHogProductionHost": "https://us.i.posthog.com"]
        #expect(AnalyticsConfiguration.resolve(info: info, environment: .production) != nil)
        #expect(AnalyticsConfiguration.resolve(info: info, environment: .testflight) == nil)
        #expect(AnalyticsConfiguration(projectToken: "phx_PersonalToken123456", host: "https://us.i.posthog.com", environment: .production) == nil)
        #expect(AnalyticsConfiguration(projectToken: "phc_TestProjectToken123456", host: "https://untrusted.example", environment: .production) == nil)
        var mixed = info
        mixed["PostHogDevelopmentToken"] = info["PostHogProductionToken"]
        mixed["PostHogDevelopmentHost"] = info["PostHogProductionHost"]
        #expect(AnalyticsConfiguration.resolve(info: mixed, environment: .development) == nil)
    }

    @Test func schemaRejectsUnstructuredTextAndUnknownEvents() {
        #expect(!AnalyticsEvent.isAllowed(name: "chat_message", properties: [:]))
        #expect(!AnalyticsEvent.isAllowed(name: "$screen", properties: ["$screen_name": "User entered name"]))
        #expect(!AnalyticsEvent.isAllowed(name: "import_workouts_failed", properties: ["error": "health details"]))
        for action in AnalyticsAction.allCases {
            for outcome in AnalyticsOutcome.allCases {
                let event = AnalyticsEvent.action(action, outcome)
                #expect(AnalyticsEvent.isAllowed(name: event.name, properties: event.properties))
            }
        }
    }
}
