import CryptoKit
import Foundation
import Observation

enum AnalyticsConsent: String {
    case undecided, allowed, declined
}

struct AnalyticsRecord: Codable, Equatable {
    let id: UUID
    let distinctID: UUID
    let sessionID: UUID
    let timestamp: Date
    let name: String
    let properties: [String: String]
    let appVersion: String
    let appBuild: String

    var accountID: String? = nil
    var email: String? = nil
    var userName: String? = nil

    var payload: [String: Any] {
        var values: [String: Any] = properties
        values["$session_id"] = sessionID.uuidString
        values["$process_person_profile"] = accountID != nil
        values["$is_identified"] = accountID != nil
        values["$geoip_disable"] = true
        values["$app_version"] = appVersion
        values["$app_build"] = appBuild
        values["schema_version"] = 2
        var personProperties: [String: String] = [:]
        if let email {
            values["user_email"] = email
            personProperties["email"] = email
        }
        if let userName {
            values["user_name"] = userName
            personProperties["name"] = userName
        }
        if accountID != nil, !personProperties.isEmpty {
            values["$set"] = personProperties
        }
        return ["uuid": id.uuidString, "distinct_id": accountID ?? distinctID.uuidString,
                "event": name, "timestamp": ISO8601DateFormatter().string(from: timestamp),
                "properties": values]
    }
}

/// Main-actor isolation serializes consent, queue mutation and network completion.
/// Account identity is limited to the authenticated account id and email; no health
/// measurements or free-form training content enters analytics.
@MainActor @Observable
final class ProductAnalytics {
    static let shared = ProductAnalytics(configuration: .current, suppressed: isTestProcess, requiresAccountResolution: true)
    static let consentKey = "analytics.usageConsent.v2"
    private static let identityKey = "analytics.installationID.v2"
    private static let accountKey = "analytics.linkedAccount.v2"
    static let queueLimit = 200
    static let retention: TimeInterval = 7 * 24 * 60 * 60

    private(set) var consent: AnalyticsConsent
    private(set) var deliveryStatus = "No delivery attempted yet"
    var isConfigured: Bool { configuration != nil && !suppressed }
    var shouldOfferConsent: Bool { false }
    var isEnabled: Bool { isConfigured && consent == .allowed && accountResolved }

    var diagnosticSummary: String {
        if suppressed { return "Disabled: automated test, preview or launch argument" }
        guard let configuration else { return "Disabled: missing or invalid bundled configuration" }
        return "Environment: \(configuration.environment.rawValue) · Consent: \(consent.rawValue) · Active: \(isActive) · Account resolved: \(accountResolved)"
    }

    static func debugLog(_ message: String) {
        #if DEBUG
        print("[Athevia Analytics] \(message)")
        #endif
    }

    @ObservationIgnored private let configuration: AnalyticsConfiguration?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let queueURL: URL?
    @ObservationIgnored private let transport: any AnalyticsTransport
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let suppressed: Bool
    @ObservationIgnored private let appVersion: String
    @ObservationIgnored private let appBuild: String
    @ObservationIgnored private var queue: [AnalyticsRecord] = []
    @ObservationIgnored private var identity: UUID?
    private(set) var accountResolved: Bool
    @ObservationIgnored private var activeAccountID: String?
    @ObservationIgnored private var activeEmail: String?
    @ObservationIgnored private var activeUserName: String?
    @ObservationIgnored private var linkedAccountID: String?
    @ObservationIgnored private var identifiedThisRun = false
    @ObservationIgnored private var sessionID: UUID?
    @ObservationIgnored private var lastActivity: Date?
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var nextAttempt = Date.distantPast
    @ObservationIgnored private var retryCount = 0

