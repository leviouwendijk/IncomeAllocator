import Foundation

/// A destination for part of the income: a bank account, a pot, a budget line.
public struct Account: Sendable, Hashable, Codable, Comparable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let name: String

    public init(
        _ name: String
    ) {
        self.name = name
    }

    public init(
        stringLiteral value: String
    ) {
        self.init(value)
    }

    public init(
        from decoder: Decoder
    ) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(
        to encoder: Encoder
    ) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }

    public var description: String {
        name
    }

    /// Lowercased with spaces, dashes and underscores removed: `Income Tax` → `incometax`.
    public var key: String {
        Self.key(name)
    }

    public static func key(
        _ text: String
    ) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    public static func < (lhs: Account, rhs: Account) -> Bool {
        lhs.name < rhs.name
    }
}

public extension Account {
    static let savings: Account = "Savings"
    static let incomeTax: Account = "Income Tax"
    static let charges: Account = "Charges"
    static let purchases: Account = "Purchases"
    static let housing: Account = "Housing Expenses"
    static let living: Account = "Living Expenses"
    static let municipal: Account = "Municipal Bills"
}
