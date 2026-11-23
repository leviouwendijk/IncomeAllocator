import Arguments
import Clipboard
import Foundation
import Income
import Terminal

private let format = IncomeFormat.standard

// MARK: - allocate

enum AllocateCommand: BoundArgumentCommand {
    static let name = "allocate"
    static let aliases = ["a"]

    struct Options: ArgumentGroup {
        @Arg("income", help: "Income per period: 2500, 2_500, 2.5k, € 2.500,00")
        var income: AmountValue

        @Opt("preset", short: "p", default: PlanValue(plan: .defaults), help: "Allocation preset (see `income presets`)")
        var preset: PlanValue

        @Opts("compare", short: "c", take: .many, help: "More incomes to compare side by side")
        var compare: [AmountValue]

        @Flag("copy", help: "Copy the plain-text report of the first income to the clipboard")
        var copy: Bool

        init() {}
    }

    static func run(
        _ options: Options,
        invocation: ParsedInvocation
    ) async throws {
        let plan = options.preset.plan
        let incomes = [try options.income.required()] + options.compare.compactMap(\.value)
        let distributions = incomes.map(plan.distribute)

        print("\(plan.name)".ansi(.bold) + "  " + "allocation per period".ansi(.dim))
        print()

        var table = TextTable([.left, .left] + incomes.map { _ in .right })
        table.row(
            [
                .init(text: "Account", colors: [.dim]),
                .init(text: "Rule", colors: [.dim]),
            ] + incomes.map { .init(text: format.amount($0), colors: [.bold]) }
        )
        table.separator()
        for (index, allocation) in plan.allocations.enumerated() {
            let cells: [TextTable.Cell] = distributions.map { distribution in
                let line = distribution.lines[index]
                return line.shortfall > 0
                    ? .init(text: format.amount(line.amount) + " !", colors: [.yellow])
                    : .init(text: format.amount(line.amount))
            }
            table.row(
                [
                    .init(text: allocation.account.name),
                    .init(text: format.share(allocation), colors: [.dim]),
                ] + cells
            )
        }
        table.separator()
        table.row(
            [.init(text: "Distributed"), .init(text: "")]
                + distributions.map { .init(text: format.amount($0.distributed)) }
        )
        table.row(
            [.init(text: "Free cash flow", colors: [.bold]), .init(text: "")]
                + distributions.map { .init(text: format.amount($0.unallocated), colors: [.green, .bold]) }
        )
        if distributions.contains(where: { $0.shortfall > 0 }) {
            table.row(
                [.init(text: "Shortfall", colors: [.yellow]), .init(text: "")]
                    + distributions.map { .init(text: format.amount($0.shortfall), colors: [.yellow]) }
            )
        }
        print(table.render())

        if let minimum = plan.minimumIncome(), minimum > 0 {
            print()
            print("Covers every allocation from ".ansi(.dim) + format.amount(minimum))
        }

        if options.copy, let first = distributions.first {
            Clipboard.system.write(format.report(first))
            print()
            print("Copied report for \(format.amount(first.income))".ansi(.dim))
        }
    }
}

// MARK: - presets

enum PresetsCommand: BoundArgumentCommand {
    static let name = "presets"
    static let aliases = ["ls"]

    struct Options: ArgumentGroup {
        init() {}
    }

    static func run(
        _ options: Options,
        invocation: ParsedInvocation
    ) async throws {
        for (index, plan) in AllocationPlan.presets.enumerated() {
            if index > 0 { print() }
            let marker = plan == .defaults ? "  (default)".ansi(.dim) : ""
            print(plan.name.ansi(.bold) + marker)
            var table = TextTable([.right, .left, .left])
            for (position, allocation) in plan.allocations.enumerated() {
                table.row(
                    [
                        .init(text: "\(position + 1).", colors: [.dim]),
                        .init(text: allocation.account.name),
                        .init(text: format.share(allocation), colors: [.dim]),
                    ]
                )
            }
            print(table.render(indent: "  "))
        }
    }
}

// MARK: - project

enum ProjectCommand: BoundArgumentCommand {
    static let name = "project"
    static let aliases = ["p"]

    struct Options: ArgumentGroup {
        @Arg("income", help: "Income per period")
        var income: AmountValue

        @Opt("preset", short: "p", default: PlanValue(plan: .defaults), help: "Allocation preset")
        var preset: PlanValue

        @Opt("account", short: "a", default: AccountValue(account: .savings), help: "Account to project, e.g. savings, income-tax")
        var account: AccountValue

        @Opt("target", short: "t", help: "Balance to reach in the account")
        var target: AmountValue

        @Opt("starting", short: "s", help: "Balance the account starts with")
        var starting: AmountValue

        @Opt("gross-target", short: "g", help: "Total income to reach")
        var grossTarget: AmountValue

        @Opt("periods", short: "n", default: CountValue(value: 12), help: "Periods to project the balance over")
        var periods: CountValue

        init() {}
    }

