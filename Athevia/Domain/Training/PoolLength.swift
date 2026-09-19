import Foundation

/// The pool the athlete actually trains in.
///
/// Swim volume only means something in whole lengths: prescribing 300 m in a
/// 50 m pool has to be six lengths, not twelve. Validation lives here so an
/// invalid length cannot reach the generator.
struct PoolLength: Equatable, Sendable {
    /// Below this a "length" is not a meaningful training unit; above it is
    /// beyond any competition pool.
    static let permittedRange: ClosedRange<Double> = 10...100

    static let short = PoolLength(meters: 25)
    static let olympic = PoolLength(meters: 50)

    let meters: Double

    /// Clamps rather than failing: a stored profile must always yield a usable
    /// pool, and the onboarding form validates before it ever gets here.
    init(meters: Double) {
        self.meters = min(max(meters, Self.permittedRange.lowerBound), Self.permittedRange.upperBound)
    }

    static func isValid(_ meters: Double) -> Bool {
        permittedRange.contains(meters)
    }

    /// The repeat distance to build a swim set from.
    ///
    /// Ability wins over geometry. An athlete who can hold 25 m in a 50 m pool
    /// gets 25 m repeats, stopping mid-pool, rather than a 50 m repeat they
    /// cannot complete.
    func repeatDistance(for baseline: SwimmingBaseline) -> Double {
        guard let continuous = baseline.continuousMeters else { return meters }
        return min(continuous, meters)
    }

    /// True when the athlete can swim at least one whole length.
    ///
    /// While false, the swim engine must not progress continuity: the next step
    /// up would finish between walls, so rest and volume are the only honest
    /// levers left.
    func supportsWholeLengths(for baseline: SwimmingBaseline) -> Bool {
        guard let continuous = baseline.continuousMeters else { return false }
        return continuous >= meters
    }

    /// Rounds a target volume to whole repeats, never below one.
    func roundedVolume(_ target: Double, repeatDistance: Double) -> Double {
        let unit = repeatDistance > 0 ? repeatDistance : meters
        return max((target / unit).rounded(), 1) * unit
    }

    /// Whole repeats a volume breaks into, which is what the athlete counts.
    func repeats(of volume: Double, repeatDistance: Double) -> Int {
        let unit = repeatDistance > 0 ? repeatDistance : meters
        return max(Int((volume / unit).rounded()), 1)
    }
}
