import Clipboard
import Foundation
import Income
import Observation

/// Everything the window shows, derived from the text the user typed.
///
/// Inputs are kept as text so a half-typed number never fights the field; every
/// output is computed from them on read, so there is nothing to keep in sync.
@Observable
@MainActor
final class AllocatorModel {
    var incomeText = "2.500"
    var planName = AllocationPlan.defaults.name

    var account: Account = .savings
    var targetText = "50.000"
    var startingText = ""
    var grossTargetText = "1.000.000"
    var periodsText = "12"

    var principalText = "0"
    var rateText = "10"
    var monthlyText = ""
    var yearsText = "10"
    var timing: Compounding.Timing = .end

    let format = IncomeFormat.standard

    // MARK: allocation

    var plan: AllocationPlan {
        AllocationPlan.named(planName) ?? .defaults
    }

    var income: Decimal? {
        try? IncomeInput.amount(incomeText)
    }

    var distribution: Distribution? {
        income.map(plan.distribute)
    }

    var minimumIncome: Decimal? {
        plan.minimumIncome().flatMap { $0 > 0 ? $0 : nil }
    }

    // MARK: projection

    /// The chosen account, or the plan's first when the plan lacks it.
    var projectedAccount: Account {
        plan.allocation(for: account)?.account ?? plan.accounts.first ?? account
    }

    var perPeriod: Decimal {
        distribution?.amount(for: projectedAccount) ?? 0
    }

    var starting: Decimal {
        (try? IncomeInput.optional(startingText, IncomeInput.amount)) ?? 0
    }

    var periods: Int? {
        try? IncomeInput.count(periodsText)
    }

    var target: Decimal? {
        (try? IncomeInput.optional(targetText, IncomeInput.amount)) ?? nil
    }

    var grossTarget: Decimal? {
        (try? IncomeInput.optional(grossTargetText, IncomeInput.amount)) ?? nil
    }

    // MARK: compounding

    /// Typed monthly amount, or what the projected account gets.
    var monthly: Decimal {
        ((try? IncomeInput.optional(monthlyText, IncomeInput.amount)) ?? nil) ?? perPeriod
    }

    var compounding: Compounding.Result? {
        guard let rate = try? IncomeInput.percent(rateText),
              let years = try? IncomeInput.count(yearsText)
        else {
            return nil
        }
        return Compounding(
            principal: (try? IncomeInput.optional(principalText, IncomeInput.amount)) ?? 0,
            annualRate: rate,
            monthlyContribution: monthly,
            years: min(years, 100),
            timing: timing
        ).result()
    }

    // MARK: actions

    /// The parse error for `text`, or `nil` when it is blank or valid.
    func problem<Value>(
        _ text: String,
        _ parse: (String) throws -> Value
    ) -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        do {
            _ = try parse(text)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func copyReport() {
        guard let distribution else {
            return
        }
        Clipboard.system.write(format.report(distribution))
    }
}