    init(configuration: AnalyticsConfiguration?, defaults: UserDefaults = .standard,
         queueURL: URL? = nil, transport: (any AnalyticsTransport)? = nil,
         suppressed: Bool = false, requiresAccountResolution: Bool = false, now: @escaping () -> Date = { Date() },
         appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
         appBuild: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown") {
        self.configuration = configuration
        self.defaults = defaults
        self.transport = transport ?? SupabaseAnalyticsTransport()
        self.suppressed = suppressed
        self.accountResolved = !requiresAccountResolution
        self.now = now
        self.appVersion = appVersion
        self.appBuild = appBuild
        // Product analytics is owner-controlled and has no user-facing consent switch.
        // Keep the legacy state field only for backwards-compatible tests/internal diagnostics.
        consent = .allowed
        defaults.set(AnalyticsConsent.allowed.rawValue, forKey: Self.consentKey)
        self.queueURL = queueURL ?? Self.defaultQueueURL(configuration)
        if consent == .allowed, configuration != nil, !suppressed {
            linkedAccountID = defaults.string(forKey: Self.accountKey)
            if linkedAccountID != nil { accountResolved = false }
            identity = defaults.string(forKey: Self.identityKey).flatMap(UUID.init(uuidString:))
            if let url = self.queueURL, let data = try? Data(contentsOf: url),
               let records = try? JSONDecoder().decode([AnalyticsRecord].self, from: data) {
                queue = records.filter {
                    $0.distinctID == identity && now().timeIntervalSince($0.timestamp) < Self.retention
                        && $0.timestamp <= now()
                        && ($0.accountID == nil || $0.accountID == linkedAccountID)
                        && isAllowedRecord($0)
                }
                queue = Array(queue.suffix(Self.queueLimit))
            }
        } else {
            if let url = self.queueURL { try? FileManager.default.removeItem(at: url) }
        }
        Self.debugLog("Initialized. \(diagnosticSummary)")
    }

    func setConsent(_ consent: AnalyticsConsent) {
        guard self.consent != consent else { return }
        self.consent = consent
        defaults.set(consent.rawValue, forKey: Self.consentKey)
        Self.debugLog("Consent changed: \(consent.rawValue)")
        if consent != .allowed {
            discardPendingAndIdentity()
        } else {
            identifyIfNeeded()
            if isActive {
                track(.appOpened)
                startTicker()
                flush()
            }
        }
    }

    /// Sign-out/account replacement/local erase rotates the analytics identity.
    func resetForAccountChange() {
        activeAccountID = nil
        activeEmail = nil
        activeUserName = nil
        consent = .allowed
        defaults.set(AnalyticsConsent.allowed.rawValue, forKey: Self.consentKey)
        discardPendingAndIdentity()
    }

    /// Call only after authentication resolves.
    ///
    /// The account id remains the stable PostHog distinct id. Email is attached
    /// as explicit user metadata so product events can be filtered back to the
    /// signed-in person without using email as the primary identity key.
    func updateAccount(
        _ userID: String?,
        email: String? = nil,
        name: String? = nil
    ) {
        let account = userID.flatMap {
            Self.accountIdentifier(
                $0,
                environment: configuration?.environment
            )
        }
        let normalizedEmail = Self.normalizedEmail(email)
        let normalizedName = Self.normalizedName(name)
        let wasResolved = accountResolved

        if let previous = linkedAccountID ?? activeAccountID,
           previous != account {
            resetForAccountChange()
        }

        let identityMetadataChanged =
            activeEmail != normalizedEmail
                || activeUserName != normalizedName
        activeAccountID = account
        activeEmail = account == nil ? nil : normalizedEmail
        activeUserName = account == nil ? nil : normalizedName
        accountResolved = true

        if identityMetadataChanged, account != nil {
            identifiedThisRun = false
        }

        identifyIfNeeded()
        Self.debugLog(
            "Account resolved: \(account == nil ? "guest" : "signed in")"
        )
        if isActive {
            if !wasResolved { track(.appOpened) }
            startTicker()
            flush()
        }
    }

    func waitForAccountResolution() {
        accountResolved = false
        Self.debugLog("Waiting for account resolution; capture and flush paused")
    }

    func accountResolutionFailed() {
        // A guest's failed login should not disable guest analytics. A cached
        // signed-in identity, however, needs a resolved session or explicit exit.
        if activeAccountID == nil && linkedAccountID == nil {
            updateAccount(nil)
        } else {
            waitForAccountResolution()
        }
    }

    // Environment namespaces keep debug and production people separate in a shared project.
    static func accountIdentifier(_ userID: String, environment: AnalyticsEnvironment?) -> String? {
        guard !userID.isEmpty, let environment else { return nil }
        let normalized = UUID(uuidString: userID)?.uuidString.lowercased() ?? userID
        let input = "athevia.analytics.v1:\(environment.rawValue):\(normalized)"
        let hash = SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
        return "account_" + hash
    }

