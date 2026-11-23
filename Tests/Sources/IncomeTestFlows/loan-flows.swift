import Foundation
import Income
import TestFlows

extension IncomeTestFlowsSuite {
    static var loanFlow: TestFlow {
        TestFlow("loan", tags: ["income", "loan"]) {
            Step("an interest-free loan repays in equal parts") {
                let loan = try Loan(.init(principal: 3000, months: 6))
                try Expect.equal(loan.installment, 500, "installment")
                let schedule = loan.schedule()
                try Expect.equal(schedule.count, 6, "six installments")
                try Expect.equal(schedule.last?.outstanding, 0, "fully repaid")
                try Expect.equal(loan.totalInterest, 0, "no interest")
                try Expect.equal(loan.lender, .account(.savings), "borrows from savings by default")
            }

            Step("uneven splits put the rounding in the last installment") {
                let loan = try Loan(.init(principal: 1000, months: 3))
                let schedule = loan.schedule()
                try Expect.equal(schedule.map(\.payment), [Decimal(string: "333.34")!, Decimal(string: "333.34")!, Decimal(string: "333.32")!], "payments")
                try Expect.equal(schedule.reduce(0) { $0 + $1.payment }, 1000, "pays exactly the principal")
            }

            Step("interest follows the annuity formula") {
                let loan = try Loan(.init(lender: .external("Bank"), principal: 10_000, months: 12, annualRate: 12))
                try Expect.equal(loan.installment, Decimal(string: "888.49")!, "annuity at 1% a month")
                try Expect.equal(loan.schedule().last?.outstanding, 0, "annuity repaid")
                try Expect.true(loan.totalInterest > 600 && loan.totalInterest < 670, "interest about 661.85, got \(loan.totalInterest)")
            }

            Step("invalid loans are rejected") {
                try Expect.throwsError("loan.zero") { _ = try Loan(.init(principal: 0, months: 6)) }
                try Expect.throwsError("loan.months") { _ = try Loan(.init(principal: 100, months: 0)) }
                try Expect.throwsError("loan.rate") { _ = try Loan(.init(principal: 100, months: 6, annualRate: 150)) }
                try Expect.throwsError("loan.external-name") { _ = try Loan(.init(lender: .external(" "), principal: 100, months: 6)) }
            }

            Step("repaying from free cash flow leaves allocations alone and restores the balance") {
                let loan = try Loan(.init(principal: 1000, months: 10))
                let projection = LoanProjection(loan: loan, plan: .defaults, income: 2500, startingBalance: 5000)
                try Expect.true(projection.fits, "100 a month fits in about 200 free cash flow")
                try Expect.equal(projection.periods[0].distribution, AllocationPlan.defaults.distribute(2500), "allocations unchanged")
                try Expect.equal(projection.restoredAt, 10, "savings back on track at the last installment")
                try Expect.equal(projection.periods[9].balance, projection.periods[9].balanceWithoutLoan, "balance fully restored")
            }

            Step("too short a term reports a shortfall and the months that fit") {
                let loan = try Loan(.init(principal: 3000, months: 3))
                let projection = LoanProjection(loan: loan, plan: .defaults, income: 2500)
                try Expect.true(!projection.fits, "1000 a month does not fit")
                try Expect.true(projection.restoredAt == nil, "never restored while short")
                guard let months = projection.monthsThatFit else {
                    try Expect.true(false, "a term that fits exists")
                    return
                }
                let fitting = LoanProjection(loan: try Loan(.init(principal: 3000, months: months)), plan: .defaults, income: 2500)
                try Expect.true(fitting.fits, "the suggested term fits")
            }

            Step("repaying before allocations shrinks the income the plan sees") {
                let loan = try Loan(.init(principal: 1200, months: 12, funding: .beforeAllocations))
                let projection = LoanProjection(loan: loan, plan: .defaults, income: 2500)
                try Expect.equal(projection.periods[0].distribution.income, 2400, "plan runs on income minus installment")
                try Expect.true(projection.fits, "fits")
            }

            Step("a later first period leaves earlier periods untouched") {
                let loan = try Loan(.init(principal: 600, months: 3, firstPeriod: 4))
                let projection = LoanProjection(loan: loan, plan: .defaults, income: 2500)
                try Expect.equal(projection.periods.count, 6, "runs through the last installment")
                try Expect.equal(projection.periods[0].paid, 0, "nothing paid before the first period")
                try Expect.equal(projection.periods[3].paid, 200, "first installment in period 4")
            }
        }
    }
}
