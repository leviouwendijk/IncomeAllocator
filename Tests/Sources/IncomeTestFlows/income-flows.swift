import Foundation
import Income
import TestFlows

private func decimal(_ text: String) -> Decimal {
    Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))!
}

private func allocation(
    _ account: Account,
    _ share: Share,
    floor: Decimal? = nil,
    cap: Decimal? = nil
) throws -> Allocation {
    try Allocation(.init(account: account, share: share, floor: floor, cap: cap))
}

private func plan(_ allocations: [Allocation]) throws -> AllocationPlan {
    try AllocationPlan(.init(name: "test", allocations: allocations))
}

extension IncomeTestFlowsSuite {
    static var presetsFlow: TestFlow {
        TestFlow("presets", tags: ["income", "presets"]) {
            Step("every preset passes plan and allocation validation") {
                for preset in AllocationPlan.presets {
                    let checked = try AllocationPlan(preset.raw)
                    try Expect.equal(checked, preset, "preset \(preset.name) is valid")
                    for allocation in preset.allocations {
                        _ = try Allocation(allocation.raw)
                    }
                }
            }

            Step("presets are found by loose name") {
                try Expect.equal(AllocationPlan.named("Adaptation-A"), .adaptationA, "named.loose")
                try Expect.true(AllocationPlan.named("nope") == nil, "named.unknown")
            }

            Step("plans round-trip through JSON and decoding re-validates") {
                let data = try JSONEncoder().encode(AllocationPlan.defaults)
                let decoded = try JSONDecoder().decode(AllocationPlan.self, from: data)
                try Expect.equal(decoded, .defaults, "codable.round-trip")

                let invalid = Data(#"{"account":"Savings","share":{"ofIncome":{"percent":120}}}"#.utf8)
                try Expect.throwsError("codable.invalid-percent") {
                    _ = try JSONDecoder().decode(Allocation.self, from: invalid)
                }
            }
        }
    }

    static var distributionFlow: TestFlow {
        TestFlow("distribution", tags: ["income", "distribution"]) {
            Step("defaults split income and remainder shares in order") {
                let distribution = AllocationPlan.defaults.distribute(2500)
                try Expect.equal(distribution.amount(for: .savings), 375, "savings 15% of income")
                try Expect.equal(distribution.amount(for: .incomeTax), decimal("887.5"), "tax 35.5% of income")
                try Expect.equal(distribution.amount(for: .charges), decimal("34.03125"), "charges 2.75% of remainder 1237.5")
                try Expect.equal(
                    distribution.distributed + distribution.unallocated,
                    2500,
                    "distributed + unallocated = income"
                )
                try Expect.equal(distribution.shortfall, 0, "percentages never fall short")
            }

            Step("fixed amounts take the amount, not income minus the amount") {
                let rent = try plan([allocation(.housing, .fixed(900))])
                let distribution = rent.distribute(2500)
                try Expect.equal(distribution.amount(for: .housing), 900, "fixed.amount")
                try Expect.equal(distribution.unallocated, 1600, "fixed.unallocated")
            }

            Step("allocations never exceed the income; the rest is shortfall") {
                let fixed = try plan([
                    allocation(.housing, .fixed(1000)),
                    allocation(.living, .fixed(800)),
                ])
                let distribution = fixed.distribute(1500)
                try Expect.equal(distribution.amount(for: .living), 500, "shortfall.clamped")
                try Expect.equal(distribution.shortfall, 300, "shortfall.total")
                try Expect.equal(distribution.unallocated, 0, "shortfall.unallocated")
            }

            Step("a remainder allocation takes what is left") {
                let rest = try plan([
                    allocation(.savings, .ofIncome(percent: 10)),
                    allocation(.living, .remainder),
                ])
                let distribution = rest.distribute(2000)
                try Expect.equal(distribution.amount(for: .living), 1800, "remainder.amount")
                try Expect.equal(distribution.unallocated, 0, "remainder.unallocated")
            }

            Step("missing accounts read as zero instead of crashing") {
                let distribution = AllocationPlan.adaptationA.distribute(2500)
                try Expect.equal(distribution.amount(for: .charges), 0, "missing.amount")
                try Expect.equal(distribution.balance(of: .charges, after: 12), 0, "missing.balance")
                try Expect.true(distribution.periodsToReach(1000, in: .charges) == nil, "missing.periods")
            }

            Step("zero income distributes nothing") {
                let distribution = AllocationPlan.defaults.distribute(0)
                try Expect.equal(distribution.distributed, 0, "zero.distributed")
                try Expect.equal(distribution.percentDistributed, 0, "zero.percent")
            }
        }
    }

    static var boundsFlow: TestFlow {
        TestFlow("bounds", tags: ["income", "floor", "cap"]) {
            Step("floors and caps bound a percentage") {
                let bounded = try plan([
                    allocation(.savings, .ofIncome(percent: 10), floor: 300),
                    allocation(.purchases, .ofIncome(percent: 10), cap: 100),
                ])
                let distribution = bounded.distribute(2000)
                try Expect.equal(distribution.amount(for: .savings), 300, "floor.applies")
                try Expect.equal(distribution.amount(for: .purchases), 100, "cap.applies")
            }

            Step("minimum income covers fixed costs and floors") {
                let rent = try plan([
                    allocation(.savings, .ofIncome(percent: 20)),
                    allocation(.housing, .fixed(1000)),
                ])
                try Expect.equal(rent.minimumIncome(), 1250, "minimum.fixed")
                try Expect.equal(AllocationPlan.defaults.minimumIncome(), 0, "minimum.percentages")

                let impossible = try plan([allocation(.housing, .fixed(10))])
                try Expect.true(impossible.minimumIncome(limit: 5) == nil, "minimum.beyond-limit")
            }
        }
    }

    static var planValidationFlow: TestFlow {
        TestFlow("plan-validation", tags: ["income", "invariant"]) {
            Step("allocations reject impossible rules") {
                try Expect.throwsError("allocation.percent") {
                    _ = try allocation(.savings, .ofIncome(percent: 120))
                }
                try Expect.throwsError("allocation.negative-fixed") {
                    _ = try allocation(.savings, .fixed(-1))
                }
                try Expect.throwsError("allocation.floor-above-cap") {
                    _ = try allocation(.savings, .ofIncome(percent: 10), floor: 200, cap: 100)
                }
            }

            Step("plans reject duplicates, misplaced remainders and blank names") {
                try Expect.throwsError("plan.duplicate") {
                    _ = try plan([
                        allocation("Savings", .ofIncome(percent: 10)),
                        allocation("savings", .ofIncome(percent: 10)),
                    ])
                }
                try Expect.throwsError("plan.remainder-last") {
                    _ = try plan([
                        allocation(.living, .remainder),
                        allocation(.savings, .ofIncome(percent: 10)),
                    ])
                }
                try Expect.throwsError("plan.name") {
                    _ = try AllocationPlan(.init(name: "  ", allocations: []))
                }
            }
        }
    }

    static var projectionFlow: TestFlow {
        TestFlow("projection", tags: ["income", "projection"]) {
            Step("periods round up and handle edges") {
                try Expect.equal(Projection.periods(toReach: 1000, perPeriod: 300), 4, "periods.round-up")
                try Expect.equal(Projection.periods(toReach: 900, perPeriod: 300), 3, "periods.exact")
                try Expect.equal(Projection.periods(toReach: 100, perPeriod: 0, starting: 200), 0, "periods.already")
                try Expect.true(Projection.periods(toReach: 100, perPeriod: 0) == nil, "periods.never")
            }

            Step("balances and gross targets follow the distribution") {
                let distribution = AllocationPlan.defaults.distribute(2500)
                try Expect.equal(distribution.balance(of: .savings, after: 12), 4500, "balance.linear")
                try Expect.equal(distribution.balance(of: .savings, after: 2, starting: 100), 850, "balance.starting")
                try Expect.equal(distribution.periodsToReachGross(1_000_000), 400, "gross.periods")
            }
        }
    }

    static var compoundingFlow: TestFlow {
        TestFlow("compounding", tags: ["income", "compounding"]) {
            Step("monthly compounding of a principal") {
                let result = Compounding(principal: 1000, annualRate: 12, years: 1).result()
                let expected = decimal("1126.825030132")
                let difference = abs(NSDecimalNumber(decimal: result.value - expected).doubleValue)
                try Expect.true(difference < 0.000001, "principal grows 1% a month, got \(result.value)")
            }

            Step("contributions and timing") {
                let end = Compounding(annualRate: 10, monthlyContribution: 100, years: 2, timing: .end).result()
                let beginning = Compounding(annualRate: 10, monthlyContribution: 100, years: 2, timing: .beginning).result()
                try Expect.equal(end.contributed, 2400, "contributed")
                try Expect.equal(end.years.count, 2, "one row per year")
                try Expect.true(beginning.value > end.value, "early contributions grow a month longer")
            }

            Step("zero years is the principal, not a trap") {
                let result = Compounding(principal: 500, annualRate: 10, years: 0).result()
                try Expect.equal(result.value, 500, "zero-years.value")
                try Expect.equal(result.gain, 0, "zero-years.gain")
            }
        }
    }

    static var inputFlow: TestFlow {
        TestFlow("input", tags: ["income", "input", "parsers"]) {
            Step("amounts, percentages and counts read as typed") {
                try Expect.equal(try IncomeInput.amount("2_500"), 2500, "amount.underscore")
                try Expect.equal(try IncomeInput.amount("€ 1.250,50"), decimal("1250.5"), "amount.euro")
                try Expect.equal(try IncomeInput.amount("2,5k"), 2500, "amount.magnitude")
                try Expect.equal(try IncomeInput.percent("35,5%"), decimal("35.5"), "percent.comma")
                try Expect.equal(try IncomeInput.count("12"), 12, "count.plain")
                try Expect.true(try IncomeInput.optional(" ", IncomeInput.amount) == nil, "optional.blank")
            }

            Step("invalid input is rejected") {
                try Expect.throwsError("amount.negative") { _ = try IncomeInput.amount("-5") }
                try Expect.throwsError("percent.range") { _ = try IncomeInput.percent("120") }
                try Expect.throwsError("count.fraction") { _ = try IncomeInput.count("1,5") }
                try Expect.throwsError("amount.text") { _ = try IncomeInput.amount("lots") }
            }
        }
    }
}
