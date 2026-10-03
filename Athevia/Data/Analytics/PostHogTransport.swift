import Foundation

enum AnalyticsDelivery {
    case accepted, rejected, retry(after: TimeInterval?)
}

@MainActor
protocol AnalyticsTransport {
    func send(_ records: [AnalyticsRecord], configuration: AnalyticsConfiguration) async -> AnalyticsDelivery
}

/// Uses PostHog's documented public batch endpoint. No SDK autocapture,
/// push integration, remote flags or session replay is installed. Signed-in
/// identity is supplied explicitly by ProductAnalytics.
@MainActor
final class PostHogTransport: AnalyticsTransport {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        session = URLSession(configuration: config)
    }

    static func request(_ records: [AnalyticsRecord], configuration: AnalyticsConfiguration) throws -> URLRequest {
        var request = URLRequest(url: configuration.host.appendingPathComponent("batch/"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let batch = records.map { record in
            var payload = record.payload
            var properties = (payload["properties"] as? [String: Any]) ?? [:]
            properties["environment"] = configuration.environment.rawValue
            payload["properties"] = properties
            return payload
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "api_key": configuration.projectToken, "batch": batch
        ])
        return request
    }

    func send(_ records: [AnalyticsRecord], configuration: AnalyticsConfiguration) async -> AnalyticsDelivery {
        do {
            let request = try Self.request(records, configuration: configuration)
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { return .retry(after: nil) }
            ProductAnalytics.debugLog("PostHog HTTP \(response.statusCode)")
            switch response.statusCode {
            case 200..<300: return .accepted
            case 408, 429, 500...599:
                let delay = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                return .retry(after: delay.map { min(max($0, 0), 24 * 60 * 60) })
            default: return .rejected
            }
        } catch {
            let failure = error as NSError
            // Do not log request bodies, tokens, URLs from errors or server bodies.
            ProductAnalytics.debugLog("Transport error code=\(failure.code)")
            return .retry(after: nil)
        }
    }
}
