import Foundation
import Primitives

/// How much of the income an allocation asks for.
public enum Share: Sendable, Hashable, Codable {
    /// A percentage of the whole income.
    case ofIncome(percent: Decimal)
    /// A percentage of what earlier allocations left over.
    case ofRemainder(percent: Decimal)
    /// A fixed amount per period, whatever the income.
    case fixed(Decimal)
    /// Everything that is left.
    case remainder

    public var percent: Decimal? {
        switch self {
        case .ofIncome(let percent), .ofRemainder(let percent):
            return percent
        case .fixed, .remainder:
            return nil
        }
    }
}

public enum AllocationError: Error, LocalizedError, Sendable, Equatable {
    case percentOutOfRange(Account, Decimal)
    case negativeAmount(Account, Decimal)
    case floorAboveCap(Account, floor: Decimal, cap: Decimal)

    public var errorDescription: String? {
        switch self {
        case .percentOutOfRange(let account, let percent):
            return "\(account): percentage must be within 0...100, got \(percent)"
        case .negativeAmount(let account, let amount):
            return "\(account): amounts cannot be negative, got \(amount)"
        case .floorAboveCap(let account, let floor, let cap):
            return "\(account): floor \(floor) is above cap \(cap)"
        }
    }
}

/// One rule of a plan: an account, its share, and optional bounds.
///
/// `floor` and `cap` bound what the share asks for. A floor turns a percentage into
/// "at least this much" (useful when income varies), a cap into "at most this much".
public struct Allocation: CodableInvariant, Sendable, Hashable {
    public struct Raw: Sendable, Hashable, Codable {
        public var account: Account
        public var share: Share
        public var floor: Decimal?
        public var cap: Decimal?

        public init(
            account: Account,
            share: Share,
            floor: Decimal? = nil,
            cap: Decimal? = nil
        ) {
            self.account = account
            self.share = share
            self.floor = floor
            self.cap = cap
        }
    }

    public typealias Error = AllocationError

    public let raw: Raw

    public init(
        _ raw: Raw
    ) throws(AllocationError) {
        switch raw.share {
        case .ofIncome(let percent), .ofRemainder(let percent):
            guard percent >= 0, percent <= 100 else {
                throw .percentOutOfRange(raw.account, percent)
            }
        case .fixed(let amount):
            guard amount >= 0 else {
                throw .negativeAmount(raw.account, amount)
            }
        case .remainder:
            break
        }
        for bound in [raw.floor, raw.cap].compactMap({ $0 }) where bound < 0 {
            throw .negativeAmount(raw.account, bound)
        }
        if let floor = raw.floor, let cap = raw.cap, floor > cap {
            throw .floorAboveCap(raw.account, floor: floor, cap: cap)
        }
        self.raw = raw
    }

    /// For literal plans whose validity the tests assert.
    init(
        unchecked raw: Raw
    ) {
        self.raw = raw
    }

    public var account: Account { raw.account }
    public var share: Share { raw.share }
    public var floor: Decimal? { raw.floor }
    public var cap: Decimal? { raw.cap }

    /// What the rule asks for, given the income and what is still unallocated.
    public func requested(
        income: Decimal,
        remaining: Decimal
    ) -> Decimal {
        var amount: Decimal
        switch share {
        case .ofIncome(let percent):
            amount = max(income, 0) * percent / 100
        case .ofRemainder(let percent):
            amount = max(remaining, 0) * percent / 100
        case .fixed(let fixed):
            amount = fixed
        case .remainder:
            amount = max(remaining, 0)
        }
        if let floor { amount = max(amount, floor) }
        if let cap { amount = min(amount, cap) }
        return amount
    }

    /// The amount the share is a percentage of, if it is one.
    public func base(
        income: Decimal,
        remaining: Decimal
    ) -> Decimal? {
        switch share {
        case .ofIncome:
            return income
        case .ofRemainder, .remainder:
            return remaining
        case .fixed:
            return nil
        }
    }
}
