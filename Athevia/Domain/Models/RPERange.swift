import Foundation

/// Rate of Perceived Exertion, 1–10.
///
/// Stored as a `Codable` value type so SwiftData persists it inline rather than
/// forcing two loose `Int` columns onto every workout.
struct RPERange: Codable, Hashable, Sendable {
    let lower: Int
    let upper: Int

    init(_ lower: Int, _ upper: Int) {
        let clampedLower = min(max(lower, RPEScale.minimum), RPEScale.maximum)
        let clampedUpper = min(max(upper, clampedLower), RPEScale.maximum)
        self.lower = clampedLower
        self.upper = clampedUpper
    }

    init(_ exact: Int) {
        self.init(exact, exact)
    }

    var isExact: Bool { lower == upper }

    func contains(_ value: Int) -> Bool {
        (lower...upper).contains(value)
    }
}

enum RPEScale {
    static let minimum = 1
    static let maximum = 10

    static func label(for value: Int) -> String {
        switch value {
        case ...1: "Almost no effort"
        case 2: "Extremely easy"
        case 3: "Easy"
        case 4: "Comfortable"
        case 5: "Moderate"
        case 6: "Getting difficult"
        case 7: "Hard"
        case 8: "Very hard"
        case 9: "Nearly maximum"
        default: "Maximum"
        }
    }
}
