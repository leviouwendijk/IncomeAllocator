import TestFlows

@main
enum IncomeTestFlowsMain {
    static func main() async {
        await TestFlowCLI.run(
            suite: IncomeTestFlowsSuite.self
        )
    }
}

enum IncomeTestFlowsSuite: TestFlowRegistry {
    static let title = "Income test flows"

    static let flows: [TestFlow] = [
        presetsFlow,
        distributionFlow,
        boundsFlow,
        planValidationFlow,
        projectionFlow,
        compoundingFlow,
        inputFlow,
        loanFlow,
    ]
}