    static func normalizedEmail(_ email: String?) -> String? {
        guard let email else { return nil }
        let value = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !value.isEmpty,
              value.contains("@") else {
            return nil
        }
        return value
    }

    static func normalizedName(_ name: String?) -> String? {
        guard let name else { return nil }
        let value = name.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return value.isEmpty ? nil : value
    }

    private func ensureIdentity() {
        if identity == nil {
            identity = UUID()
            defaults.set(identity?.uuidString, forKey: Self.identityKey)
        }
    }

    private func identifyIfNeeded() {
        guard isEnabled, let account = activeAccountID, !identifiedThisRun else { return }
        ensureIdentity()
        guard let identity else { return }
        linkedAccountID = account
        defaults.set(account, forKey: Self.accountKey)
        // Retry an existing merge with its original UUID. If auth refreshes
        // the email while that identify event is still queued, update the
        // metadata in place rather than sending a stale address.
        if let index = queue.firstIndex(
            where: {
                $0.name == "$identify"
                    && $0.accountID == account
            }
        ) {
            queue[index].email = activeEmail
            queue[index].userName = activeUserName
        } else {
            let linkSessionID = sessionID ?? UUID()
            sessionID = linkSessionID
            queue.append(
                AnalyticsRecord(
                    id: UUID(),
                    distinctID: identity,
                    sessionID: linkSessionID,
                    timestamp: now(),
                    name: "$identify",
                    properties: [
                        "$anon_distinct_id": identity.uuidString
                    ],
                    appVersion: appVersion,
                    appBuild: appBuild,
                    accountID: account,
                    email: activeEmail,
                    userName: activeUserName
                )
            )
        }
        identifiedThisRun = true
        trimQueue()
        persist()
        Self.debugLog("Queued account identity link (identifiers omitted)")
    }

    private func isAllowedRecord(_ record: AnalyticsRecord) -> Bool {
        if let email = record.email,
           Self.normalizedEmail(email) != email {
            return false
        }
        if let userName = record.userName,
           Self.normalizedName(userName) != userName {
            return false
        }

        if record.name == "$identify" {
            return record.accountID != nil && record.accountID == linkedAccountID
                && record.properties == ["$anon_distinct_id": record.distinctID.uuidString]
        }
        return AnalyticsEvent.isAllowed(name: record.name, properties: record.properties)
    }

