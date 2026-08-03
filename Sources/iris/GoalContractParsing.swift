import Foundation

enum GoalContractParsing {
    static func contract(from args: [String: JSONValue]) -> GoalContract? {
        guard let objective = args["objective"]?.stringValue, !objective.isEmpty else { return nil }

        func strings(_ key: String) -> [String] {
            guard case .array(let arr)? = args[key] else { return [] }
            var result: [String] = []
            for item in arr {
                if case .string(let s) = item {
                    result.append(s)
                } else {
                    print("[iris] GoalContract parse: non-string element in '\(key)' array ignored")
                }
            }
            return result
        }

        var criteria: [Criterion] = []
        var order: [String] = []                 // milestone titles in first-appearance order
        var groups: [String: [UUID]] = [:]
        if case .array(let arr)? = args["criteria"] {
            for item in arr {
                guard case .object(let obj) = item, let text = obj["text"]?.stringValue else { continue }
                let rawKind = obj["kind"]?.stringValue ?? ""
                let kind = CriterionKind(rawValue: rawKind)
                if kind == nil, !rawKind.isEmpty {
                    print("[iris] GoalContract parse: unknown criterion kind '\(rawKind)', falling back to qualitative")
                }
                let resolvedKind = kind ?? .qualitative
                let check = resolvedKind == .executable ? obj["check"]?.stringValue : nil
                let criterion = Criterion(text: text, kind: resolvedKind, check: check)
                criteria.append(criterion)
                if let label = obj["milestone"]?.stringValue,
                   !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if groups[label] == nil { order.append(label) }
                    groups[label, default: []].append(criterion.id)
                }
            }
        }
        let milestones = order.map { Milestone(title: $0, criterionIds: groups[$0] ?? []) }

        return GoalContract(objective: objective,
                            criteria: criteria,
                            outOfScope: strings("out_of_scope"),
                            stopBefore: strings("stop_before"),
                            assumptions: strings("assumptions"),
                            milestones: milestones,
                            state: .draft)
    }
}
