import Foundation

final class GoalEvaluator: @unchecked Sendable {
    static let shared = GoalEvaluator()
    private init() {}

    /// Runs a fresh-context grader against `contract` and writes a `GoalEvaluation` onto
    /// `originatingConversationId`. Non-blocking for the caller: dispatch this in a detached Task.
    /// `client` is injectable so tests can drive the grader with a `ScriptedLLMClient` instead of
    /// hitting the network.
    func evaluate(contract: GoalContract, workspace: String?, originatingConversationId originId: UUID,
                  app: AppState, client: any LLMClientProtocol = LLMClient()) async {

        let evalId = UUID()
        await MainActor.run {
            app.createNewConversation(id: evalId, isSubagent: true)
            app.updateConversationTitle(id: evalId, title: "Evaluator")
            if let ws = workspace { app.setWorkspace(for: evalId, path: ws) }
        }

        // Fresh engine, evaluator principal. It never sees the working transcript.
        let checks = contract.criteria.compactMap { $0.kind == .executable ? $0.check : nil }
        let engine = IrisEngine(state: app, tier: .hard, principal: .evaluator, roleLabel: "evaluator", client: client, evaluatorChecks: checks)
        let prompt = Self.systemPrompt(for: contract)
        await engine.setSystemPrompt(text: prompt)

        // Resolve on submit_evaluation: reconcile against the contract's criteria and write graded.
        await MainActor.run {
            app.onEvaluationComplete[evalId] = { payload in
                let verdicts: [CriterionVerdict]
                if case .object(let obj)? = payload {
                    verdicts = GoalEvaluationParsing.verdicts(from: obj, criteria: contract.criteria)
                } else {
                    verdicts = GoalEvaluationParsing.verdicts(from: [:], criteria: contract.criteria)
                }
                let eval = GoalEvaluation(status: .graded, criteria: verdicts, startedAt: Date(), completedAt: Date())
                Task { @MainActor in
                    app.recordEvaluation(for: originId, eval)
                    app.onEvaluationComplete[evalId] = nil
                    app.deleteConversation(evalId)
                }
            }
        }

        // Kick the grader loop; its activeGoal makes it auto-reprompt until it calls submit_evaluation.
        await MainActor.run { app.setGoal(for: evalId, goal: "Evaluate the completed work against the contract above, then call submit_evaluation.") }
        await engine.processInput("Begin your evaluation. Inspect the workspace, run the checks, then call submit_evaluation.",
                                  source: "System", conversationId: evalId)

        // Safety net: if the loop ended without submit_evaluation, mark the evaluation failed.
        // Gate on the callback slot: submit_evaluation nils it synchronously on the MainActor at
        // submit time, so a non-nil slot here means the grader never submitted.
        await MainActor.run {
            guard app.onEvaluationComplete[evalId] != nil else { return }
            // Grader did not submit — record a failed evaluation.
            let originalStartedAt = app.conversations.first { $0.id == originId }?.lastGoalEvaluation?.startedAt ?? Date()
            let failed = GoalEvaluation(
                status: .failed,
                criteria: contract.criteria.map {
                    CriterionVerdict(criterionId: $0.id, criterionText: $0.text, kind: $0.kind,
                                     verdict: $0.kind == .humanJudged ? .humanPending : .cannotVerify,
                                     evidence: "Evaluator ended without submitting a verdict.",
                                     method: $0.kind == .executable ? .check : ($0.kind == .qualitative ? .judge : .human))
                },
                startedAt: originalStartedAt, completedAt: Date())
            app.recordEvaluation(for: originId, failed)
            app.onEvaluationComplete[evalId] = nil
            app.deleteConversation(evalId)
        }
    }

    private static func systemPrompt(for contract: GoalContract) -> String {
        let base: String
        if let url = Bundle.module.url(forResource: "EVALUATOR", withExtension: "md"),
           let contents = try? String(contentsOf: url, encoding: .utf8),
           !contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            base = contents
        } else {
            base = fallbackPrompt
        }
        var s = base + "\n\n## The locked contract you are grading\nObjective: \(contract.objective)\n\nCriteria (grade each by its id):\n"
        for c in contract.criteria {
            let checkNote = (c.kind == .executable) ? " — run this check: `\(c.check ?? "")`" : ""
            let kindNote = (c.kind == .humanJudged) ? " — HUMAN-JUDGED: do NOT grade this; omit it." : ""
            s += "  - id \(c.id.uuidString) [\(c.kind.rawValue)] \(c.text)\(checkNote)\(kindNote)\n"
        }
        if !contract.outOfScope.isEmpty { s += "\nOut of scope (do not reward or penalize): \(contract.outOfScope.joined(separator: "; "))\n" }
        return s
    }

    private static let fallbackPrompt = "You are an impartial evaluator. You did not do the work and have no stake in it passing. Independently determine, for each contract criterion, whether the finished work satisfies it, using only read_file and run_command to gather your own evidence. Return cannot_verify when you genuinely cannot determine a criterion; never fabricate a pass. Then call submit_evaluation with one entry per criterion you graded (omit human-judged criteria)."
}
