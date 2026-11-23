import Foundation

/// A plan applied to one income.
///
/// Allocations run in plan order. Each takes what it asks for, but never more than is
/// still unallocated: when fixed amounts or floors ask for more than the income holds,
/// the difference is reported as a shortfall instead of a negative remainder.
public struct Distribution: Sendable, Hashable {
    public struct Line: Sendable, Hashable, Identifiable {
        public let allocation: Allocation
        /// What a percentage share was taken from; `nil` for fixed amounts.
        public let base: Decimal?
        /// What the rule asked for, after its floor and cap.
        public let requested: Decimal
        /// What it got.
        public let amount: Decimal
        /// Unallocated income after this line.
        public let remaining: Decimal
        public let income: Decimal

        public var id: String { allocation.account.key }
        public var account: Account { allocation.account }
        public var shortfall: Decimal { requested - amount }

        /// This line's amount as a percentage of the whole income.
        public var percentOfIncome: Decimal {
            income > 0 ? amount / income * 100 : 0
        }
    }

    public let income: Decimal
    public let plan: AllocationPlan
    public let lines: [Line]

    public init(
        income: Decimal,
        plan: AllocationPlan
    ) {
        var remaining = max(income, 0)
        var lines: [Line] = []
        lines.reserveCapacity(plan.allocations.count)

        for allocation in plan.allocations {
            let base = allocation.base(income: max(income, 0), remaining: remaining)
            let requested = allocation.requested(income: income, remaining: remaining)
            let amount = min(requested, remaining)
            remaining -= amount
            lines.append(
                Line(
                    allocation: allocation,
                    base: base,
                    requested: requested,
                    amount: amount,
                    remaining: remaining,
                    income: income
                )
            )
        }

        self.income = income
        self.plan = plan
        self.lines = lines
    }

    public var distributed: Decimal {
        lines.reduce(0) { $0 + $1.amount }
    }

    /// Income no allocation claimed: the free cash flow.
    public var unallocated: Decimal {
        lines.last?.remaining ?? max(income, 0)
    }

    /// What the allocations asked for but could not get.
    public var shortfall: Decimal {
        lines.reduce(0) { $0 + $1.shortfall }
    }

    public var percentDistributed: Decimal {
        income > 0 ? distributed / income * 100 : 0
    }

    public var percentUnallocated: Decimal {
        income > 0 ? unallocated / income * 100 : 0
    }

    public func line(
        for account: Account
    ) -> Line? {
        lines.first { $0.account.key == account.key }
    }

    /// What `account` receives each period; `0` when the plan has no such account.
    public func amount(
        for account: Account
    ) -> Decimal {
        line(for: account)?.amount ?? 0
    }
}
