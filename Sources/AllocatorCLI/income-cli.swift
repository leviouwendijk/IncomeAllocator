import Arguments
import Foundation
import Income
import Terminal

@main
struct IncomeCLIMain {
    static func main() async {
        await IncomeCommand.main(
            errorHandler: { error in
                print("error: ".ansi(.red, .bold) + error.localizedDescription)
                return 1
            }
        )
    }
}

enum IncomeCommand: ArgumentCommand {
    static let name = "income"

    static let children: [ArgumentCommandType] = [
        AllocateCommand.self,
        PresetsCommand.self,
        ProjectCommand.self,
        CompoundCommand.self,
    ]
}

enum IncomeCLIError: Error, LocalizedError {
    case missingIncome
    case unknownPreset(String)
    case unknownAccount(Account, plan: AllocationPlan)

    var errorDescription: String? {
        switch self {
        case .missingIncome:
            return "Pass an income, e.g. `income allocate 2500`"
        case .unknownPreset(let name):
            let names = AllocationPlan.presets.map(\.name).joined(separator: ", ")
            return "Unknown preset '\(name)'. Presets: \(names)"
        case .unknownAccount(let account, let plan):
            let names = plan.accounts.map(\.name).joined(separator: ", ")
            return "Preset '\(plan.name)' has no account '\(account)'. Accounts: \(names)"
        }
    }
}

// MARK: - argument values

struct AmountValue: ArgumentValue, ExpressibleByNilLiteral, Hashable {
    let value: Decimal?

    init(_ value: Decimal?) {
        self.value = value
    }

    init(nilLiteral: ()) {
        self.value = nil
    }

    static var parser: AnyArgumentValueParser<AmountValue> {
        .init { AmountValue(try IncomeInput.amount($0)) }
    }

    static var valueName: String { "amount" }

    static func raw(_ value: AmountValue) -> String {
        value.value.map { "\($0)" } ?? ""
    }

    func required() throws -> Decimal {
        guard let value else {
            throw IncomeCLIError.missingIncome
        }
        return value
    }
}

struct PercentValue: ArgumentValue, Hashable {
    let value: Decimal

    static var parser: AnyArgumentValueParser<PercentValue> {
        .init { PercentValue(value: try IncomeInput.percent($0)) }
    }

    static var valueName: String { "percent" }

    static func raw(_ value: PercentValue) -> String { "\(value.value)" }
}

struct CountValue: ArgumentValue, Hashable {
    let value: Int

    static var parser: AnyArgumentValueParser<CountValue> {
        .init { CountValue(value: try IncomeInput.count($0)) }
    }

    static var valueName: String { "count" }

    static func raw(_ value: CountValue) -> String { "\(value.value)" }
}

struct PlanValue: ArgumentValue, Hashable {
    let plan: AllocationPlan

    static var parser: AnyArgumentValueParser<PlanValue> {
        .init { text in
            guard let plan = AllocationPlan.named(text) else {
                throw IncomeCLIError.unknownPreset(text)
            }
            return PlanValue(plan: plan)
        }
    }

    static var valueName: String { "preset" }

    static func raw(_ value: PlanValue) -> String { value.plan.name }
}

struct AccountValue: ArgumentValue, Hashable {
    let account: Account

    static var parser: AnyArgumentValueParser<AccountValue> {
        .init { AccountValue(account: Account($0)) }
    }

    static var valueName: String { "account" }

    static func raw(_ value: AccountValue) -> String { value.account.name }

    /// The plan's own spelling of the account (`income-tax` → `Income Tax`).
    func resolved(in plan: AllocationPlan) throws -> Account {
        guard let allocation = plan.allocation(for: account) else {
            throw IncomeCLIError.unknownAccount(account, plan: plan)
        }
        return allocation.account
    }
}

struct TimingValue: ArgumentValue, Hashable {
    let timing: Compounding.Timing

    static var parser: AnyArgumentValueParser<TimingValue> {
        .init { text in
            guard let timing = Compounding.Timing(rawValue: text.lowercased()) else {
                throw ArgumentValueParseError.invalid_value(value: text, type: valueName)
            }
            return TimingValue(timing: timing)
        }
    }

    static var valueName: String { "beginning|end" }

    static func raw(_ value: TimingValue) -> String { value.timing.rawValue }
}
