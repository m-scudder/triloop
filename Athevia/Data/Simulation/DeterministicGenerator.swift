#if DEBUG
import Foundation

/// A repeatable pseudo-random source.
///
/// Fixtures must not use `Double.random`: the same dataset and reference date
/// have to produce byte-identical workouts, loads and trends every run, or a
/// failing test cannot be reproduced and a UI change cannot be compared.
struct DeterministicGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Never zero: the xorshift below is a fixed point at zero.
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    /// Uniform in `range`, deterministic for a given seed and call order.
    mutating func value(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() % 1_000_000) / 1_000_000
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }

    mutating func value(in range: ClosedRange<Int>) -> Int {
        Int(value(in: Double(range.lowerBound)...Double(range.upperBound)).rounded())
    }
}
#endif
