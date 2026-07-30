import Foundation

enum GoalEvaluationParsing {
    /// Reconciles the grader's submitted verdicts against the FULL criteria list (spec §4.3):
    /// use a supplied verdict if present; else `humanPending` for a `humanJudged` criterion; else
    /// `cannotVerify`. So every criterion always carries a verdict and humanJudged never collapses
    /// to cannot_verify. `method` derives from the criterion kind.
    static func verdicts(from args: [String: JSONValue], criteria: [Criterion]) -> [CriterionVerdict] {
        // Index submitted verdicts by criterion_id.
        var submitted: [UUID: (value: CriterionVerdictValue, evidence: String)] = [:]
        if case .array(let items)? = args["evaluations"] {
            for item in items {
                guard case .object(let obj) = item,
                      let idString = obj["criterion_id"]?.stringValue,
                      let id = UUID(uuidString: idString) else { continue }
                let value = CriterionVerdictValue(rawValue: obj["verdict"]?.stringValue ?? "") ?? .cannotVerify
                // A grader must never mark a criterion humanPending; that is system-assigned.
                let safeValue: CriterionVerdictValue = (value == .humanPending) ? .cannotVerify : value
                submitted[id] = (safeValue, obj["evidence"]?.stringValue ?? "")
            }
        }

        return criteria.map { c in
            let method: VerdictMethod
            switch c.kind {
            case .executable: method = .check
            case .qualitative: method = .judge
            case .humanJudged: method = .human
            }
            if let s = submitted[c.id] {
                return CriterionVerdict(criterionId: c.id, criterionText: c.text, kind: c.kind,
                                        verdict: s.value, evidence: s.evidence, method: method)
            }
            let fallback: CriterionVerdictValue = (c.kind == .humanJudged) ? .humanPending : .cannotVerify
            return CriterionVerdict(criterionId: c.id, criterionText: c.text, kind: c.kind,
                                    verdict: fallback, evidence: "", method: method)
        }
    }
}
