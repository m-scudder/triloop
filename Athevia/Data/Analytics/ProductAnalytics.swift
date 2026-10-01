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

    var payload: [String: Any] {
        var values: [String: Any] = properties
        values["$session_id"] = sessionID.uuidString
        values["$process_person_profile"] = false
        values["$geoip_disable"] = true
        values["$app_version"] = appVersion
        values["$app_build"] = appBuild
        values["schema_version"] = 1
        return ["uuid": id.uuidString, "distinct_id": distinctID.uuidString,
                "event": name, "timestamp": ISO8601DateFormatter().string(from: timestamp),
                "properties": values]
    }
}

/// Main-actor isolation serializes consent, queue mutation and network completion.
/// No HealthKit, account or training models are accessible from this service.
@MainActor @Observable
final class ProductAnalytics {
    static let shared = ProductAnalytics(configuration: .current, suppressed: isTestProcess)
    static let consentKey = "analytics.usageConsent.v1"
    private static let identityKey = "analytics.installationID.v1"
    static let queueLimit = 200
    static let retention: TimeInterval = 7 * 24 * 60 * 60

    private(set) var consent: AnalyticsConsent
    private(set) var deliveryStatus = "No delivery attempted yet"
    var isConfigured: Bool { configuration != nil && !suppressed }
    var shouldOfferConsent: Bool { isConfigured && consent == .undecided }
    var isEnabled: Bool { isConfigured && consent == .allowed }

    var diagnosticSummary: String {
        if suppressed { return "Disabled: automated test, preview or launch argument" }
        guard let configuration else { return "Disabled: missing or invalid bundled configuration" }
        return "Environment: \(configuration.environment.rawValue) · Consent: \(consent.rawValue) · Active: \(isActive)"
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
         suppressed: Bool = false, now: @escaping () -> Date = { Date() },
         appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
         appBuild: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown") {
        self.configuration = configuration
        self.defaults = defaults
        self.transport = transport ?? PostHogTransport()
        self.suppressed = suppressed
        self.now = now
        self.appVersion = appVersion
        self.appBuild = appBuild
        consent = AnalyticsConsent(rawValue: defaults.string(forKey: Self.consentKey) ?? "") ?? .undecided
        self.queueURL = queueURL ?? Self.defaultQueueURL(configuration)
        if consent == .allowed, configuration != nil, !suppressed {
            identity = defaults.string(forKey: Self.identityKey).flatMap(UUID.init(uuidString:))
            if let url = self.queueURL, let data = try? Data(contentsOf: url),
               let records = try? JSONDecoder().decode([AnalyticsRecord].self, from: data) {
                queue = records.filter {
                    $0.distinctID == identity && now().timeIntervalSince($0.timestamp) < Self.retention
                        && $0.timestamp <= now()
                        && AnalyticsEvent.isAllowed(name: $0.name, properties: $0.properties)
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
        } else if isActive {
            track(.appOpened)
            startTicker()
            flush()
        }
    }

    /// Called on sign-out/account replacement/local erase. No account identifier
    /// is ever sent. The next user makes a fresh analytics choice.
    func resetForAccountChange() {
        consent = .undecided
        defaults.removeObject(forKey: Self.consentKey)
        discardPendingAndIdentity()
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
        if identity == nil {
            identity = UUID()
            defaults.set(identity?.uuidString, forKey: Self.identityKey)
        }
        if sessionID == nil || lastActivity.map({ date.timeIntervalSince($0) >= 30 * 60 }) == true {
            sessionID = UUID()
        }
        lastActivity = date
        guard let identity, let sessionID else { return }
        queue.removeAll { date.timeIntervalSince($0.timestamp) >= Self.retention }
        queue.append(AnalyticsRecord(id: UUID(), distinctID: identity, sessionID: sessionID,
                                     timestamp: date, name: event.name, properties: event.properties,
                                     appVersion: appVersion, appBuild: appBuild))
        queue = Array(queue.suffix(Self.queueLimit))
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
        queue.removeAll { now().timeIntervalSince($0.timestamp) >= Self.retention }
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
                case .accepted: self.deliveryStatus = "PostHog accepted the request. Check Activity → Live events."
                default: self.deliveryStatus = "PostHog rejected the request. Check the HTTP status in Xcode."
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
        sessionID = nil
        lastActivity = nil
        retryCount = 0
        nextAttempt = .distantPast
        defaults.removeObject(forKey: Self.identityKey)
        deliveryStatus = "Unsent events cleared"
        Self.debugLog("Cleared queue and analytics identity; cancelled pending sends")
        if let queueURL { try? FileManager.default.removeItem(at: queueURL) }
        // Cancellation cannot retract a request already received by PostHog.
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
