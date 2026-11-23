import Foundation

/// Monthly compounding of a principal plus a fixed monthly contribution.
public struct Compounding: Sendable, Hashable, Codable {
    /// Whether the monthly contribution lands before or after that month's growth.
    public enum Timing: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
        case beginning
        case end

        public var id: String { rawValue }
    }

    public struct Year: Sendable, Hashable, Identifiable {
        public let year: Int
        public let contributed: Decimal
        public let value: Decimal

        public var id: Int { year }
        public var gain: Decimal { value - contributed }
    }

    public struct Result: Sendable, Hashable {
        public let years: [Year]
        public let principal: Decimal

        public var contributed: Decimal { years.last?.contributed ?? principal }
        public var value: Decimal { years.last?.value ?? principal }
        public var gain: Decimal { value - contributed }
    }

    public var principal: Decimal
    /// Yearly rate in percent (`7` is 7 %), applied monthly as `rate / 12`.
    public var annualRate: Decimal
    public var monthlyContribution: Decimal
    public var years: Int
    public var timing: Timing

    public init(
        principal: Decimal = 0,
        annualRate: Decimal,
        monthlyContribution: Decimal = 0,
        years: Int,
        timing: Timing = .end
    ) {
        self.principal = principal
        self.annualRate = annualRate
        self.monthlyContribution = monthlyContribution
        self.years = years
        self.timing = timing
    }

    public func result() -> Result {
        let growth = 1 + annualRate / 100 / 12
        var value = principal
        var contributed = principal
        var schedule: [Year] = []
        schedule.reserveCapacity(max(years, 0))

        for year in stride(from: 1, through: max(years, 0), by: 1) {
            for _ in 0..<12 {
                switch timing {
                case .beginning:
                    value = (value + monthlyContribution) * growth
                case .end:
                    value = value * growth + monthlyContribution
                }
                contributed += monthlyContribution
            }
            schedule.append(
                Year(
                    year: year,
                    contributed: contributed,
                    value: value.rounded(scale: 10, mode: .plain)
                )
            )
            value = value.rounded(scale: 10, mode: .plain)
        }

        return Result(
            years: schedule,
            principal: principal
        )
    }
}
