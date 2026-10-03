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

    @Test func analyticsStartsAutomaticallyWhenConfigured() async {
        let configured = Fixture()
        defer { configured.cleanUp() }
        configured.analytics.track(.screenViewed(.home))
        await configured.analytics.flush()?.value
        #expect(configured.transport.deliveries.first?.first?.name == "$screen")

        let unconfigured = Fixture(configured: false)
        defer { unconfigured.cleanUp() }
        unconfigured.analytics.track(.whyTapped)
        await unconfigured.analytics.flush()?.value
        #expect(unconfigured.transport.deliveries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: unconfigured.queueURL.path))
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

    @Test func accountResetRotatesIdentityWithoutDisablingAnalytics() async {
        let f = Fixture()
        defer { f.cleanUp() }
        f.analytics.setConsent(.allowed)
        f.analytics.track(.appOpened)
        f.analytics.resetForAccountChange()
        #expect(f.analytics.consent == .allowed)
        #expect(!f.analytics.shouldOfferConsent)
        #expect(f.analytics.isEnabled)
        f.analytics.track(.infoTapped)
        await f.analytics.flush()?.value
        #expect(f.transport.deliveries.last?.first?.name == "info_tapped")
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
        #expect(Set(properties.keys) == ["$screen_name", "$session_id", "$process_person_profile", "$is_identified",
                                         "$geoip_disable", "$app_version", "$app_build", "schema_version", "environment"])
        #expect(properties["$geoip_disable"] as? Bool == true)
        #expect(properties["$process_person_profile"] as? Bool == false)
        #expect(body["api_key"] as? String == config.projectToken)
        #expect(batch.first?["distinct_id"] as? String == event.distinctID.uuidString)
    }

    @Test func guestHistoryLinksToAccountWithoutSendingRawAccountID() async throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.analytics.setConsent(.allowed)
        f.analytics.track(.whyTapped)
        f.analytics.updateAccount("account-a")
        f.analytics.updateAccount("account-a")
        f.analytics.track(.infoTapped)
        await f.analytics.flush()?.value
        let records = try #require(f.transport.deliveries.first)
        let guest = try #require(records.first { $0.name == "why_tapped" })
        let link = try #require(records.first { $0.name == "$identify" })
        let signedIn = try #require(records.first { $0.name == "info_tapped" })
        #expect(records.filter { $0.name == "$identify" }.count == 1)
        #expect(guest.accountID == nil)
        #expect(link.properties == ["$anon_distinct_id": guest.distinctID.uuidString])
        #expect(link.accountID == signedIn.accountID)
        #expect(link.accountID != "account-a")
        #expect(link.payload["distinct_id"] as? String == signedIn.accountID)
        let properties = try #require(link.payload["properties"] as? [String: Any])
        #expect(properties["$process_person_profile"] as? Bool == true)
        #expect(properties["$is_identified"] as? Bool == true)
    }

    @Test func signedInEventsIncludeNormalizedEmailAndPersonProperty() async throws {
        let f = Fixture()
        defer { f.cleanUp() }

        f.analytics.updateAccount(
            "account-a",
            email: "  Athlete@Example.COM "
        )
        f.analytics.track(.screenViewed(.plan))
        await f.analytics.flush()?.value

        let records = try #require(
            f.transport.deliveries.first
        )
        let identify = try #require(
            records.first { $0.name == "$identify" }
        )
        let screen = try #require(
            records.first { $0.name == "$screen" }
        )

        #expect(identify.email == "athlete@example.com")
        #expect(screen.email == "athlete@example.com")

        let identifyProperties = try #require(
            identify.payload["properties"] as? [String: Any]
        )
        let screenProperties = try #require(
            screen.payload["properties"] as? [String: Any]
        )
        let person = try #require(
            identifyProperties["$set"] as? [String: String]
        )

        #expect(
            identifyProperties["user_email"] as? String
                == "athlete@example.com"
        )
        #expect(
            screenProperties["user_email"] as? String
                == "athlete@example.com"
        )
        #expect(person["email"] == "athlete@example.com")
    }

    @Test func guestEventsDoNotContainEmail() async throws {
        let f = Fixture()
        defer { f.cleanUp() }

        f.analytics.track(.screenViewed(.home))
        await f.analytics.flush()?.value

        let record = try #require(
            f.transport.deliveries.first?.first
        )
        let properties = try #require(
            record.payload["properties"] as? [String: Any]
        )

        #expect(record.email == nil)
        #expect(properties["user_email"] == nil)
        #expect(properties["$set"] == nil)
    }

    @Test func signingOutStopsEmailFromLeakingIntoLaterEvents() async throws {
        let f = Fixture()
        defer { f.cleanUp() }

        f.analytics.updateAccount(
            "account-a",
            email: "athlete@example.com"
        )
        await f.analytics.flush()?.value

        f.analytics.updateAccount(nil)
        f.analytics.track(.infoTapped)
        await f.analytics.flush()?.value

        let event = try #require(
            f.transport.deliveries.last?.first {
                $0.name == "info_tapped"
            }
        )
        #expect(event.email == nil)
        let properties = try #require(
            event.payload["properties"] as? [String: Any]
        )
        #expect(properties["user_email"] == nil)
    }

    @Test func loginAutomaticallyIdentifiesConfiguredAnalytics() async {
        let f = Fixture()
        defer { f.cleanUp() }
        f.analytics.updateAccount("account-a")
        await f.analytics.flush()?.value
        #expect(f.transport.deliveries.first?.first?.name == "$identify")
    }

    @Test func accountReplacementNeverMergesTwoAccounts() async throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.analytics.setConsent(.allowed)
        f.analytics.updateAccount("account-a")
        await f.analytics.flush()?.value
        let first = try #require(f.transport.deliveries.first?.first)
        f.analytics.updateAccount("account-b")
        #expect(f.analytics.consent == .allowed)
        await f.analytics.flush()?.value
        let second = try #require(f.transport.deliveries.last?.first)
        #expect(first.distinctID != second.distinctID)
        #expect(first.accountID != second.accountID)
        #expect(second.properties["$anon_distinct_id"] == second.distinctID.uuidString)
        f.analytics.updateAccount(nil)
        #expect(f.analytics.consent == .allowed)
    }

    @Test func restartWaitsForAuthAndPreservesPendingMergeUUID() async throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.analytics.setConsent(.allowed)
        f.analytics.track(.whyTapped)
        f.analytics.updateAccount("account-a")
        let queued = try JSONDecoder().decode([AnalyticsRecord].self, from: Data(contentsOf: f.queueURL))
        let restored = ProductAnalytics(configuration: Fixture.configuration, defaults: f.defaults,
            queueURL: f.queueURL, transport: f.transport, now: { f.clock.date })
        await restored.flush()?.value
        #expect(f.transport.deliveries.isEmpty)
        restored.updateAccount("account-a")
        await restored.flush()?.value
        #expect(f.transport.deliveries.first == queued)
    }

    @Test func expiredSessionDoesNotSendPreviousAccountsQueue() async {
        let f = Fixture()
        defer { f.cleanUp() }
        f.analytics.setConsent(.allowed)
        f.analytics.updateAccount("account-a")
        let restored = ProductAnalytics(configuration: Fixture.configuration, defaults: f.defaults,
            queueURL: f.queueURL, transport: f.transport, now: { f.clock.date })
        restored.updateAccount(nil)
        await restored.flush()?.value
        #expect(restored.consent == .allowed)
        #expect(f.transport.deliveries.isEmpty)
    }

    @Test func pendingMergeSurvivesQueueOverflowAndOfflineRetry() async throws {
        let f = Fixture()
        defer { f.cleanUp() }
        f.analytics.setConsent(.allowed)
        f.analytics.updateAccount("account-a")
        f.transport.result = .retry(after: 60)
        for _ in 0..<250 { f.analytics.track(.whyTapped) }
        await f.analytics.flush()?.value
        let records = try JSONDecoder().decode([AnalyticsRecord].self, from: Data(contentsOf: f.queueURL))
        #expect(records.count == ProductAnalytics.queueLimit)
        #expect(records.first?.name == "$identify")
        let firstUUID = records.first?.id
        f.clock.date.addTimeInterval(61)
        await f.analytics.flush()?.value
        #expect(f.transport.deliveries.last?.first?.id == firstUUID)
    }

    @Test func freshInstallHasNewGuestIDButAccountIDIsStable() async throws {
        let first = Fixture()
        let second = Fixture()
        defer { first.cleanUp(); second.cleanUp() }
        for f in [first, second] {
            f.analytics.setConsent(.allowed)
            f.analytics.track(.whyTapped)
            f.analytics.updateAccount("account-a")
            await f.analytics.flush()?.value
        }
        let a = try #require(first.transport.deliveries.first?.first)
        let b = try #require(second.transport.deliveries.first?.first)
        #expect(a.distinctID != b.distinctID)
        #expect(a.accountID == b.accountID)
        #expect(ProductAnalytics.accountIdentifier("account-a", environment: .development)
            != ProductAnalytics.accountIdentifier("account-a", environment: .production))
    }

    @Test func failedLoginResumesGuestButDoesNotAssumeCachedAccountSignedOut() async {
        let f = Fixture()
        defer { f.cleanUp() }
        f.analytics.setConsent(.allowed)
        f.analytics.waitForAccountResolution()
        f.analytics.track(.whyTapped)
        await f.analytics.flush()?.value
        #expect(f.transport.deliveries.isEmpty)
        f.analytics.accountResolutionFailed()
        #expect(f.analytics.isEnabled)
        f.analytics.updateAccount("account-a")
        f.analytics.waitForAccountResolution()
        f.analytics.accountResolutionFailed()
        #expect(!f.analytics.isEnabled)
        #expect(f.analytics.consent == .allowed)
        f.analytics.updateAccount("account-a")
        #expect(f.analytics.isEnabled)
    }

    @Test func legacyConsentStateDoesNotDisableOwnerControlledAnalytics() {
        let f = Fixture()
        defer { f.cleanUp() }
        for previous in [AnalyticsConsent.allowed, .declined] {
            f.defaults.removeObject(forKey: ProductAnalytics.consentKey)
            f.defaults.set(previous.rawValue, forKey: "analytics.usageConsent.v1")
            let migrated = ProductAnalytics(configuration: Fixture.configuration, defaults: f.defaults,
                queueURL: f.queueURL, transport: f.transport)
            #expect(migrated.consent == .allowed)
            #expect(migrated.isEnabled)
        }
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

    @Test func explicitDebugSharingPreservesLabelAndDoesNotEnableReleaseOrTestFlight() throws {
        let info: [String: Any] = [
            "PostHogProductionToken": "phc_ProductionTestToken123",
            "PostHogProductionHost": "https://us.i.posthog.com",
            "PostHogDebugUsesProductionProject": true
        ]
        let config = try #require(AnalyticsConfiguration.resolve(info: info, environment: .development, isDebug: true))
        #expect(config.projectToken == (info["PostHogProductionToken"] as? String))
        #expect(config.environment == .development)
        #expect(AnalyticsConfiguration.resolve(info: info, environment: .development, isDebug: false) == nil)
        #expect(AnalyticsConfiguration.resolve(info: info, environment: .testflight, isDebug: false) == nil)
        var disabled = info
        disabled["PostHogDebugUsesProductionProject"] = false
        #expect(AnalyticsConfiguration.resolve(info: disabled, environment: .development, isDebug: true) == nil)

        let event = AnalyticsRecord(id: UUID(), distinctID: UUID(), sessionID: UUID(), timestamp: .now,
                                    name: "why_tapped", properties: [:], appVersion: "1.0", appBuild: "test")
        let request = try PostHogTransport.request([event], configuration: config)
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let batch = try #require(body["batch"] as? [[String: Any]])
        let properties = try #require(batch.first?["properties"] as? [String: Any])
        #expect(properties["environment"] as? String == "development")
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
