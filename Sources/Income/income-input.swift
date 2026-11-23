import Foundation
import Parsers

/// Typed-in numbers, read with `Prebuilt.DecimalNumberParser`
/// (`2_500`, `€ 1.250,50`, `1,2m`, `35,5%`).
public enum IncomeInput {
    public enum Failure: Error, LocalizedError, Sendable, Equatable {
        case notWhole(Decimal)
        case negative(Decimal)

        public var errorDescription: String? {
            switch self {
            case .notWhole(let value):
                return "Expected a whole number, got \(value)"
            case .negative(let value):
                return "Expected zero or more, got \(value)"
            }
        }
    }

    /// A non-negative amount of money.
    public static func amount(
        _ text: String
    ) throws -> Decimal {
        try Prebuilt.DecimalNumberParser.parse(text, config: .amount).value
    }

    /// A percentage in 0...100, with or without `%`.
    public static func percent(
        _ text: String
    ) throws -> Decimal {
        try Prebuilt.DecimalNumberParser.parse(text, config: .percentage).value
    }

    /// A non-negative whole count (periods, years); `1k` reads as 1000.
    public static func count(
        _ text: String
    ) throws -> Int {
        let value = try Prebuilt.DecimalNumberParser.parse(
            text,
            config: .init(
                allowsNegative: false,
                allowsPercent: false,
                allowsCurrency: false,
                maximum: Decimal(Int32.max)
            )
        ).value
        guard value >= 0 else {
            throw Failure.negative(value)
        }
        guard value.rounded(scale: 0, mode: .plain) == value else {
            throw Failure.notWhole(value)
        }
        return NSDecimalNumber(decimal: value).intValue
    }

    /// `nil` for blank input, otherwise `parse(text)`.
    public static func optional<Value>(
        _ text: String,
        _ parse: (String) throws -> Value
    ) rethrows -> Value? {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : try parse(text)
    }
}
