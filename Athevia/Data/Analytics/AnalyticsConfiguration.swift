import Foundation

enum AnalyticsEnvironment: String, Codable {
    case development, testflight, production

    static func resolve(isDebug: Bool, receiptName: String?) -> Self {
        if isDebug { return .development }
        if receiptName == "sandboxReceipt" { return .testflight }
        // Ad-hoc/unsigned Release builds have no App Store receipt. Fail closed
        // into development instead of contaminating the production project.
        return receiptName == "receipt" ? .production : .development
    }
}

struct AnalyticsConfiguration: Equatable {
    let projectToken: String
    let host: URL
    let environment: AnalyticsEnvironment

    init?(projectToken: String, host: String, environment: AnalyticsEnvironment) {
        let token = projectToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        // Project ingestion tokens only; never ship a personal/secret API key.
        guard token.hasPrefix("phc_"), token.count > 12,
              token.dropFirst(4).allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              ["https://us.i.posthog.com", "https://eu.i.posthog.com"].contains(host),
              let url = URL(string: host) else { return nil }
        self.projectToken = token
        self.host = url
        self.environment = environment
    }

    static func resolve(info: [String: Any], environment: AnalyticsEnvironment) -> Self? {
        let configPrefix = environment == .production ? "PostHogProduction" : "PostHogDevelopment"
        let token = (info[configPrefix + "Token"] as? String) ?? ""
        // A misconfigured development build must never fall back to production.
        if environment != .production,
           token == (info["PostHogProductionToken"] as? String) { return nil }
        return Self(projectToken: token, host: (info[configPrefix + "Host"] as? String) ?? "",
                    environment: environment)
    }

    static var current: Self? {
        #if DEBUG
        let debug = true
        #else
        let debug = false
        #endif
        return resolve(info: Bundle.main.infoDictionary ?? [:], environment: .resolve(
            isDebug: debug, receiptName: Bundle.main.appStoreReceiptURL?.lastPathComponent
        ))
    }
}
