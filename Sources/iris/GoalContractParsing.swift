import Foundation

enum GoalContractParsing {
    static func contract(from args: [String: JSONValue]) -> GoalContract? {
        guard let objective = args["objective"]?.stringValue, !objective.isEmpty else { return nil }

        func strings(_ key: String) -> [String] {
            guard case .array(let arr)? = args[key] else { return [] }
            return arr.compactMap { $0.stringValue }
        }

        var criteria: [Criterion] = []
        var order: [String] = []                 // milestone titles in first-appearance order
        var groups: [String: [UUID]] = [:]
        if case .array(let arr)? = args["criteria"] {
            for item in arr {
                guard case .object(let obj) = item, let text = obj["text"]?.stringValue else { continue }
                let kind = CriterionKind(rawValue: obj["kind"]?.stringValue ?? "") ?? .qualitative
                let check = kind == .executable ? obj["check"]?.stringValue : nil
                let criterion = Criterion(text: text, kind: kind, check: check)
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
