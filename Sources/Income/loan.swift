import Foundation
import Primitives

/// Who the money is borrowed from.
public enum Lender: Sendable, Hashable, Codable, CustomStringConvertible {
    /// One of your own accounts: the draw lowers its balance, repayments restore it.
    case account(Account)
    /// A bank, a person, anyone outside the plan.
    case external(String)

    public var description: String {
        switch self {
        case .account(let account):
            return account.name
        case .external(let name):
            return name
        }
    }

    public var account: Account? {
        if case .account(let account) = self {
            return account
        }
        return nil
    }
}

/// Where the monthly installment comes from.
public enum LoanFunding: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    /// Out of what the plan leaves unallocated; allocations stay exactly as planned.
    case freeCashFlow
    /// Off the top of the income, before the plan runs; every allocation shrinks a little.
    case beforeAllocations

    public var id: String { rawValue }
}

public enum LoanError: Error, LocalizedError, Sendable, Equatable {
    case nonPositivePrincipal(Decimal)
    case monthsOutOfRange(Int)
    case rateOutOfRange(Decimal)
    case firstPeriodBeforeOne(Int)
    case unnamedLender

    public var errorDescription: String? {
        switch self {
        case .nonPositivePrincipal(let principal):
            return "A loan needs an amount above zero, got \(principal)"
        case .monthsOutOfRange(let months):
            return "Repay over 1...\(Loan.maximumMonths) months, got \(months)"
        case .rateOutOfRange(let rate):
            return "Interest must be within 0...100 %, got \(rate)"
        case .firstPeriodBeforeOne(let period):
            return "Repayment starts at period 1 or later, got \(period)"
        case .unnamedLender:
            return "The lender needs a name"
        }
    }
}

/// Money taken now and repaid in equal monthly installments (an annuity when there is interest).
public struct Loan: CodableInvariant, Sendable, Hashable {
    public static let maximumMonths = 600

    public struct Raw: Sendable, Hashable, Codable {
        public var lender: Lender
        public var principal: Decimal
        public var months: Int
        /// Yearly interest in percent; `0` for a plain loan to yourself.
        public var annualRate: Decimal
        /// The period of the first installment (`1` = the first period after the draw).
        public var firstPeriod: Int
        public var funding: LoanFunding

        public init(
            lender: Lender = .account(.savings),
            principal: Decimal,
            months: Int,
            annualRate: Decimal = 0,
            firstPeriod: Int = 1,
            funding: LoanFunding = .freeCashFlow
        ) {
            self.lender = lender
            self.principal = principal
            self.months = months
            self.annualRate = annualRate
            self.firstPeriod = firstPeriod
            self.funding = funding
        }
    }

    public typealias Error = LoanError

    public struct Installment: Sendable, Hashable, Identifiable {
        public let period: Int
        public let payment: Decimal
        public let interest: Decimal
        public let principal: Decimal
        /// What is still owed after this installment.
        public let outstanding: Decimal

        public var id: Int { period }
    }

    public let raw: Raw

    public init(
        _ raw: Raw
    ) throws(LoanError) {
        guard raw.principal > 0 else {
            throw .nonPositivePrincipal(raw.principal)
        }
        guard (1...Self.maximumMonths).contains(raw.months) else {
            throw .monthsOutOfRange(raw.months)
        }
        guard raw.annualRate >= 0, raw.annualRate <= 100 else {
            throw .rateOutOfRange(raw.annualRate)
        }
        guard raw.firstPeriod >= 1 else {
            throw .firstPeriodBeforeOne(raw.firstPeriod)
        }
        if case .external(let name) = raw.lender,
           name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw .unnamedLender
        }
        self.raw = raw
    }

    public var lender: Lender { raw.lender }
    public var principal: Decimal { raw.principal }
    public var months: Int { raw.months }
    public var annualRate: Decimal { raw.annualRate }
    public var firstPeriod: Int { raw.firstPeriod }
    public var funding: LoanFunding { raw.funding }
    public var lastPeriod: Int { raw.firstPeriod + raw.months - 1 }

    /// The regular monthly installment, to the cent. The last one absorbs rounding.
    public var installment: Decimal {
        Self.installment(principal: principal, months: months, annualRate: annualRate)
    }

    public static func installment(
        principal: Decimal,
        months: Int,
        annualRate: Decimal
    ) -> Decimal {
        guard months > 0 else {
            return principal
        }
        let rate = annualRate / 100 / 12
        guard rate > 0 else {
            return (principal / Decimal(months)).rounded(scale: 2, mode: .up)
        }
        let growth = pow(1 + rate, months)
        return (principal * rate * growth / (growth - 1)).rounded(scale: 2, mode: .up)
    }

    public func schedule() -> [Installment] {
        let rate = annualRate / 100 / 12
        let regular = installment
        var outstanding = principal
        var installments: [Installment] = []
        installments.reserveCapacity(months)

        for index in 0..<months {
            let interest = (outstanding * rate).rounded(scale: 2, mode: .plain)
            let isLast = index == months - 1
            let payment = isLast ? outstanding + interest : min(regular, outstanding + interest)
            let repaid = payment - interest
            outstanding -= repaid
            installments.append(
                Installment(
                    period: firstPeriod + index,
                    payment: payment,
                    interest: interest,
                    principal: repaid,
                    outstanding: outstanding
                )
            )
            if outstanding <= 0 {
                break
            }
        }
        return installments
    }

    public var totalInterest: Decimal {
        schedule().reduce(0) { $0 + $1.interest }
    }

    public var totalPaid: Decimal {
        principal + totalInterest
    }

    /// The fewest months (up to `maximumMonths`) whose installment fits in `budget` per month.
    public static func minimumMonths(
        principal: Decimal,
        annualRate: Decimal = 0,
        budget: Decimal
    ) -> Int? {
        guard budget > 0 else {
            return nil
        }
        return (1...maximumMonths).first {
            installment(principal: principal, months: $0, annualRate: annualRate) <= budget
        }
    }
}