    static func run(
        _ options: Options,
        invocation: ParsedInvocation
    ) async throws {
        let plan = options.preset.plan
        let distribution = plan.distribute(try options.income.required())
        let account = try options.account.resolved(in: plan)
        let perPeriod = distribution.amount(for: account)
        let starting = options.starting.value ?? 0

        print(account.name.ansi(.bold) + " gets " + format.amount(perPeriod).ansi(.green, .bold) + " per period".ansi(.dim) + "  (\(plan.name), income \(format.amount(distribution.income)))".ansi(.dim))
        print()

        var table = TextTable([.left, .right, .left])
        let periods = options.periods.value
        table.row(
            .init(text: "After \(format.count(periods)) periods"),
            .init(text: format.amount(distribution.balance(of: account, after: periods, starting: starting))),
            .init(text: "")
        )
        if let target = options.target.value {
            table.row(
                .init(text: "Reach \(format.amount(target))"),
                periodsCell(distribution.periodsToReach(target, in: account, starting: starting)),
                .init(text: span(distribution.periodsToReach(target, in: account, starting: starting)), colors: [.dim])
            )
        }
        if let grossTarget = options.grossTarget.value {
            table.row(
                .init(text: "Earn \(format.amount(grossTarget)) gross"),
                periodsCell(distribution.periodsToReachGross(grossTarget)),
                .init(text: span(distribution.periodsToReachGross(grossTarget)), colors: [.dim])
            )
        }
        print(table.render())
    }

    private static func periodsCell(_ periods: Int?) -> TextTable.Cell {
        guard let periods else {
            return .init(text: "never", colors: [.yellow])
        }
        return .init(text: "\(format.count(periods)) periods", colors: [.bold])
    }

    /// Periods read as months.
    private static func span(_ periods: Int?) -> String {
        guard let periods, periods >= 12 else {
            return ""
        }
        let years = periods / 12
        let months = periods % 12
        return months == 0 ? "\(years) yr" : "\(years) yr \(months) mo"
    }
}

// MARK: - compound

enum CompoundCommand: BoundArgumentCommand {
    static let name = "compound"
    static let aliases = ["c"]

    struct Options: ArgumentGroup {
        @Opt("principal", default: AmountValue(0), help: "Starting balance")
        var principal: AmountValue

        @Opt("rate", short: "r", default: PercentValue(value: 10), help: "Yearly return in percent")
        var rate: PercentValue

        @Opt("monthly", short: "m", help: "Monthly contribution (or derive it with --income)")
        var monthly: AmountValue

        @Opt("income", short: "i", help: "Derive the monthly contribution from this income's allocation")
        var income: AmountValue

        @Opt("preset", short: "p", default: PlanValue(plan: .defaults), help: "Preset used with --income")
        var preset: PlanValue

        @Opt("account", short: "a", default: AccountValue(account: .savings), help: "Account used with --income")
        var account: AccountValue

        @Opt("years", short: "y", default: CountValue(value: 10), help: "Years to compound")
        var years: CountValue

        @Opt("timing", default: TimingValue(timing: .end), help: "Contribution at the beginning or end of each month")
        var timing: TimingValue

        @Flag("schedule", short: "s", help: "Print the value at the end of every year")
        var schedule: Bool

        init() {}
    }

    static func run(
        _ options: Options,
        invocation: ParsedInvocation
    ) async throws {
        var monthly = options.monthly.value ?? 0
        var source = ""
        if options.monthly.value == nil, let income = options.income.value {
            let plan = options.preset.plan
            let account = try options.account.resolved(in: plan)
            monthly = plan.distribute(income).amount(for: account)
            source = "  (\(account.name) of \(format.amount(income)), \(plan.name))".ansi(.dim)
        }

        let compounding = Compounding(
            principal: options.principal.value ?? 0,
            annualRate: options.rate.value,
            monthlyContribution: monthly,
            years: options.years.value,
            timing: options.timing.timing
        )
        let result = compounding.result()

        print("\(format.amount(monthly)) monthly".ansi(.bold) + " at \(format.percent(compounding.annualRate)) for \(compounding.years) years" + source)
        print()

        var summary = TextTable([.left, .right])
        summary.row(.init(text: "Contributed"), .init(text: format.amount(result.contributed)))
        summary.row(.init(text: "Growth"), .init(text: format.amount(result.gain), colors: [.green]))
        summary.separator()
        summary.row(.init(text: "Value", colors: [.bold]), .init(text: format.amount(result.value), colors: [.green, .bold]))
        print(summary.render())

        guard options.schedule, !result.years.isEmpty else {
            return
        }
        print()
        var table = TextTable([.right, .right, .right, .right])
        table.row(
            [
                .init(text: "Year", colors: [.dim]),
                .init(text: "Contributed", colors: [.dim]),
                .init(text: "Growth", colors: [.dim]),
                .init(text: "Value", colors: [.dim]),
            ]
        )
        table.separator()
        for year in result.years {
            table.row(
                "\(year.year)",
                format.amount(year.contributed),
                format.amount(year.gain),
                format.amount(year.value)
            )
        }
        print(table.render())
    }
}