    private func trimQueue() {
        // Preserve pending identity links while dropping oldest usage events on overflow.
        let links = queue.filter { $0.name == "$identify" }
        let events = queue.filter { $0.name != "$identify" }
        queue = Array(links.prefix(1)) + Array(events.suffix(Self.queueLimit - min(links.count, 1)))
    }

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        Self.debugLog("Lifecycle active=\(active). \(diagnosticSummary)")
        if active {
            track(.appOpened)
            startTicker()
            flush()
        } else {
            ticker?.cancel()
            ticker = nil
            flush() // Best effort only; no background mode is requested.
        }
    }

    func track(_ event: AnalyticsEvent) {
        guard isEnabled else {
            Self.debugLog("Skipped \(event.name). \(diagnosticSummary)")
            return
        }
        let date = now()
        identifyIfNeeded()
        ensureIdentity()
        if sessionID == nil || lastActivity.map({ date.timeIntervalSince($0) >= 30 * 60 }) == true {
            sessionID = UUID()
        }
        lastActivity = date
        guard let identity, let sessionID else { return }
        queue.removeAll { $0.name != "$identify" && date.timeIntervalSince($0.timestamp) >= Self.retention }
        queue.append(
            AnalyticsRecord(
                id: UUID(),
                distinctID: identity,
                sessionID: sessionID,
                timestamp: date,
                name: event.name,
                properties: event.properties,
                appVersion: appVersion,
                appBuild: appBuild,
                accountID: activeAccountID,
                email: activeEmail,
                userName: activeUserName
            )
        )
        trimQueue()
        persist()
        Self.debugLog("Queued \(event.name); pending=\(queue.count)")
        if queue.count >= 20 { flush() }
    }

    @discardableResult
    func flush() -> Task<Void, Never>? {
        guard isEnabled, let configuration else {
            deliveryStatus = diagnosticSummary
            Self.debugLog("Flush blocked. \(diagnosticSummary)")
            return nil
        }
        guard now() >= nextAttempt else {
            deliveryStatus = "Waiting for retry backoff"
            Self.debugLog(deliveryStatus)
            return nil
        }
        if let request {
            Self.debugLog("Flush already in progress")
            return request
        }
        queue.removeAll { $0.name != "$identify" && now().timeIntervalSince($0.timestamp) >= Self.retention }
        persist()
        guard !queue.isEmpty else {
            Self.debugLog("Flush: queue empty")
            return nil
        }
        let batch = Array(queue.prefix(50))
        deliveryStatus = "Sending \(batch.count) event(s)…"
        Self.debugLog("Sending \(batch.count) event(s) to \(configuration.host.host ?? "PostHog"); environment=\(configuration.environment.rawValue)")
        let requestGeneration = generation
        request = Task { [weak self, transport] in
            let outcome = await transport.send(batch, configuration: configuration)
            guard let self, !Task.isCancelled, self.generation == requestGeneration else {
                Self.debugLog("Ignored delivery completion: cancelled or consent changed")
                return
            }
            self.request = nil
            switch outcome {
            case .accepted, .rejected:
                switch outcome {
                case .accepted: self.deliveryStatus = "Supabase accepted the analytics batch."
                default: self.deliveryStatus = "Supabase rejected the analytics batch. Check the HTTP status in Xcode."
                }
                Self.debugLog(self.deliveryStatus)
                // Non-retryable 4xx is dropped; retries preserve event UUIDs.
                let ids = Set(batch.map(\.id))
                self.queue.removeAll { ids.contains($0.id) }
                self.retryCount = 0
                self.nextAttempt = .distantPast
                self.persist()
                if self.isActive { self.flush() }
            case .retry(let retryAfter):
                self.retryCount = min(self.retryCount + 1, 6)
                let delay = max(retryAfter ?? 0, min(30 * pow(2, Double(self.retryCount - 1)), 1800))
                self.nextAttempt = self.now().addingTimeInterval(delay)
                self.deliveryStatus = "Delivery failed; retry in \(Int(delay)) seconds"
                Self.debugLog(self.deliveryStatus)
            }
        }
        return request
    }

    private func startTicker() {
        guard isEnabled, ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                self?.flush()
            }
        }
    }

    private func discardPendingAndIdentity() {
        generation = UUID()
        request?.cancel()
        request = nil
        ticker?.cancel()
        ticker = nil
        queue.removeAll()
        identity = nil
        linkedAccountID = nil
        activeEmail = nil
        activeUserName = nil
        identifiedThisRun = false
        defaults.removeObject(forKey: Self.accountKey)
        sessionID = nil
        lastActivity = nil
        retryCount = 0
        nextAttempt = .distantPast
        defaults.removeObject(forKey: Self.identityKey)
        deliveryStatus = "Unsent events cleared"
        Self.debugLog("Cleared queue and analytics identity; cancelled pending sends")
        if let queueURL { try? FileManager.default.removeItem(at: queueURL) }
        // Cancellation cannot retract a request already received by the analytics backend.
    }

    private func persist() {
        guard let queueURL else { return }
        if queue.isEmpty {
            try? FileManager.default.removeItem(at: queueURL)
            return
        }
        do {
            try FileManager.default.createDirectory(at: queueURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(queue).write(to: queueURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var url = queueURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
        } catch {
            // Analytics persistence must never interrupt training or show an alert.
            Self.debugLog("Queue persistence failed; error code=\((error as NSError).code)")
        }
    }

    private static func defaultQueueURL(_ configuration: AnalyticsConfiguration?) -> URL? {
        guard let configuration else { return nil }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AtheviaAnalytics", isDirectory: true)
            .appendingPathComponent("\(configuration.environment.rawValue)-\(configuration.projectToken).json")
    }

    private static var isTestProcess: Bool {
        let process = ProcessInfo.processInfo
        return process.environment["XCTestConfigurationFilePath"] != nil
            || process.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || NSClassFromString("XCTestCase") != nil
            || process.arguments.contains { $0.contains("ui-tests") || $0 == "--disable-analytics" }
    }
}
