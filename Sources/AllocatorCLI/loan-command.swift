import Arguments
import Foundation
import Income
import Terminal

private let format = IncomeFormat.standard

enum LoanCommand: BoundArgumentCommand {
    static let name = "loan"
    static let aliases = ["l"]

    struct Options: ArgumentGroup {
        @Arg("amount", help: "Amount to take now, e.g. 3000, 3k, € 3.000")
        var amount: AmountValue

        @Opt("months", short: "m", default: CountValue(value: 12), help: "Months to repay over")
        var months: CountValue

        @Flag("fit", help: "With --income: repay over the fewest months the free cash flow covers")
        var fit: Bool

        @Opt("from", short: "f", default: AccountValue(account: .savings), help: "Your account to borrow from")
        var from: AccountValue

        @Opt("external", short: "e", help: "Borrow from someone outside the plan instead (a name)")
        var external: String?

        @Opt("rate", short: "r", default: PercentValue(value: 0), help: "Yearly interest in percent (pay yourself interest too)")
        var rate: PercentValue

        @Opt("start", short: "s", default: CountValue(value: 1), help: "Period of the first installment")
        var start: CountValue

        @Opt("funding", default: FundingValue(funding: .freeCashFlow), help: "Pay from free cash flow (free) or before the plan runs (before)")
        var funding: FundingValue

        @Opt("income", short: "i", help: "Lay the loan over this income's plan")
        var income: AmountValue

        @Opt("preset", short: "p", default: PlanValue(plan: .defaults), help: "Preset used with --income")
        var preset: PlanValue

        @Opt("balance", short: "b", help: "Current balance of the account you borrow from")
        var balance: AmountValue

        init() {}
    }

    static func run(
        _ options: Options,
        invocation: ParsedInvocation
    ) async throws {
        let plan = options.preset.plan
        let lender: Lender
        if let external = options.external {
            lender = .external(external)
        } else if options.income.value != nil {
            lender = .account(try options.from.resolved(in: plan))
        } else {
            lender = .account(options.from.account)
        }

        let principal = try options.amount.required()
        var months = options.months.value
        if options.fit {
            guard let income = options.income.value else {
                throw LoanCommandError.fitNeedsIncome
            }
            guard let fitting = Loan.minimumMonths(
                principal: principal,
                annualRate: options.rate.value,
                budget: plan.distribute(income).unallocated
            ) else {
                throw LoanCommandError.nothingFits
            }
            months = fitting
        }

        let loan = try Loan(
            .init(
                lender: lender,
                principal: principal,
                months: months,
                annualRate: options.rate.value,
                firstPeriod: max(options.start.value, 1),
                funding: options.funding.funding
            )
        )

        let source = loan.lender.account == nil ? "from \(loan.lender)" : "from your \(loan.lender)"
        print("Loan ".ansi(.bold) + format.amount(loan.principal).ansi(.bold) + " \(source)".ansi(.dim) + " · \(loan.months) months · \(format.percent(loan.annualRate))")
        print(
            "Installment ".ansi(.dim) + format.amount(loan.installment).ansi(.bold)
                + "  interest ".ansi(.dim) + format.amount(loan.totalInterest)
                + "  total ".ansi(.dim) + format.amount(loan.totalPaid)
        )
        print()

        guard let income = options.income.value else {
            printSchedule(loan)
            return
        }

        let projection = LoanProjection(
            loan: loan,
            plan: plan,
            income: income,
            startingBalance: options.balance.value ?? 0
        )
        printProjection(projection)
    }

    private static func printSchedule(_ loan: Loan) {
        let hasInterest = loan.annualRate > 0
        var table = TextTable(hasInterest ? [.right, .right, .right, .right, .right] : [.right, .right, .right])
        let header = hasInterest
            ? ["Period", "Payment", "Interest", "Principal", "Outstanding"]
            : ["Period", "Payment", "Outstanding"]
        table.row(header.map { .init(text: $0, colors: [.dim]) })
        table.separator()
        for installment in loan.schedule() {
            var cells = [
                TextTable.Cell(text: "\(installment.period)"),
                .init(text: format.amount(installment.payment)),
            ]
            if hasInterest {
                cells.append(.init(text: format.amount(installment.interest), colors: [.dim]))
                cells.append(.init(text: format.amount(installment.principal)))
            }
            cells.append(.init(text: format.amount(installment.outstanding)))
            table.row(cells)
        }
        print(table.render())
        print()
        print("Add --income 2500 to see it against your plan.".ansi(.dim))
    }

    private static func printProjection(_ projection: LoanProjection) {
        let loan = projection.loan
        let account = projection.account
        let funding = loan.funding == .freeCashFlow
            ? "paid from free cash flow; allocations unchanged"
            : "paid before the plan runs; allocations shrink"
        print("\(projection.plan.name), income \(format.amount(projection.income)) · \(funding)".ansi(.dim))
        print()

        var columns: [TextTable.Alignment] = [.right, .right, .right]
        var header = ["Period", "Paid", "Free cash flow"]
        if let account {
            columns += [.right, .right]
            header += ["\(account.name)", "without loan"]
        }
        var table = TextTable(columns)
        table.row(header.map { .init(text: $0, colors: [.dim]) })
        table.separator()

        if account != nil {
            table.row(
                [
                    .init(text: "0", colors: [.dim]),
                    .init(text: "draw", colors: [.dim]),
                    .init(text: ""),
                    .init(text: format.amount(projection.startingBalance - loan.principal), colors: [.yellow]),
                    .init(text: format.amount(projection.startingBalance), colors: [.dim]),
                ]
            )
        }

        for period in projection.periods {
            let paid: TextTable.Cell = period.shortfall > 0
                ? .init(text: format.amount(period.paid) + " !", colors: [.yellow])
                : .init(text: period.installment == nil ? "–" : format.amount(period.paid))
            var cells: [TextTable.Cell] = [
                .init(text: "\(period.period)"),
                paid,
                .init(text: format.amount(period.freeCashFlow), colors: period.freeCashFlow < 0 ? [.red] : [.green]),
            ]
            if let balance = period.balance, let without = period.balanceWithoutLoan {
                cells.append(.init(text: format.amount(balance), colors: balance >= without ? [.green] : []))
                cells.append(.init(text: format.amount(without), colors: [.dim]))
            }
            table.row(cells)
        }
        print(table.render())
        print()

        if projection.fits {
            print("✓ ".ansi(.green) + "Every installment fits. Lowest free cash flow while repaying: " + format.amount(projection.lowestFreeCashFlow))
            if let account, let restored = projection.restoredAt {
                print("✓ ".ansi(.green) + "\(account.name) is back on track after period \(restored).")
            }
        } else {
            print("! ".ansi(.yellow) + "Short \(format.amount(projection.shortfall)) in total: the plan leaves too little each period.")
            if loan.funding == .freeCashFlow, let months = projection.monthsThatFit {
                print("  Fits over \(months) months (" + format.amount(Loan.installment(principal: loan.principal, months: months, annualRate: loan.annualRate)) + " a month), or use --funding before.")
            } else if loan.funding == .freeCashFlow {
                print("  The plan leaves no free cash flow; try --funding before.")
            }
        }
    }
}

enum LoanCommandError: Error, LocalizedError {
    case fitNeedsIncome
    case nothingFits

    var errorDescription: String? {
        switch self {
        case .fitNeedsIncome:
            return "--fit needs --income to know the free cash flow"
        case .nothingFits:
            return "The plan leaves no free cash flow to repay from; try --funding before"
        }
    }
}