/// A loan laid over a plan and a steady income, period by period.
///
/// Period 0 is the draw. Each later period runs the plan, pays the installment the way
/// the loan's funding says, and, for a loan from one of your accounts, tracks that
/// account's balance next to where it would have been without the loan.
public struct LoanProjection: Sendable, Hashable {
    public struct Period: Sendable, Hashable, Identifiable {
        public let period: Int
        public let installment: Loan.Installment?
        public let distribution: Distribution
        /// What was actually paid this period.
        public let paid: Decimal
        /// Free cash flow left after the installment.
        public let freeCashFlow: Decimal
        /// Installment that could not be paid this period.
        public let shortfall: Decimal
        /// The lender account's balance, when lending from yourself.
        public let balance: Decimal?
        public let balanceWithoutLoan: Decimal?

        public var id: Int { period }
    }

    public let loan: Loan
    public let plan: AllocationPlan
    public let income: Decimal
    public let startingBalance: Decimal
    public let periods: [Period]

    public init(
        loan: Loan,
        plan: AllocationPlan,
        income: Decimal,
        startingBalance: Decimal = 0,
        periods count: Int? = nil
    ) {
        let installments = Dictionary(uniqueKeysWithValues: loan.schedule().map { ($0.period, $0) })
        let account = loan.lender.account.flatMap { plan.allocation(for: $0)?.account ?? $0 }
        let baseline = plan.distribute(income)
        let total = max(count ?? 0, loan.lastPeriod)

        var balance = account.map { _ in startingBalance - loan.principal }
        var balanceWithoutLoan = account.map { _ in startingBalance }
        var periods: [Period] = []
        periods.reserveCapacity(total)

        for period in 1...max(total, 1) {
            let installment = installments[period]
            let due = installment?.payment ?? 0
            let distribution: Distribution
            let paid: Decimal
            let freeCashFlow: Decimal

            switch loan.funding {
            case .freeCashFlow:
                distribution = baseline
                paid = min(due, max(baseline.unallocated, 0))
                freeCashFlow = baseline.unallocated - paid
            case .beforeAllocations:
                paid = min(due, max(income, 0))
                distribution = plan.distribute(income - paid)
                freeCashFlow = distribution.unallocated
            }

            if let account {
                balance? += distribution.amount(for: account) + paid
                balanceWithoutLoan? += baseline.amount(for: account)
            }

            periods.append(
                Period(
                    period: period,
                    installment: installment,
                    distribution: distribution,
                    paid: paid,
                    freeCashFlow: freeCashFlow,
                    shortfall: due - paid,
                    balance: balance,
                    balanceWithoutLoan: balanceWithoutLoan
                )
            )
        }

        self.loan = loan
        self.plan = plan
        self.income = income
        self.startingBalance = startingBalance
        self.periods = periods
    }

    /// The lender account, spelled as the plan spells it.
    public var account: Account? {
        loan.lender.account.map { plan.allocation(for: $0)?.account ?? $0 }
    }

    public var shortfall: Decimal {
        periods.reduce(0) { $0 + $1.shortfall }
    }

    public var fits: Bool {
        shortfall == 0
    }

    /// The lowest free cash flow while repaying.
    public var lowestFreeCashFlow: Decimal {
        periods.filter { $0.installment != nil }.map(\.freeCashFlow).min() ?? 0
    }

    /// The first period the lender account is back where it would have been without the loan.
    public var restoredAt: Int? {
        periods.first { period in
            guard let balance = period.balance, let without = period.balanceWithoutLoan else {
                return false
            }
            return balance >= without
        }?.period
    }

    /// The fewest months that fit this income's free cash flow (only for `.freeCashFlow` funding).
    public var monthsThatFit: Int? {
        Loan.minimumMonths(
            principal: loan.principal,
            annualRate: loan.annualRate,
            budget: plan.distribute(income).unallocated
        )
    }
}
