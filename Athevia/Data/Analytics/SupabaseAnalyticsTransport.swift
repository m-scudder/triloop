import Foundation
import Supabase

/// Sends Athevia's allow-listed semantic product events to the private
/// Supabase analytics ingestion function.
///
/// The authenticated Supabase session is authoritative. The Edge Function
/// derives user_id from the verified JWT and ignores any client-supplied
/// identity, so a modified client cannot write analytics for another account.
@MainActor
final class SupabaseAnalyticsTransport: AnalyticsTransport {
    private let session: URLSession
    private let client: SupabaseClient

    init(client: SupabaseClient = SupabaseConfiguration.client) {
        self.client = client
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        session = URLSession(configuration: configuration)
    }

    func send(
        _ records: [AnalyticsRecord],
        configuration: AnalyticsConfiguration
    ) async -> AnalyticsDelivery {
        guard !records.isEmpty else { return .accepted }

        do {
            let auth = try await client.auth.session
            var request = URLRequest(
                url: SupabaseConfiguration.url
                    .appendingPathComponent("functions/v1/analytics-ingest")
            )
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(
                "Bearer \(auth.accessToken)",
                forHTTPHeaderField: "Authorization"
            )
            request.setValue(
                SupabaseConfiguration.publishableKey,
                forHTTPHeaderField: "apikey"
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(
                AnalyticsIngestRequest(
                    batch: records.map {
                        AnalyticsIngestRecord(
                            id: $0.id,
                            sessionID: $0.sessionID,
                            occurredAt: $0.timestamp,
                            name: $0.name,
                            properties: $0.properties,
                            appVersion: $0.appVersion,
                            appBuild: $0.appBuild,
                            environment: configuration.environment.rawValue
                        )
                    }
                )
            )

            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                return .retry(after: nil)
            }

            ProductAnalytics.debugLog(
                "Supabase analytics HTTP \(response.statusCode)"
            )

            switch response.statusCode {
            case 200..<300:
                return .accepted
            case 401:
                // The auth session may have expired between queueing and send.
                return .retry(after: 5)
            case 408, 429, 500...599:
                let delay = response
                    .value(forHTTPHeaderField: "Retry-After")
                    .flatMap(Double.init)
                return .retry(
                    after: delay.map { min(max($0, 0), 24 * 60 * 60) }
                )
            default:
                // Validation failures are intentionally non-retryable.
                return .rejected
            }
        } catch {
            let failure = error as NSError
            ProductAnalytics.debugLog(
                "Supabase analytics transport error code=\(failure.code)"
            )
            return .retry(after: nil)
        }
    }
}

private struct AnalyticsIngestRequest: Encodable {
    let batch: [AnalyticsIngestRecord]
}

private struct AnalyticsIngestRecord: Encodable {
    let id: UUID
    let sessionID: UUID
    let occurredAt: Date
    let name: String
    let properties: [String: String]
    let appVersion: String
    let appBuild: String
    let environment: String

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID = "session_id"
        case occurredAt = "occurred_at"
        case name
        case properties
        case appVersion = "app_version"
        case appBuild = "app_build"
        case environment
    }
}
