import Foundation
import Primitives

public enum AllocationPlanError: Error, LocalizedError, Sendable, Equatable {
    case emptyName
    case duplicateAccount(Account)
    case remainderNotLast(Account)

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            return "A plan needs a name"
        case .duplicateAccount(let account):
            return "\(account) appears more than once in the plan"
        case .remainderNotLast(let account):
            return "\(account) takes the remainder, so it must be the last allocation"
        }
    }
}

/// An ordered list of allocations. Order matters: each allocation sees what the earlier ones left.
public struct AllocationPlan: CodableInvariant, Sendable, Hashable, Identifiable {
    public struct Raw: Sendable, Hashable, Codable {
        public var name: String
        public var allocations: [Allocation]

        public init(
            name: String,
            allocations: [Allocation]
        ) {
            self.name = name
            self.allocations = allocations
        }
    }

    public typealias Error = AllocationPlanError

    public let raw: Raw

    public init(
        _ raw: Raw
    ) throws(AllocationPlanError) {
        guard !raw.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw .emptyName
        }
        var seen: Set<String> = []
        for (index, allocation) in raw.allocations.enumerated() {
            guard seen.insert(allocation.account.key).inserted else {
                throw .duplicateAccount(allocation.account)
            }
            if allocation.share == .remainder, index != raw.allocations.count - 1 {
                throw .remainderNotLast(allocation.account)
            }
        }
        self.raw = raw
    }

    init(
        unchecked raw: Raw
    ) {
        self.raw = raw
    }

    public var id: String { raw.name }
    public var name: String { raw.name }
    public var allocations: [Allocation] { raw.allocations }
    public var accounts: [Account] { raw.allocations.map(\.account) }

    public func allocation(
        for account: Account
    ) -> Allocation? {
        allocations.first { $0.account.key == account.key }
    }

    public func distribute(
        _ income: Decimal
    ) -> Distribution {
        Distribution(
            income: income,
            plan: self
        )
    }

    /// The lowest income (to the cent) at which every allocation gets what it asks for,
    /// or `nil` if no income up to `limit` covers the plan.
    ///
    /// Only fixed amounts and floors can leave a shortfall, so plans of pure
    /// percentages are covered by any income and return `0`.
    public func minimumIncome(
        limit: Decimal = 1_000_000_000
    ) -> Decimal? {
        guard distribute(limit).shortfall == 0 else {
            return nil
        }
        guard distribute(0).shortfall > 0 else {
            return 0
        }
        var low: Decimal = 0
        var high = limit
        while high - low > Decimal(string: "0.01")! {
            let middle = (low + high) / 2
            if distribute(middle).shortfall > 0 {
                low = middle
            } else {
                high = middle
            }
        }
        let down = high.rounded(scale: 2, mode: .down)
        return distribute(down).shortfall == 0 ? down : high.rounded(scale: 2, mode: .up)
    }
}

public extension AllocationPlan {
    static func named(
        _ name: String
    ) -> AllocationPlan? {
        let key = Account.key(name)
        return presets.first { Account.key($0.name) == key }
    }

    static let presets: [AllocationPlan] = [
        defaults,
        previous,
        adaptationA,
        adaptationB,
        adaptationC,
    ]

    static let defaults = plan("defaults", [
        (.savings, .ofIncome(percent: 15)),
        (.incomeTax, .ofIncome(percent: decimal("35.5"))),
        (.charges, .ofRemainder(percent: decimal("2.75"))),
        (.purchases, .ofRemainder(percent: decimal("14.5"))),
        (.housing, .ofIncome(percent: 20)),
        (.living, .ofIncome(percent: decimal("12.5"))),
        (.municipal, .ofRemainder(percent: decimal("7.25"))),
    ])

    static let previous = plan("previous", [
        (.savings, .ofIncome(percent: 10)),
        (.incomeTax, .ofRemainder(percent: 20)),
        (.charges, .ofRemainder(percent: 10)),
    ])

    static let adaptationA = plan("adaptation a", [
        (.savings, .ofIncome(percent: 10)),
        (.purchases, .ofIncome(percent: 20)),
        (.living, .ofIncome(percent: 45)),
        (.incomeTax, .ofIncome(percent: 15)),
    ])

    static let adaptationB = plan("adaptation b", [
        (.savings, .ofIncome(percent: 15)),
        (.incomeTax, .ofIncome(percent: decimal("35.5"))),
        (.charges, .ofIncome(percent: decimal("1.36125"))),
        (.purchases, .ofIncome(percent: decimal("6.98011875"))),
        (.housing, .ofIncome(percent: 20)),
        (.living, .ofIncome(percent: decimal("12.5"))),
        (.municipal, .ofIncome(percent: decimal("0.627750765625"))),
    ])

    static let adaptationC = plan("adaptation c", [
        (.savings, .ofIncome(percent: 15)),
        (.incomeTax, .ofIncome(percent: 35)),
        (.charges, .ofIncome(percent: 2)),
        (.purchases, .ofIncome(percent: 5)),
        (.housing, .ofIncome(percent: 20)),
        (.living, .ofIncome(percent: 15)),
        (.municipal, .ofIncome(percent: 1)),
    ])

    private static func plan(
        _ name: String,
        _ rules: [(Account, Share)]
    ) -> AllocationPlan {
        AllocationPlan(
            unchecked: .init(
                name: name,
                allocations: rules.map { account, share in
                    Allocation(unchecked: .init(account: account, share: share))
                }
            )
        )
    }

    private static func decimal(
        _ text: String
    ) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }
}
