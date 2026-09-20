import Foundation

/// A value the intelligence layer either has, or explicitly does not.
///
/// §55: a missing metric is never zero. An athlete with no power meter has no
/// FTP — reporting `0 W` would be a measurement that never happened, and any
/// average or trend built on it would be quietly wrong.
///
/// The four cases are distinct because they call for different responses: an
/// absent sensor is permanent, insufficient history resolves with time, and a
/// query failure is a bug worth surfacing.
enum IntelligenceValue<Value> {
    case available(Value)
    /// The metric was never recorded — no sensor, no permission, no sample.
    case unavailable
    /// Enough readings exist to know there are not enough readings.
    case insufficientHistory(found: Int, required: Int)
    case queryFailure

    var value: Value? {
        if case .available(let value) = self { return value }
        return nil
    }

    var isAvailable: Bool { value != nil }

    /// Wraps an optional, treating `nil` as never recorded.
    init(_ optional: Value?) {
        self = optional.map(Self.available) ?? .unavailable
    }

    func map<Other>(_ transform: (Value) -> Other) -> IntelligenceValue<Other> {
        switch self {
        case .available(let value): .available(transform(value))
        case .unavailable: .unavailable
        case .insufficientHistory(let found, let required): .insufficientHistory(found: found, required: required)
        case .queryFailure: .queryFailure
        }
    }
}

extension IntelligenceValue: Equatable where Value: Equatable {}
extension IntelligenceValue: Sendable where Value: Sendable {}
