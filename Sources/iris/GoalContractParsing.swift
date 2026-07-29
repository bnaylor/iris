import Foundation

enum GoalContractParsing {
    static func contract(from args: [String: JSONValue]) -> GoalContract? {
        guard let objective = args["objective"]?.stringValue, !objective.isEmpty else { return nil }

        func strings(_ key: String) -> [String] {
            guard case .array(let arr)? = args[key] else { return [] }
            return arr.compactMap { $0.stringValue }
        }

        var criteria: [Criterion] = []
        if case .array(let arr)? = args["criteria"] {
            for item in arr {
                guard case .object(let obj) = item, let text = obj["text"]?.stringValue else { continue }
                let kind = CriterionKind(rawValue: obj["kind"]?.stringValue ?? "") ?? .qualitative
                let check = kind == .executable ? obj["check"]?.stringValue : nil
                criteria.append(Criterion(text: text, kind: kind, check: check))
            }
        }

        return GoalContract(objective: objective,
                            criteria: criteria,
                            outOfScope: strings("out_of_scope"),
                            stopBefore: strings("stop_before"),
                            assumptions: strings("assumptions"),
                            state: .draft)
    }
}
