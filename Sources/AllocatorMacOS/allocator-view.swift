import Charts
import Income
import SwiftUI

struct AllocatorView: View {
    let model: AllocatorModel

    var body: some View {
        HStack(spacing: 0) {
            InputsPane(model: model)
                .frame(width: 320)

            Divider()

            VStack(spacing: 0) {
                DistributionPane(model: model)

                Divider()

                TabView {
                    HStack(alignment: .top, spacing: 0) {
                        ProjectionPane(model: model)
                            .frame(maxWidth: .infinity)
                        Divider()
                        CompoundingPane(model: model)
                            .frame(maxWidth: .infinity)
                    }
                    .tabItem { Text("Projection") }

                    LoanPane(model: model)
                        .tabItem { Text("Loan") }
                }
                .padding(.top, 8)
                .frame(height: 320)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    model.copyReport()
                } label: {
                    Label("Copy Report", systemImage: "doc.on.doc")
                }
                .help("Copy the allocation as text (⇧⌘C)")
                .disabled(model.distribution == nil)
            }
        }
    }
}

// MARK: - inputs

private struct InputsPane: View {
    let model: AllocatorModel

    var body: some View {
        let bindable = Bindable(wrappedValue: model)

        Form {
            Section("Income") {
                NumberField(
                    "Income per period",
                    text: bindable.incomeText,
                    prompt: "2.500",
                    problem: model.problem(model.incomeText, IncomeInput.amount)
                )
                Picker("Preset", selection: bindable.planName) {
                    ForEach(AllocationPlan.presets) { plan in
                        Text(plan.name).tag(plan.name)
                    }
                }
                if let minimum = model.minimumIncome {
                    LabeledContent("Covers the plan from", value: model.format.amount(minimum))
                }
            }

            Section("Projection") {
                Picker("Account", selection: bindable.account) {
                    ForEach(model.plan.accounts, id: \.self) { account in
                        Text(account.name).tag(account)
                    }
                }
                NumberField(
                    "Target balance",
                    text: bindable.targetText,
                    prompt: "50.000",
                    problem: model.problem(model.targetText, IncomeInput.amount)
                )
                NumberField(
                    "Starting balance",
                    text: bindable.startingText,
                    prompt: "0",
                    problem: model.problem(model.startingText, IncomeInput.amount)
                )
                NumberField(
                    "Gross target",
                    text: bindable.grossTargetText,
                    prompt: "1.000.000",
                    problem: model.problem(model.grossTargetText, IncomeInput.amount)
                )
                NumberField(
                    "Periods",
                    text: bindable.periodsText,
                    prompt: "12",
                    problem: model.problem(model.periodsText, IncomeInput.count)
                )
            }

            Section("Compounding") {
                NumberField(
                    "Principal",
                    text: bindable.principalText,
                    prompt: "0",
                    problem: model.problem(model.principalText, IncomeInput.amount)
                )
                NumberField(
                    "Yearly return %",
                    text: bindable.rateText,
                    prompt: "7",
                    problem: model.problem(model.rateText, IncomeInput.percent)
                )
                NumberField(
                    "Monthly",
                    text: bindable.monthlyText,
                    prompt: "\(model.projectedAccount.name): \(model.format.amount(model.perPeriod))",
                    problem: model.problem(model.monthlyText, IncomeInput.amount)
                )
                NumberField(
                    "Years",
                    text: bindable.yearsText,
                    prompt: "10",
                    problem: model.problem(model.yearsText, IncomeInput.count)
                )
                Picker("Contribution", selection: bindable.timing) {
                    Text("Start of month").tag(Compounding.Timing.beginning)
                    Text("End of month").tag(Compounding.Timing.end)
                }
            }

            Section("Loan") {
                NumberField(
                    "Amount",
                    text: bindable.loanAmountText,
                    prompt: "3.000",
                    problem: model.problem(model.loanAmountText, IncomeInput.amount)
                )
                Picker("From", selection: bindable.loanLender) {
                    ForEach(model.plan.accounts, id: \.self) { account in
                        Text(account.name).tag(account.name)
                    }
                    Divider()
                    Text("External").tag(AllocatorModel.externalLender)
                }
                if model.loanLender == AllocatorModel.externalLender {
                    TextField("Lender", text: bindable.loanExternalName)
                        .multilineTextAlignment(.trailing)
                } else {
                    NumberField(
                        "Current balance",
                        text: bindable.loanBalanceText,
                        prompt: "0",
                        problem: model.problem(model.loanBalanceText, IncomeInput.amount)
                    )
                }
                HStack {
                    NumberField(
                        "Months",
                        text: bindable.loanMonthsText,
                        prompt: "12",
                        problem: model.problem(model.loanMonthsText, IncomeInput.count)
                    )
                    Button("Fit") {
                        model.fitLoanMonths()
                    }
                    .help("Fewest months the free cash flow covers")
                    .disabled(model.loanProjection?.monthsThatFit == nil)
                }
                NumberField(
                    "Yearly interest %",
                    text: bindable.loanRateText,
                    prompt: "0",
                    problem: model.problem(model.loanRateText, IncomeInput.percent)
                )
                Picker("Repay", selection: bindable.loanFunding) {
                    Text("From free cash flow").tag(LoanFunding.freeCashFlow)
                    Text("Before allocations").tag(LoanFunding.beforeAllocations)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct NumberField: View {
    let title: String
    let text: Binding<String>
    let prompt: String
    let problem: String?

    init(
        _ title: String,
        text: Binding<String>,
        prompt: String,
        problem: String?
    ) {
        self.title = title
        self.text = text
        self.prompt = prompt
        self.problem = problem
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            TextField(title, text: text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}

// MARK: - distribution

private struct DistributionPane: View {
    let model: AllocatorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let distribution = model.distribution {
                HStack(alignment: .firstTextBaseline) {
                    Text(model.format.amount(distribution.income))
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(distribution.plan.name)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                Table(distribution.lines) {
                    TableColumn("Account") { line in
                        Text(line.account.name)
                            .fontWeight(line.account == model.projectedAccount ? .semibold : .regular)
                    }
                    TableColumn("Rule") { line in
                        Text(model.format.share(line.allocation))
                            .foregroundStyle(.secondary)
                    }
                    TableColumn("Share of income") { line in
                        HStack(spacing: 8) {
                            ProgressView(value: line.percentOfIncome.double, total: 100)
                                .progressViewStyle(.linear)
                            Text(model.format.percent(line.percentOfIncome))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 64, alignment: .trailing)
                        }
                    }
                    TableColumn("Amount") { line in
                        HStack(spacing: 4) {
                            Spacer(minLength: 0)
                            if line.shortfall > 0 {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .help("Short \(model.format.amount(line.shortfall))")
                            }
                            Text(model.format.amount(line.amount))
                                .monospacedDigit()
                        }
                    }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))

                HStack(spacing: 12) {
                    Stat(title: "Distributed", value: model.format.amount(distribution.distributed), detail: model.format.percent(distribution.percentDistributed))
                    Stat(title: "Free cash flow", value: model.format.amount(distribution.unallocated), detail: model.format.percent(distribution.percentUnallocated), tint: .green)
                    if distribution.shortfall > 0 {
                        Stat(title: "Shortfall", value: model.format.amount(distribution.shortfall), detail: "income too low for the plan", tint: .orange)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Enter an income",
                    systemImage: "eurosign.circle",
                    description: Text("Type the income per period on the left, e.g. 2.500 or 2,5k.")
                )
            }
        }
        .padding(20)
    }
}

private struct Stat: View {
    let title: String
    let value: String
    let detail: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - projection

private struct ProjectionPane: View {
    let model: AllocatorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Projection")
                .font(.headline)

            Row(label: "\(model.projectedAccount.name) per period", value: model.format.amount(model.perPeriod), emphasis: true)

            if let periods = model.periods, let distribution = model.distribution {
                Row(
                    label: "After \(model.format.count(periods)) periods",
                    value: model.format.amount(distribution.balance(of: model.projectedAccount, after: periods, starting: model.starting))
                )
            }
            if let target = model.target, let distribution = model.distribution {
                Row(
                    label: "Reach \(model.format.amount(target))",
                    value: span(distribution.periodsToReach(target, in: model.projectedAccount, starting: model.starting))
                )
            }
            if let gross = model.grossTarget, let distribution = model.distribution {
                Row(
                    label: "Earn \(model.format.amount(gross)) gross",
                    value: span(distribution.periodsToReachGross(gross))
                )
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func span(_ periods: Int?) -> String {
        guard let periods else {
            return "never"
        }
        let base = "\(model.format.count(periods)) periods"
        guard periods >= 12 else {
            return base
        }
        let years = periods / 12
        let months = periods % 12
        return base + (months == 0 ? " · \(years) yr" : " · \(years) yr \(months) mo")
    }
}

private struct Row: View {
    let label: String
    let value: String
    var emphasis = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
                .fontWeight(emphasis ? .semibold : .regular)
        }
    }
}

// MARK: - compounding

private struct CompoundingPane: View {
    let model: AllocatorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Compounding")
                .font(.headline)

            if let result = model.compounding {
                Row(label: "Contributed", value: model.format.amount(result.contributed))
                Row(label: "Growth", value: model.format.amount(result.gain))
                Row(label: "Value after \(result.years.count) years", value: model.format.amount(result.value), emphasis: true)

                if !result.years.isEmpty {
                    Chart(result.years) { year in
                        AreaMark(
                            x: .value("Year", year.year),
                            y: .value("Value", year.value.double)
                        )
                        .foregroundStyle(.green.opacity(0.25))
                        LineMark(
                            x: .value("Year", year.year),
                            y: .value("Contributed", year.contributed.double)
                        )
                        .foregroundStyle(.secondary)
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing)
                    }
                    .frame(minHeight: 80)
                }
            } else {
                Text("Enter a return and a number of years.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
}

// MARK: - loan

private struct LoanPane: View {
    let model: AllocatorModel

    var body: some View {
        if let projection = model.loanProjection {
            HStack(alignment: .top, spacing: 0) {
                summary(projection)
                    .frame(width: 300)
                Divider()
                chart(projection)
                    .frame(maxWidth: .infinity)
            }
        } else {
            ContentUnavailableView(
                "No loan",
                systemImage: "arrow.uturn.left.circle",
                description: Text("Enter an amount under Loan to plan taking from an account and paying it back.")
            )
        }
    }

    private func summary(_ projection: LoanProjection) -> some View {
        let loan = projection.loan
        return VStack(alignment: .leading, spacing: 10) {
            Text("\(model.format.amount(loan.principal)) from \(loan.lender.description)")
                .font(.headline)
            Row(label: "Installment", value: model.format.amount(loan.installment), emphasis: true)
            Row(label: "Months", value: "\(loan.months)")
            if loan.annualRate > 0 {
                Row(label: "Interest", value: model.format.amount(loan.totalInterest))
            }
            Row(label: "Lowest free cash flow", value: model.format.amount(projection.lowestFreeCashFlow))
            if projection.fits {
                if let account = projection.account, let restored = projection.restoredAt {
                    Label("\(account.name) back on track after period \(restored)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Every installment fits", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } else {
                Label("Short \(model.format.amount(projection.shortfall)) in total", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                if loan.funding == .freeCashFlow, let months = projection.monthsThatFit {
                    Text("Fits over \(months) months.")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    @ViewBuilder
    private func chart(_ projection: LoanProjection) -> some View {
        let periods = projection.periods
        if projection.account != nil {
            Chart {
                ForEach(periods) { period in
                    if let balance = period.balance {
                        LineMark(
                            x: .value("Period", period.period),
                            y: .value("Balance", balance.double),
                            series: .value("Series", "With loan")
                        )
                        .foregroundStyle(.orange)
                    }
                    if let without = period.balanceWithoutLoan {
                        LineMark(
                            x: .value("Period", period.period),
                            y: .value("Balance", without.double),
                            series: .value("Series", "Without loan")
                        )
                        .foregroundStyle(.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing)
            }
            .padding(20)
        } else {
            Chart(periods.compactMap(\.installment)) { installment in
                BarMark(
                    x: .value("Period", installment.period),
                    y: .value("Outstanding", installment.outstanding.double)
                )
                .foregroundStyle(.orange.opacity(0.6))
            }
            .chartYAxis {
                AxisMarks(position: .trailing)
            }
            .padding(20)
        }
    }
}

extension Decimal {
    var double: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}
