import SwiftUI

/// Displays the draft `GoalContract` proposed by the model, lets the user edit it,
/// and then either approves (locking the contract and starting the goal loop) or discards it.
struct GoalContractPanel: View {
    var state: AppState
    let conversation: Conversation

    // Local editable copies — edits stay here until the user approves.
    @State private var objective: String
    @State private var criteria: [Criterion]
    @State private var outOfScope: [String]
    @State private var stopBefore: [String]
    @State private var assumptions: [String]

    init(state: AppState, conversation: Conversation) {
        self.state = state
        self.conversation = conversation
        let contract = conversation.goalContract ?? GoalContract(
            objective: "",
            criteria: []
        )
        // Seeding @State from the conversation's draft contract is safe here because:
        // (a) GoalContractPanel only appears while goalContract.state == .draft, and
        // (b) the state machine never transitions a contract back to .draft once it leaves
        //     that phase — so this init runs exactly once per panel lifetime and there is
        //     no risk of a re-render clobbering in-progress edits.
        _objective = State(initialValue: contract.objective)
        _criteria = State(initialValue: contract.criteria)
        _outOfScope = State(initialValue: contract.outOfScope)
        _stopBefore = State(initialValue: contract.stopBefore)
        _assumptions = State(initialValue: contract.assumptions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    objectiveSection
                    criteriaSection
                    if !outOfScope.isEmpty || !stopBefore.isEmpty || !assumptions.isEmpty {
                        listsSection
                    }
                }
                .padding(12)
            }
            .frame(maxHeight: 320)
            Divider()
            actionBar
        }
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(Color.irisIndigo)
                .font(.caption)
            Text("GOAL CONTRACT DRAFT")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
            Spacer()
            Text("Review and edit before approving")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var objectiveSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Objective", systemImage: "target")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            TextField("Objective", text: $objective, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .lineLimit(2...4)
                .padding(6)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var criteriaSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Done when…", systemImage: "list.bullet.clipboard")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach($criteria) { $criterion in
                CriterionRow(criterion: $criterion)
            }
        }
    }

    private var listsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !outOfScope.isEmpty {
                StringListSection(
                    label: "Out of scope",
                    systemImage: "nosign",
                    items: $outOfScope
                )
            }
            if !stopBefore.isEmpty {
                StringListSection(
                    label: "Stop and ask before",
                    systemImage: "exclamationmark.triangle",
                    items: $stopBefore
                )
            }
            if !assumptions.isEmpty {
                StringListSection(
                    label: "Assumptions",
                    systemImage: "questionmark.circle",
                    items: $assumptions
                )
            }
        }
    }

    private var actionBar: some View {
        HStack {
            Button("Discard", role: .destructive) {
                state.clearGoal(for: conversation.id)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Spacer()

            Button("Approve & Lock") {
                approveAndLock()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .font(.subheadline.bold())
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color.irisIndigo)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func approveAndLock() {
        // Normalize: a criterion's `check` is only valid for `.executable` kind.
        // If the user switched the picker away from `.executable` after typing a command,
        // the check string is still in local state — strip it here so the locked contract
        // never carries a check value on a non-executable criterion.
        let normalizedCriteria = criteria.map { criterion in
            Criterion(
                id: criterion.id,
                text: criterion.text,
                kind: criterion.kind,
                check: criterion.kind == .executable ? criterion.check : nil
            )
        }
        let edited = GoalContract(
            objective: objective,
            criteria: normalizedCriteria,
            outOfScope: outOfScope,
            stopBefore: stopBefore,
            assumptions: assumptions
        )
        state.setGoalContract(for: conversation.id, edited)
        state.sendGoalKickoff(for: conversation.id)
    }
}

// MARK: - Subviews

private struct CriterionRow: View {
    @Binding var criterion: Criterion

    /// Local mirror of `criterion.check` so we can use a plain `$checkText` binding
    /// instead of a manual `Binding(get:set:)`.
    @State private var checkText: String

    init(criterion: Binding<Criterion>) {
        _criterion = criterion
        _checkText = State(initialValue: criterion.wrappedValue.check ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Picker("Kind", selection: $criterion.kind) {
                    Text("Executable").tag(CriterionKind.executable)
                    Text("Qualitative").tag(CriterionKind.qualitative)
                    Text("Human-judged").tag(CriterionKind.humanJudged)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.caption)
                .frame(width: 130)

                TextField("Criterion description", text: $criterion.text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...3)
                    .padding(6)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            if criterion.kind == .executable {
                TextField("Check command (e.g. swift test)", text: $checkText)
                    .textFieldStyle(.plain)
                    .font(.system(.caption, design: .monospaced))
                    .padding(6)
                    .background(Color.irisIndigo.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.leading, 138)
                    .onChange(of: checkText) { _, new in
                        criterion.check = new.isEmpty ? nil : new
                    }
            }
        }
    }
}

/// Pairs a stable UUID with an index so `ForEach` can use a fixed identity while
/// `StringListSection` still binds edits directly into the underlying `[String]` array.
private struct IndexedString: Identifiable {
    let id: UUID
    let index: Int
}

private struct StringListSection: View {
    let label: String
    let systemImage: String
    @Binding var items: [String]

    /// Stable row identifiers generated once per section lifetime.
    /// Each entry maps a UUID to a positional index in `items`.
    /// Using UUID-based identity prevents SwiftUI from recycling rows incorrectly
    /// when the collection is mutated (add/delete in future iterations).
    @State private var rowIDs: [IndexedString]

    init(label: String, systemImage: String, items: Binding<[String]>) {
        self.label = label
        self.systemImage = systemImage
        _items = items
        _rowIDs = State(initialValue: items.wrappedValue.indices.map {
            IndexedString(id: UUID(), index: $0)
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: systemImage)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(rowIDs) { row in
                TextField(label, text: $items[row.index], axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1...2)
                    .padding(6)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}
