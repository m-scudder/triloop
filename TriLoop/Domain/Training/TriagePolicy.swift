import Foundation

/// Thresholds that sort a session into GREEN / YELLOW / RED.
///
/// Values live here rather than inline in the engines so they can be tuned in
/// one place, and so a test can state the threshold it is exercising.
struct TriagePolicy: Equatable, Sendable {
    var minimumCompletionForProgress: Double = 0.9
    var lowCompletionThreshold: Double = 0.75
    var maximumRPEForProgress: Int = 5
    var rpeRequiringReduction: Int = 8
    var maximumPainForProgress: Int = 1
    var painRequiringReduction: Int = 4
    var worstRecoveryAllowingProgress: RecoveryFeeling = .good
    var reductionFraction: Double = 0.2
}

extension TriagePolicy {
    /// Running carries the highest impact cost of the three sports, so it backs
    /// off at a lower pain score than swimming or cycling.
    static let running = TriagePolicy(painRequiringReduction: 3)

    /// Swimming is low impact and technique-limited, so mild discomfort and a
    /// slightly higher effort are tolerated before reducing.
    static let swimming = TriagePolicy(
        maximumRPEForProgress: 6,
        painRequiringReduction: 5
    )

    static let cycling = TriagePolicy()
}
