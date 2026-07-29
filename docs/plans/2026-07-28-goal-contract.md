# Goal Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `/goal <line>` into a structured, lockable **GoalContract** (criteria spectrum + scope + stop-before) that the existing goal loop consults as its decision oracle.

**Architecture:** A pure `GoalContract` model persisted on `Conversation`. `/goal` intercepts into a draft→confirm flow (a `propose_goal_contract` tool the model fills, a panel the user edits and locks). Locking mirrors the objective into the existing `activeGoal` gate (so #16 and subagents are untouched) and injects the contract into the loop's reprompt. `goal_complete` reports per-criterion status (self-reported, marked unverified); `amend_goal_contract` is the only rationale-carrying edit path for a locked contract.

**Tech Stack:** Swift 6 (language mode v6), SwiftUI, swift-testing (`import Testing`).

## Global Constraints

- Criteria spectrum, verbatim: `executable` (carries a runnable `check`), `qualitative` (concrete "done looks like X", no number), `humanJudged` (flagged "you decide", never auto-graded). **No fabricated numbers, no invented `executable` check that can't be run** (honesty invariant).
- The loop gate **stays `activeGoal != nil`**; locking a contract sets `activeGoal = objective`. The ~six `activeGoal` read sites (`iris.swift` loop-detection/cap/reprompt/soft-stop; `SubagentManager` kickoff) are **not** converted. Only new invariant: lock ⇒ `activeGoal` set; a legacy `activeGoal`-only conversation loads as a locked single-`qualitative` contract.
- A locked contract's criteria change through exactly one path, and it carries a non-empty rationale (the change-log). No silent-edit route.
- `goal_complete`'s completion status is a **self-report, rendered as unverified** — never a green "verified" check (slice C does trusted grading, not built here). It must not gate anything yet.
- `goal_complete` is central to #16's soft-stop (`restrictToGoalComplete`, the summary turn, `onSubagentComplete` nil-out, the goal-completion skill-check). Preserve all of it; the new status field is **optional** so the soft-stop summary turn still validates with just `summary`.
- Tests use swift-testing (`import Testing`, `@Suite`, `@Test`, `#expect`), `@testable import iris`, in `Tests/irisTests/`.
- New tools (`propose_goal_contract`, `amend_goal_contract`) are appended to `toolsList` in `iris.swift`; they inherit `intent` automatically via `ToolIntent.augment` (#31) — no action needed.

---

### Task 1: `GoalContract` model

**Files:**
- Create: `Sources/iris/GoalContract.swift`
- Test: `Tests/irisTests/GoalContractTests.swift`

**Interfaces:**
- Produces: `CriterionKind`, `Criterion`, `ContractChange`, `ContractState`, `GoalContract` with `isLocked`, `lock()`, and `applyCriteriaEdit(rationale:_:) -> Bool`, plus `oracleText() -> String`.

- [ ] **Step 1: Write the failing test**

Create `Tests/irisTests/GoalContractTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@Suite("GoalContract")
struct GoalContractTests {
    private func draft() -> GoalContract {
        GoalContract(objective: "Fix the reflow",
                     criteria: [Criterion(text: "swift build green", kind: .executable, check: "swift build"),
                                Criterion(text: "twisty repaints without scroll", kind: .qualitative, check: nil)])
    }

    @Test("round-trips through Codable")
    func codable() throws {
        var c = draft(); c.lock()
        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(GoalContract.self, from: data)
        #expect(back == c)
    }

    @Test("lock flips state and isLocked")
    func locking() {
        var c = draft()
        #expect(!c.isLocked)
        c.lock()
        #expect(c.isLocked && c.state == .locked)
    }

    @Test("a draft edit does not require a rationale and does not log")
    func draftEdit() {
        var c = draft()
        let ok = c.applyCriteriaEdit(rationale: "") { $0.append(Criterion(text: "x", kind: .qualitative, check: nil)) }
        #expect(ok)
        #expect(c.criteria.count == 3)
        #expect(c.changeLog.isEmpty)
    }

    @Test("a locked edit without a rationale is rejected and changes nothing")
    func lockedEditNoRationale() {
        var c = draft(); c.lock()
        let ok = c.applyCriteriaEdit(rationale: "   ") { $0.removeAll() }
        #expect(!ok)
        #expect(c.criteria.count == 2)   // unchanged
        #expect(c.changeLog.isEmpty)
    }

    @Test("a locked edit with a rationale applies and appends a change-log entry")
    func lockedEditWithRationale() {
        var c = draft(); c.lock()
        let ok = c.applyCriteriaEdit(rationale: "criterion was wrong") {
            $0.append(Criterion(text: "new", kind: .qualitative, check: nil))
        }
        #expect(ok)
        #expect(c.criteria.count == 3)
        #expect(c.changeLog.count == 1)
        #expect(c.changeLog.first?.rationale == "criterion was wrong")
    }

    @Test("oracleText includes objective, each criterion, out-of-scope, stop-before")
    func oracle() {
        var c = draft()
        c.outOfScope = ["selection refactor"]; c.stopBefore = ["force-push"]
        let t = c.oracleText()
        #expect(t.contains("Fix the reflow"))
        #expect(t.contains("swift build green"))
        #expect(t.contains("selection refactor"))
        #expect(t.contains("force-push"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter GoalContractTests 2>&1 | tail -15`
Expected: FAIL — `cannot find 'GoalContract' in scope`.

- [ ] **Step 3: Implement the model**

Create `Sources/iris/GoalContract.swift`:

```swift
import Foundation

enum CriterionKind: String, Codable, Sendable, Equatable {
    case executable   // carries a runnable `check`
    case qualitative  // concrete "done looks like X"; no number
    case humanJudged  // "you decide" — never auto-graded
}

struct Criterion: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var text: String
    var kind: CriterionKind
    var check: String?   // command/test for .executable; nil otherwise
}

struct ContractChange: Codable, Equatable, Sendable {
    var date: Date = Date()
    var rationale: String
}

enum ContractState: String, Codable, Sendable, Equatable {
    case draft, locked
}

struct GoalContract: Codable, Equatable, Sendable {
    var id = UUID()
    var objective: String
    var criteria: [Criterion]
    var outOfScope: [String] = []
    var stopBefore: [String] = []
    var assumptions: [String] = []
    var changeLog: [ContractChange] = []
    var state: ContractState = .draft

    var isLocked: Bool { state == .locked }

    mutating func lock() { state = .locked }

    /// The ONLY sanctioned edit to criteria. On a locked contract a non-empty rationale is
    /// mandatory (edit rejected otherwise) and the change is recorded in the change-log.
    /// On a draft, edits are free and unlogged. Returns false iff the edit was rejected.
    @discardableResult
    mutating func applyCriteriaEdit(rationale: String, _ edit: (inout [Criterion]) -> Void) -> Bool {
        let blank = rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isLocked && blank { return false }
        edit(&criteria)
        if isLocked { changeLog.append(ContractChange(rationale: rationale)) }
        return true
    }

    /// The contract as injected into the goal loop's context (the "decision oracle").
    func oracleText() -> String {
        var s = "## Active Goal Contract (the oracle — consult before deciding)\n"
        s += "Objective: \(objective)\n\nDone when ALL of these hold:\n"
        for c in criteria {
            let tag: String
            switch c.kind {
            case .executable: tag = "[executable\(c.check.map { ": \($0)" } ?? "")]"
            case .qualitative: tag = "[qualitative]"
            case .humanJudged: tag = "[human-judged — you do not grade this]"
            }
            s += "  - \(tag) \(c.text)\n"
        }
        if !outOfScope.isEmpty { s += "\nOut of scope (do NOT do): \(outOfScope.joined(separator: "; "))\n" }
        if !stopBefore.isEmpty { s += "Stop and ask before: \(stopBefore.joined(separator: "; "))\n" }
        s += "\nChanging these criteria requires the `amend_goal_contract` tool with a rationale — never silently."
        return s
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter GoalContractTests 2>&1 | tail -15`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/GoalContract.swift Tests/irisTests/GoalContractTests.swift
git commit -m "feat(goal): GoalContract model with criteria spectrum + rationale-gated edits (#13, #9)"
```

---

### Task 2: Persist the contract on `Conversation` + migration

**Files:**
- Modify: `Sources/iris/AppState.swift` (the `Conversation` struct ~L44-90; `clearGoal` ~L576; add `setGoalContract`)
- Test: `Tests/irisTests/GoalContractMigrationTests.swift`

**Interfaces:**
- Consumes: `GoalContract` (Task 1).
- Produces: `Conversation.goalContract: GoalContract?`; `AppState.setGoalContract(for:_:)`; `clearGoal` also clears the contract; legacy-`activeGoal` conversations decode as a locked single-criterion contract.

- [ ] **Step 1: Write the failing test**

Create `Tests/irisTests/GoalContractMigrationTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@Suite("GoalContract persistence & migration")
struct GoalContractMigrationTests {
    @Test("a legacy conversation with only activeGoal decodes as a locked single-criterion contract")
    func legacyUpgrade() throws {
        let legacy = #"{"id":"\#(UUID().uuidString)","title":"t","messages":[],"history":[],"tokenUsage":{"promptTokenCount":0,"candidatesTokenCount":0,"totalTokenCount":0},"activeGoal":"ship the thing","messageCountSinceReflection":0}"#
        let conv = try JSONDecoder().decode(Conversation.self, from: Data(legacy.utf8))
        #expect(conv.activeGoal == "ship the thing")
        #expect(conv.goalContract?.isLocked == true)
        #expect(conv.goalContract?.objective == "ship the thing")
        #expect(conv.goalContract?.criteria.count == 1)
        #expect(conv.goalContract?.criteria.first?.kind == .qualitative)
    }

    @Test("a conversation with no goal decodes with nil contract")
    func noGoal() throws {
        let json = #"{"id":"\#(UUID().uuidString)","title":"t","messages":[],"history":[],"tokenUsage":{"promptTokenCount":0,"candidatesTokenCount":0,"totalTokenCount":0},"messageCountSinceReflection":0}"#
        let conv = try JSONDecoder().decode(Conversation.self, from: Data(json.utf8))
        #expect(conv.goalContract == nil)
        #expect(conv.activeGoal == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter "GoalContract persistence" 2>&1 | tail -15`
Expected: FAIL — `Conversation` has no member `goalContract`.

- [ ] **Step 3: Add `goalContract` to `Conversation` with migration**

In `Sources/iris/AppState.swift`, `struct Conversation`:
- Add stored property next to `activeGoal`: `var goalContract: GoalContract?`.
- Add `goalContract` to the memberwise `init` signature (defaulted `goalContract: GoalContract? = nil`) and body (`self.goalContract = goalContract`).
- Add `case goalContract` to `CodingKeys`.
- In `init(from:)`, after decoding `activeGoal`, add the migration:

```swift
        goalContract = try container.decodeIfPresent(GoalContract.self, forKey: .goalContract)
        // Migration: a legacy conversation that had a goal (activeGoal) but no contract is
        // upgraded to a locked single-qualitative-criterion contract so in-flight goals survive.
        if goalContract == nil, let legacy = activeGoal {
            var c = GoalContract(objective: legacy,
                                 criteria: [Criterion(text: legacy, kind: .qualitative, check: nil)])
            c.lock()
            goalContract = c
        }
```

- [ ] **Step 4: Wire `setGoalContract` and extend `clearGoal`**

In `AppState`, add:

```swift
    /// Locks a drafted contract onto the conversation and mirrors its objective into `activeGoal`
    /// so the existing loop gate (activeGoal != nil) and #16's machinery keep working unchanged.
    func setGoalContract(for conversationId: UUID, _ contract: GoalContract) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        var locked = contract
        locked.lock()
        conversations[idx].goalContract = locked
        conversations[idx].activeGoal = locked.objective
        conversations[idx].goalIterationCount = 0
        saveConversations()
    }
```

And in `clearGoal(for:)`, alongside `conversations[idx].activeGoal = nil`, add `conversations[idx].goalContract = nil`.

- [ ] **Step 5: Run the tests + build**

Run: `swift test --filter "GoalContract persistence" 2>&1 | tail -8` (expect PASS, 2 tests) and `swift build 2>&1 | tail -3` (expect `Build complete!`).

- [ ] **Step 6: Commit**

```bash
git add Sources/iris/AppState.swift Tests/irisTests/GoalContractMigrationTests.swift
git commit -m "feat(goal): persist GoalContract on Conversation; migrate legacy activeGoal (#13, #9)"
```

---

### Task 3: `propose_goal_contract` tool + parsing

**Files:**
- Modify: `Sources/iris/iris.swift` (append the tool to `toolsList` near the other `toolsList.append`; handle it in `executeFunctionCall`)
- Create: `Sources/iris/GoalContractParsing.swift` (pure `JSONValue`→`GoalContract` builder)
- Test: `Tests/irisTests/GoalContractParsingTests.swift`

**Interfaces:**
- Consumes: `GoalContract`, `Criterion` (Task 1); `JSONValue`, `FunctionDeclaration`, `Schema` (`Models.swift`).
- Produces: `GoalContractParsing.contract(from args: [String: JSONValue]) -> GoalContract?` (returns a **draft**).

- [ ] **Step 1: Write the failing test**

Create `Tests/irisTests/GoalContractParsingTests.swift`:

```swift
import Testing
@testable import iris

@Suite("GoalContract parsing")
struct GoalContractParsingTests {
    @Test("builds a draft contract from a tool-call args payload")
    func parses() {
        let args: [String: JSONValue] = [
            "objective": .string("Fix the reflow"),
            "criteria": .array([
                .object(["text": .string("swift build green"), "kind": .string("executable"), "check": .string("swift build")]),
                .object(["text": .string("repaints without scroll"), "kind": .string("qualitative")])
            ]),
            "out_of_scope": .array([.string("selection refactor")]),
            "stop_before": .array([.string("force-push")]),
            "assumptions": .array([.string("keep the List container")])
        ]
        let c = GoalContractParsing.contract(from: args)
        #expect(c?.objective == "Fix the reflow")
        #expect(c?.state == .draft)
        #expect(c?.criteria.count == 2)
        #expect(c?.criteria.first?.kind == .executable)
        #expect(c?.criteria.first?.check == "swift build")
        #expect(c?.criteria.last?.check == nil)
        #expect(c?.outOfScope == ["selection refactor"])
        #expect(c?.stopBefore == ["force-push"])
    }

    @Test("an unknown kind falls back to qualitative")
    func unknownKind() {
        let args: [String: JSONValue] = [
            "objective": .string("x"),
            "criteria": .array([.object(["text": .string("c"), "kind": .string("bogus")])])
        ]
        #expect(GoalContractParsing.contract(from: args)?.criteria.first?.kind == .qualitative)
    }

    @Test("missing objective returns nil")
    func noObjective() {
        #expect(GoalContractParsing.contract(from: ["criteria": .array([])]) == nil)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter "GoalContract parsing" 2>&1 | tail -12`
Expected: FAIL — `cannot find 'GoalContractParsing'`.

- [ ] **Step 3: Implement the parser**

Create `Sources/iris/GoalContractParsing.swift`:

```swift
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
```

(Note: `CriterionKind(rawValue:)` maps `"executable"/"qualitative"/"humanJudged"`. A tool that sends `"human"` or `"human_judged"` would fall back to qualitative; the tool description in Step 4 uses the exact raw values.)

- [ ] **Step 4: Append the tool declaration**

In `Sources/iris/iris.swift`, alongside the other `toolsList.append(FunctionDeclaration(...))` calls, add:

```swift
        toolsList.append(FunctionDeclaration(
            name: "propose_goal_contract",
            description: "Draft a structured contract for a goal the user is starting. Produce concrete criteria for 'done'. Honesty rules: never invent an `executable` check you cannot actually run; prefer a `qualitative` criterion over a fabricated number; flag taste/direction as `humanJudged`. This proposes a DRAFT for the user to edit and approve — it does not start the loop.",
            parameters: Schema(type: "OBJECT", properties: [
                "objective": Schema(type: "STRING", description: "One-line restatement of the goal."),
                "criteria": Schema(type: "ARRAY", description: "Definition of done. Each item: {text, kind: executable|qualitative|humanJudged, check?}. `check` is a runnable command/test, only for executable.", items: Schema(type: "OBJECT")),
                "out_of_scope": Schema(type: "ARRAY", description: "Explicit non-goals.", items: Schema(type: "STRING")),
                "stop_before": Schema(type: "ARRAY", description: "Irreversible / authorization boundaries to stop and ask before (e.g. force-push, merge, delete, spend).", items: Schema(type: "STRING")),
                "assumptions": Schema(type: "ARRAY", description: "Anything you inferred that the user should confirm.", items: Schema(type: "STRING"))
            ], required: ["objective", "criteria"])
        ))
```

(If `Schema` lacks an `items` parameter, check `Models.swift`; the existing schema uses `type`/`properties`/`required`/`description`. If `items` is absent, drop it and describe the array shape in the `description` only — the model still fills it. Verify against `Models.swift` before writing.)

- [ ] **Step 5: Handle the tool call**

In `executeFunctionCall` (`iris.swift`, the `else if functionCall.name == ...` chain), add a branch that parses the draft, stores it on the conversation (draft state, does NOT set `activeGoal`), and returns a confirmation the UI/panel will pick up:

```swift
        } else if functionCall.name == "propose_goal_contract" {
            if let draft = GoalContractParsing.contract(from: functionCall.args) {
                await MainActor.run { localState?.setDraftContract(for: conversationId, draft) }
                result = "Draft goal contract proposed for user review. Await approval before starting the goal loop."
            } else {
                result = "Could not parse the proposed goal contract (missing objective?)."
            }
```

And add `setDraftContract` to `AppState` (sets `conversations[idx].goalContract = draft` in `.draft` state, saves; does NOT touch `activeGoal`).

- [ ] **Step 6: Run tests + build**

Run: `swift test --filter "GoalContract parsing" 2>&1 | tail -6` (PASS, 3) and `swift build 2>&1 | tail -3`.

- [ ] **Step 7: Commit**

```bash
git add Sources/iris/GoalContractParsing.swift Sources/iris/iris.swift Sources/iris/AppState.swift Tests/irisTests/GoalContractParsingTests.swift
git commit -m "feat(goal): propose_goal_contract tool + draft parsing (#13, #9)"
```

---

### Task 4: `/goal` draft→confirm flow + contract panel (GUI-verified)

**Files:**
- Modify: `Sources/iris/AppState.swift` (`sendMessage` `/goal` branch, ~L351)
- Modify: `Sources/iris/ChatView.swift` (render the draft panel above the composer)
- Create: `Sources/iris/GoalContractPanel.swift` (the SwiftUI panel)

**Interfaces:**
- Consumes: `setDraftContract` (Task 3), `setGoalContract` (Task 2), `Conversation.goalContract`.

- [ ] **Step 1: Redirect `/goal` into the draft flow**

In `AppState.sendMessage`, replace the `/goal` branch body (currently sets `activeGoal` and sends "GOAL MODE ACTIVATED…") so it instead kicks a drafting turn and does **not** start the loop:

```swift
        if trimmed.hasPrefix("/goal") {
            let goalText = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            if goalText.isEmpty {
                appendMessage(role: .system, content: "Please specify a goal, e.g., `/goal Build a snake game in Python`", to: convId)
                return
            }
            appendMessage(role: .user, content: "/goal \(goalText)", to: convId)
            let draftPrompt = "The user wants to start a goal: \"\(goalText)\". Call `propose_goal_contract` to draft a contract (concrete criteria for done, out-of-scope, stop-before). Ask 1–3 clarifying questions in your text ONLY if the goal is genuinely ambiguous or a boundary matters. Do NOT start any work yet — this is the drafting step."
            runThinkingTask(conversationId: convId) { [self] in
                await engine.processInput(draftPrompt, source: "System", conversationId: convId)
            }
            return
        }
```

(The model calls `propose_goal_contract` → Task 3's handler stores the draft → the panel, Step 2, renders it. Any clarifying questions arrive as normal assistant text.)

- [ ] **Step 2: Build the panel** (`GoalContractPanel.swift`) rendering `conversation.goalContract` when `state == .draft`: objective, each criterion with an editable text field + a kind picker (`executable`/`qualitative`/`humanJudged`) + a `check` field shown only for `executable`, editable out-of-scope / stop-before / assumptions lists, an **Approve & Lock** button and a **Discard** button. Approve calls `state.setGoalContract(for:convId, editedContract)` then sends the existing "GOAL MODE ACTIVATED…" kickoff so the loop starts (see Step 3). Discard clears the draft (`state.clearGoal`). Follow the styling of `EmojiAutoCompleteView`/the existing composer panels.

- [ ] **Step 3: Start the loop on approval.** On **Approve & Lock**: after `setGoalContract`, send the goal-mode kickoff so the existing loop begins with the contract already locked:

```swift
        // in the Approve action, after setGoalContract:
        state.sendGoalKickoff(for: convId)   // helper posts the "GOAL MODE ACTIVATED..." system turn
```

Add `sendGoalKickoff` to `AppState`: it composes the same `GOAL MODE ACTIVATED. Your goal is: <objective>.…` message used today (now sourced from `goalContract.objective`) and runs the thinking task — identical to today's behavior, just deferred until after lock.

- [ ] **Step 4: Render it in `ChatView`.** Above the composer (near where the slash/emoji popups render), add `if let conv = active, conv.goalContract?.state == .draft { GoalContractPanel(...) }`.

- [ ] **Step 5: Build**

Run: `swift build 2>&1 | tail -4` (expect `Build complete!`).

- [ ] **Step 6: GUI verification (ask the user to `swift run`)**

Ask the human partner to verify: `/goal <something>` shows a draft-contract panel (not an immediate goal run); criteria are editable with kind pickers; **Approve & Lock** starts the goal loop; **Discard** cancels cleanly; a plain chat message is unaffected.

- [ ] **Step 7: Commit**

```bash
git add Sources/iris/AppState.swift Sources/iris/ChatView.swift Sources/iris/GoalContractPanel.swift
git commit -m "feat(goal): /goal draft-and-confirm flow + contract panel (#13, #9)"
```

---

### Task 5: Inject the locked contract into the loop (the oracle)

**Files:**
- Modify: `Sources/iris/iris.swift` (the auto-reprompt text ~L637; and where the goal-mode kickoff is built if applicable)
- Test: `Tests/irisTests/GoalContractTests.swift` already covers `oracleText()`; add an injection helper test if a pure helper is introduced.

**Interfaces:**
- Consumes: `GoalContract.oracleText()` (Task 1); `Conversation.goalContract`.

- [ ] **Step 1: Prepend the oracle to the auto-reprompt when a contract is locked**

In `iris.swift`, in the auto-reprompt task (currently `await self.processInput("Continue working on your goal. What is your next step? If finished, call goal_complete.", …)`), read the contract and prepend its oracle text:

```swift
                    let oracle = await MainActor.run { () -> String in
                        localState?.conversations.first(where: { $0.id == conversationId })?.goalContract?.oracleText() ?? ""
                    }
                    let reprompt = oracle.isEmpty
                        ? "Continue working on your goal. What is your next step? If finished, call goal_complete."
                        : "\(oracle)\n\nContinue working toward the objective above. What is your next step? If every criterion is satisfied, call goal_complete."
                    await self.processInput(reprompt, source: "System", conversationId: conversationId)
```

- [ ] **Step 2: Build + confirm the loop still runs**

Run: `swift build 2>&1 | tail -3`. (The `oracleText()` content is already unit-tested in Task 1; this step is the wiring.)

- [ ] **Step 3: Commit**

```bash
git add Sources/iris/iris.swift
git commit -m "feat(goal): inject the locked contract as the loop's decision oracle (#13, #9)"
```

---

### Task 6: `goal_complete` per-criterion status (preserve #16)

**Files:**
- Modify: `Sources/iris/iris.swift` (`goal_complete` declaration ~L338; handler ~L727)
- Modify: `Sources/iris/AppState.swift` (store the reported status on the conversation for the panel)
- Test: `Tests/irisTests/GoalCompleteStatusTests.swift`

**Interfaces:**
- Consumes: `GoalContract` (Task 1).
- Produces: `goal_complete` schema carries an **optional** `criteria_status` array; the handler records it and preserves clearGoal/callback/skill-check.

- [ ] **Step 1: Add the optional field to the declaration**

In the `goal_complete` `FunctionDeclaration`, add to `properties` (keep `required: ["summary"]` — `criteria_status` is optional so the #16 soft-stop summary turn still validates):

```swift
                    "summary": Schema(type: "STRING", description: "A detailed summary of what was accomplished and final conclusion."),
                    "criteria_status": Schema(type: "ARRAY", description: "Per-criterion self-report against the goal contract. Each item: {criterion, status: met|not_met|cannot_verify, evidence}. This is a self-report shown to the user as UNVERIFIED — do not overstate.", items: Schema(type: "OBJECT"))
```

- [ ] **Step 2: Record status in the handler without changing #16 behavior**

In the `functionCall.name == "goal_complete"` branch, before `clearGoal`, capture the optional status and hand it to AppState; keep every existing line (`clearGoal`, `onSubagentComplete` fire + nil, `pushToUI` summary, the goal-completion skill-check, `result = …`):

```swift
        } else if functionCall.name == "goal_complete", let summary = functionCall.args["summary"]?.stringValue {
            let statusReport = functionCall.args["criteria_status"]  // optional; passed through for the panel
            await MainActor.run {
                localState?.recordCompletionSelfReport(for: conversationId, statusJSON: statusReport)
                localState?.clearGoal(for: conversationId)
                localState?.onSubagentComplete[conversationId]?(summary)
                localState?.onSubagentComplete[conversationId] = nil
            }
            // ... unchanged: pushToUI(summary), main-agent skill-check reflection, result = ...
```

Add `recordCompletionSelfReport(for:statusJSON:)` to `AppState`: it stores a rendered/structured self-report (e.g. `conversations[idx].lastGoalCompletionReport`) so the panel (Task 8) can show it. **`clearGoal` nils the contract**, so capture the report before clearing — the order above (record, then clear) matters.

- [ ] **Step 3: Behavioral test — `criteria_status` is optional, #16 path intact**

`goal_complete` is assembled inside `IrisEngine` (not exposed), so test the *behavior*: a `goal_complete` with only `summary` (no `criteria_status`) must still clear the goal. Reuse the injected-mock pattern from `LoopStopEnforcementTests` (its `ScriptedLLMClient` is in the test target). Create `Tests/irisTests/GoalCompleteStatusTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@MainActor
@Suite("goal_complete status")
struct GoalCompleteStatusTests {
    private func response(functionCall: FunctionCall?) -> GeminiResponse {
        let part = Part(text: functionCall == nil ? "No new skill needed." : nil,
                        functionCall: functionCall, functionResponse: nil,
                        thought_signature: nil, thoughtSignature: nil)
        return GeminiResponse(candidates: [Candidate(content: Content(role: "model", parts: [part]))], usageMetadata: nil)
    }

    @Test("goal_complete with only summary still clears the goal (criteria_status optional; #16 intact)")
    func summaryOnlyCompletes() async {
        let app = AppState()
        let id = UUID()
        app.createNewConversation(id: id)
        var contract = GoalContract(objective: "obj", criteria: [Criterion(text: "c", kind: .qualitative, check: nil)])
        contract.lock()
        app.setGoalContract(for: id, contract)
        #expect(app.conversations.first { $0.id == id }?.activeGoal == "obj")

        let done = FunctionCall(name: "goal_complete", args: ["summary": .string("done, all good")],
                               id: nil, thought_signature: nil, thoughtSignature: nil)
        // 1st response: goal_complete (summary only). 2nd: text, for the main-agent skill-check turn.
        let mock = ScriptedLLMClient(responses: [response(functionCall: done), response(functionCall: nil)])
        let engine = IrisEngine(state: app, tier: .medium, client: mock)
        await engine.processInput("proceed", source: "System", conversationId: id)

        #expect(app.conversations.first { $0.id == id }?.activeGoal == nil)     // goal cleared (the #16 path)
        #expect(app.conversations.first { $0.id == id }?.goalContract == nil)
        let msgs = app.conversations.first { $0.id == id }?.messages ?? []
        #expect(msgs.contains { $0.content.contains("done, all good") })       // summary surfaced
    }
}
```

(Note the goal_complete handler fires a nested skill-check `processInput` for the main agent — hence the second scripted text response so that turn ends cleanly.)

- [ ] **Step 4: Run + build**

Run: `swift test --filter "goal_complete status" 2>&1 | tail -6` and `swift build 2>&1 | tail -3`. Also re-run `swift test --filter LoopStopEnforcement 2>&1 | tail -3` to confirm #16 is intact.

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/iris.swift Sources/iris/AppState.swift Tests/irisTests/GoalCompleteStatusTests.swift
git commit -m "feat(goal): goal_complete reports per-criterion self-report; #16 preserved (#13, #9)"
```

---

### Task 7: `amend_goal_contract` tool

**Files:**
- Modify: `Sources/iris/iris.swift` (append the tool; handle it)
- Modify: `Sources/iris/AppState.swift` (apply the amend to the locked contract)
- Test: `Tests/irisTests/GoalContractAmendTests.swift`

**Interfaces:**
- Consumes: `GoalContract.applyCriteriaEdit(rationale:_:)` (Task 1).
- Produces: `AppState.amendGoalContract(for:action:criterionText:kind:check:rationale:) -> Bool`.

- [ ] **Step 1: Write the failing test**

Create `Tests/irisTests/GoalContractAmendTests.swift`:

```swift
import Testing
@testable import iris

@MainActor
@Suite("GoalContract amend")
struct GoalContractAmendTests {
    private func lockedConv(_ app: AppState) -> UUID {
        let id = UUID()
        app.createNewConversation(id: id)
        var c = GoalContract(objective: "obj", criteria: [Criterion(text: "old", kind: .qualitative, check: nil)])
        c.lock()
        app.setGoalContract(for: id, c)
        return id
    }

    @Test("adding a criterion with a rationale succeeds and logs the change")
    func addWithRationale() {
        let app = AppState(); let id = lockedConv(app)
        let ok = app.amendGoalContract(for: id, action: "add", criterionText: "new", kind: "qualitative", check: nil, rationale: "found a missing case")
        #expect(ok)
        let c = app.conversations.first { $0.id == id }?.goalContract
        #expect(c?.criteria.contains { $0.text == "new" } == true)
        #expect(c?.changeLog.count == 1)
    }

    @Test("amending without a rationale is rejected and changes nothing")
    func rejectNoRationale() {
        let app = AppState(); let id = lockedConv(app)
        let ok = app.amendGoalContract(for: id, action: "add", criterionText: "new", kind: "qualitative", check: nil, rationale: "  ")
        #expect(!ok)
        #expect(app.conversations.first { $0.id == id }?.goalContract?.criteria.count == 1)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter "GoalContract amend" 2>&1 | tail -10`
Expected: FAIL — no `amendGoalContract`.

- [ ] **Step 3: Implement `amendGoalContract` on `AppState`**

```swift
    /// The only sanctioned edit path for a LOCKED contract. Returns false if rejected
    /// (blank rationale) or no contract. `action` is "add" | "remove" | "update".
    @discardableResult
    func amendGoalContract(for conversationId: UUID, action: String, criterionText: String,
                           kind: String, check: String?, rationale: String) -> Bool {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }),
              var contract = conversations[idx].goalContract else { return false }
        let ck = CriterionKind(rawValue: kind) ?? .qualitative
        let ok = contract.applyCriteriaEdit(rationale: rationale) { criteria in
            switch action {
            case "remove": criteria.removeAll { $0.text == criterionText }
            case "update":
                if let i = criteria.firstIndex(where: { $0.text == criterionText }) {
                    criteria[i].kind = ck; criteria[i].check = ck == .executable ? check : nil
                }
            default: // "add"
                criteria.append(Criterion(text: criterionText, kind: ck, check: ck == .executable ? check : nil))
            }
        }
        if ok {
            conversations[idx].goalContract = contract
            saveConversations()
        }
        return ok
    }
```

- [ ] **Step 4: Append + handle the tool** in `iris.swift`:

```swift
        toolsList.append(FunctionDeclaration(
            name: "amend_goal_contract",
            description: "Change the LOCKED goal contract's criteria when the work reveals they were wrong. A `rationale` is mandatory — criteria never change silently. The change is logged and shown to the user.",
            parameters: Schema(type: "OBJECT", properties: [
                "action": Schema(type: "STRING", description: "add | remove | update"),
                "criterion": Schema(type: "STRING", description: "The criterion text to add, or the existing text to remove/update."),
                "kind": Schema(type: "STRING", description: "executable | qualitative | humanJudged (for add/update)."),
                "check": Schema(type: "STRING", description: "Runnable command/test, only for executable."),
                "rationale": Schema(type: "STRING", description: "One line: why the criteria must change.")
            ], required: ["action", "criterion", "rationale"])
        ))
```

Handler branch in `executeFunctionCall`:

```swift
        } else if functionCall.name == "amend_goal_contract" {
            let action = functionCall.args["action"]?.stringValue ?? "add"
            let text = functionCall.args["criterion"]?.stringValue ?? ""
            let kind = functionCall.args["kind"]?.stringValue ?? "qualitative"
            let check = functionCall.args["check"]?.stringValue
            let rationale = functionCall.args["rationale"]?.stringValue ?? ""
            let ok = await MainActor.run {
                localState?.amendGoalContract(for: conversationId, action: action, criterionText: text, kind: kind, check: check, rationale: rationale) ?? false
            }
            result = ok ? "Goal contract amended (\(action): \(text)). Logged with rationale."
                        : "Amend rejected — a non-empty rationale is required to change locked criteria."
```

- [ ] **Step 5: Run + build**

Run: `swift test --filter "GoalContract amend" 2>&1 | tail -6` (PASS, 2) and `swift build 2>&1 | tail -3`.

- [ ] **Step 6: Commit**

```bash
git add Sources/iris/iris.swift Sources/iris/AppState.swift Tests/irisTests/GoalContractAmendTests.swift
git commit -m "feat(goal): amend_goal_contract tool as the only rationale-gated edit path (#13, #9)"
```

---

### Task 8: Locked-contract chip, change-log, and UNVERIFIED completion labels (GUI-verified)

**Files:**
- Modify: `Sources/iris/GoalContractPanel.swift` (add the locked-run view)
- Modify: `Sources/iris/ChatView.swift` (show the chip during a locked run)

- [ ] **Step 1: Locked-run view.** When `goalContract?.state == .locked`, render a compact chip: the objective, a small criteria list, and any `changeLog` entries (each with its rationale). This is the "oracle you're being held to."

- [ ] **Step 2: Mark the completion self-report UNVERIFIED.** When `lastGoalCompletionReport` is present, render each per-criterion status with an explicit **"self-reported · unverified"** label and a neutral icon — never a green verified check. Add a one-line caption: "Independent verification arrives with the drift evaluator (not yet built)."

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -3`.

- [ ] **Step 4: GUI verification (user `swift run`)**

Verify: during a locked goal run a chip shows the contract + any amendments; on `goal_complete` the per-criterion status renders as *self-reported/unverified* (no green checks); an `amend_goal_contract` call shows a new change-log line.

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/GoalContractPanel.swift Sources/iris/ChatView.swift
git commit -m "feat(goal): locked-contract chip + change-log + unverified completion labels (#13, #9)"
```

---

## Notes for the implementer

- `swift test` builds the whole package (MLX/ONNX/llama) and can be slow cold; use `--filter <Suite>` while iterating.
- **Do not convert the `activeGoal` gate sites.** The loop gate stays `activeGoal != nil`; locking a contract sets `activeGoal` (Task 2). This is deliberate — subagents (`SubagentManager`) and all of #16 depend on `activeGoal`.
- **Verify `Schema` supports `items:`** in `Models.swift` before Tasks 3/6/7. If it doesn't, drop the `items:` argument and describe the array element shape in the `description` string only — the model still fills the array; only the JSON-schema hint is lost.
- The two new tools inherit an `intent` field automatically from `ToolIntent.augment` (#31); don't add one by hand.
- Preserve every existing line in the `goal_complete` handler (Task 6) — `clearGoal`, the `onSubagentComplete` fire+nil, the summary `pushToUI`, and the main-agent goal-completion skill-check. Record the self-report *before* `clearGoal` (which nils the contract).
- **Stop-before scope in slice A.** `stopBefore` is *surfaced in the oracle* (Task 5 — the model is told to stop and ask before those actions), and the genuinely dangerous operations (`run_command`, `write_file`) already require approval through the existing Vibecop/approval queue. A does **not** add action-string matching that maps an arbitrary tool call to a `stopBefore` phrase and forces approval — that finer enforcement is deferred (it belongs with the done-gates, slice D). This matches the spec's softened §6 framing ("a boundary denylist reusing existing approval machinery"), and is called out here so the lighter enforcement isn't mistaken for an omission.
