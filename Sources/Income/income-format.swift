import Foundation

/// Display formatting shared by the Mac app and the CLI.
public struct IncomeFormat: Sendable, Hashable {
    public var currencyCode: String
    public var locale: Locale

    public init(
        currencyCode: String = "EUR",
        locale: Locale = .current
    ) {
        self.currencyCode = currencyCode
        self.locale = locale
    }

    public static let standard = IncomeFormat()

    public func amount(
        _ value: Decimal
    ) -> String {
        value.formatted(
            .currency(code: currencyCode)
                .precision(.fractionLength(2))
                .locale(locale)
        )
    }

    /// `percent` is in percent units: `15` → `15 %`.
    public func percent(
        _ percent: Decimal
    ) -> String {
        (percent / 100).formatted(
            .percent
                .precision(.fractionLength(0...2))
                .locale(locale)
        )
    }

    public func number(
        _ value: Decimal
    ) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(0...2))
                .locale(locale)
        )
    }

    public func count(
        _ value: Int
    ) -> String {
        value.formatted(.number.locale(locale))
    }

    public func share(
        _ allocation: Allocation
    ) -> String {
        var text: String
        switch allocation.share {
        case .ofIncome(let value):
            text = "\(percent(value)) of income"
        case .ofRemainder(let value):
            text = "\(percent(value)) of remainder"
        case .fixed(let value):
            text = "\(amount(value)) fixed"
        case .remainder:
            text = "remainder"
        }
        if let floor = allocation.floor {
            text += ", at least \(amount(floor))"
        }
        if let cap = allocation.cap {
            text += ", at most \(amount(cap))"
        }
        return text
    }

    /// Plain aligned text, for the clipboard.
    public func report(
        _ distribution: Distribution
    ) -> String {
        let rows: [(String, String, String)] = distribution.lines.map {
            ($0.account.name, share($0.allocation), amount($0.amount))
        }
        let nameWidth = max(rows.map(\.0.count).max() ?? 0, 18)
        let shareWidth = rows.map(\.1.count).max() ?? 0
        let amountWidth = max(rows.map(\.2.count).max() ?? 0, amount(distribution.income).count)

        func pad(_ text: String, _ width: Int, right: Bool = false) -> String {
            let padding = String(repeating: " ", count: max(width - text.count, 0))
            return right ? padding + text : text + padding
        }

        var lines: [String] = []
        lines.append("\(distribution.plan.name): \(amount(distribution.income))")
        lines.append("")
        for (name, rule, value) in rows {
            lines.append("\(pad(name, nameWidth))  \(pad(rule, shareWidth))  \(pad(value, amountWidth, right: true))")
        }
        let totalWidth = nameWidth + shareWidth + amountWidth + 4
        lines.append(String(repeating: "-", count: totalWidth))
        let totals: [(String, Decimal)] = [
            ("Distributed", distribution.distributed),
            ("Free cash flow", distribution.unallocated),
        ] + (distribution.shortfall > 0 ? [("Shortfall", distribution.shortfall)] : [])
        for (label, value) in totals {
            lines.append("\(pad(label, nameWidth + shareWidth + 2))  \(pad(amount(value), amountWidth, right: true))")
        }
        return lines.joined(separator: "\n")
    }
}
