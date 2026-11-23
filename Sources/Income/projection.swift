import Foundation

/// Linear projections: the same amount every period, no growth (see `Compounding` for growth).
public enum Projection {
    /// Periods of `perPeriod` needed to reach `target` from `starting`; `nil` if never.
    public static func periods(
        toReach target: Decimal,
        perPeriod: Decimal,
        starting: Decimal = 0
    ) -> Int? {
        let missing = target - starting
        guard missing > 0 else {
            return 0
        }
        guard perPeriod > 0 else {
            return nil
        }
        let periods = (missing / perPeriod).rounded(scale: 0, mode: .up)
        guard periods <= Decimal(Int.max) else {
            return nil
        }
        return NSDecimalNumber(decimal: periods).intValue
    }

    public static func balance(
        perPeriod: Decimal,
        periods: Int,
        starting: Decimal = 0
    ) -> Decimal {
        starting + perPeriod * Decimal(max(periods, 0))
    }
}

public extension Distribution {
    /// Periods of this whole income needed to earn `target` gross.
    func periodsToReachGross(
        _ target: Decimal
    ) -> Int? {
        Projection.periods(toReach: target, perPeriod: income)
    }

    /// Periods until `account` holds `target`; `nil` if the plan gives it nothing.
    func periodsToReach(
        _ target: Decimal,
        in account: Account,
        starting: Decimal = 0
    ) -> Int? {
        Projection.periods(toReach: target, perPeriod: amount(for: account), starting: starting)
    }

    func balance(
        of account: Account,
        after periods: Int,
        starting: Decimal = 0
    ) -> Decimal {
        Projection.balance(perPeriod: amount(for: account), periods: periods, starting: starting)
    }
}

extension Decimal {
    func rounded(
        scale: Int,
        mode: NSDecimalNumber.RoundingMode
    ) -> Decimal {
        var source = self
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, mode)
        return result
    }
}
