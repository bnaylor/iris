# Goal Drift Evaluator (slice C) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a fresh-context, hands-on evaluator that independently grades a completed goal's work against its locked `GoalContract` and shows the trusted per-criterion verdict beside the agent's self-report (drift-revealing), without blocking completion.

**Architecture:** A new `Principal.evaluator` runs a fresh `IrisEngine` (isolated like a subagent) with a mutation-free toolset — `read_file`, `run_command`, `submit_evaluation` — grading against a contract snapshot captured at `goal_complete`. It runs the `executable` `check`s itself, LLM-judges `qualitative`, surfaces `humanJudged`, and writes a `GoalEvaluation` back to the originating conversation via a completion callback. `run_command` for the evaluator is routed through a stricter Vibecop caller-role layer. The completion chip becomes a two-column self-report-vs-grader drift view.

**Tech Stack:** Swift 6 (language mode v6), SwiftUI, swift-testing (`import Testing`) + a little XCTest where the repo already uses it.

## Global Constraints

- **C is non-blocking.** A failing grade does NOT stop `goal_complete` or re-prompt the agent. The gate/retry/`n/a — reason` escape is slice D. (spec §2)
- **Adversarial isolation.** The grader runs in a fresh conversation + fresh `IrisEngine(principal: .evaluator)` and never receives the working transcript. (spec §3.3)
- **Mutation-free by construction.** The `.evaluator` assembled toolset is exactly `{read_file, run_command, submit_evaluation}` — every write/goal/network tool absent, not merely sandboxed. (spec §4.1)
- **Honesty invariant.** The grader must be able to answer `cannot_verify` and must never fabricate a pass. `humanJudged` criteria are never auto-graded. (spec §2, §4.2, §4.4)
- **Reconciliation rule (verbatim):** for each contract criterion, if the grader supplied a verdict use it; else if kind is `humanJudged` record `humanPending`; else record `cannot_verify`. A `humanJudged` criterion never collapses to `cannot_verify`. (spec §4.3)
- **executable mapping:** run the `check`; exit `0` → `met`, nonzero → `not_met`, couldn't run → `cannot_verify`. (spec §4.4)
- **UI honesty styling:** the self-report column stays neutral (never a green check); the grader column earns real color (green `met`, red `not_met`, neutral `cannot_verify`, "your call" `humanPending`); disagreements flagged. (spec §7)
- Tests use swift-testing (`import Testing`, `@Suite`, `@Test`, `#expect`), `@testable import iris`, in `Tests/irisTests/`.
- Tool ARRAY schemas MUST set `items` (Gemini rejects otherwise); `Schema` supports `items:` since slice A.
- New tools inherit an `intent` field automatically from `ToolIntent.augment`; never hand-add one.

### Types from slice A (already in the codebase — do not redefine)

```swift
enum CriterionKind: String, Codable, Sendable, Equatable { case executable, qualitative, humanJudged }
struct Criterion: Codable, Identifiable, Equatable, Sendable { var id = UUID(); var text: String; var kind: CriterionKind; var check: String? }
struct GoalContract: Codable, Equatable, Sendable { var id = UUID(); var objective: String; var criteria: [Criterion]; var outOfScope: [String]; var stopBefore: [String]; var assumptions: [String]; var changeLog: [ContractChange]; var state: ContractState; /* ... */ }
enum Principal: Sendable { case main, subagent }   // SandboxPolicy.swift — Task 3 adds .evaluator
struct Schema: Codable { var type: String; var properties: [String: Schema]?; var required: [String]?; var description: String?; var items: Schema? /* backed by single-elem array; init(type:properties:required:description:items:) */ }
enum JSONValue { case string(String); case int(Int); case double(Double); case bool(Bool); case object([String: JSONValue]); case array([JSONValue]); case null; var stringValue: String { get } }
// IrisEngine.init(state:tier:principal:roleLabel:client:)  — iris.swift:22
// AppState.onSubagentComplete: [UUID: @Sendable (String) -> Void]  — the callback pattern to mirror
// AppState.createNewConversation(id:isSubagent:), setGoal(for:goal:), clearGoal(for:), saveConversations()
```

---

### Task 1: `GoalEvaluation` + `CriterionVerdict` model, persisted on `Conversation`

**Files:**
- Create: `Sources/iris/GoalEvaluation.swift`
- Modify: `Sources/iris/AppState.swift` (the `Conversation` struct: stored prop + `CodingKeys` + `init(from:)` + memberwise init default)
- Test: `Tests/irisTests/GoalEvaluationTests.swift`

**Interfaces:**
- Produces: `enum CriterionVerdictValue`, `enum VerdictMethod`, `struct CriterionVerdict`, `enum EvaluationStatus`, `struct GoalEvaluation`; `Conversation.lastGoalEvaluation: GoalEvaluation?`.

- [ ] **Step 1: Write the failing test**

Create `Tests/irisTests/GoalEvaluationTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@Suite("GoalEvaluation model")
struct GoalEvaluationTests {
    private func sample() -> GoalEvaluation {
        GoalEvaluation(
            status: .graded,
            criteria: [
                CriterionVerdict(criterionId: UUID(), criterionText: "swift build green",
                                 kind: .executable, verdict: .met,
                                 evidence: "swift build → exit 0", method: .check),
                CriterionVerdict(criterionId: UUID(), criterionText: "looks good",
                                 kind: .humanJudged, verdict: .humanPending,
                                 evidence: "", method: .human)
            ],
            startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 200))
    }

    @Test("round-trips through Codable")
    func codable() throws {
        let e = sample()
        let back = try JSONDecoder().decode(GoalEvaluation.self, from: JSONEncoder().encode(e))
        #expect(back == e)
    }

    @Test("a legacy conversation with no evaluation decodes with nil")
    func legacyNil() throws {
        let json = #"{"id":"\#(UUID().uuidString)","title":"t","messages":[],"history":[],"tokenUsage":{"promptTokenCount":0,"candidatesTokenCount":0,"totalTokenCount":0},"messageCountSinceReflection":0}"#
        let conv = try JSONDecoder().decode(Conversation.self, from: Data(json.utf8))
        #expect(conv.lastGoalEvaluation == nil)
    }

    @Test("verdict + method + status enums are string-coded")
    func rawValues() {
        #expect(CriterionVerdictValue.notMet.rawValue == "not_met")
        #expect(CriterionVerdictValue.cannotVerify.rawValue == "cannot_verify")
        #expect(CriterionVerdictValue.humanPending.rawValue == "human_pending")
        #expect(EvaluationStatus.verifying.rawValue == "verifying")
        #expect(VerdictMethod.check.rawValue == "check")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter GoalEvaluationTests 2>&1 | tail -15`
Expected: FAIL — `cannot find 'GoalEvaluation' in scope`.

- [ ] **Step 3: Create the model**

Create `Sources/iris/GoalEvaluation.swift`:

```swift
import Foundation

/// The grader's verdict for one criterion. `met`/`notMet`/`cannotVerify` are gradable outcomes;
/// `humanPending` marks a `humanJudged` criterion the grader must not auto-grade (spec §4.4).
enum CriterionVerdictValue: String, Codable, Sendable, Equatable {
    case met
    case notMet = "not_met"
    case cannotVerify = "cannot_verify"
    case humanPending = "human_pending"
}

/// How a verdict was reached: a run check (executable), an LLM judgement (qualitative), or
/// deferred to a human (humanJudged).
enum VerdictMethod: String, Codable, Sendable, Equatable {
    case check
    case judge
    case human
}

struct CriterionVerdict: Codable, Identifiable, Equatable, Sendable {
    var id: UUID { criterionId }
    var criterionId: UUID
    var criterionText: String
    var kind: CriterionKind
    var verdict: CriterionVerdictValue
    var evidence: String
    var method: VerdictMethod
}

enum EvaluationStatus: String, Codable, Sendable, Equatable {
    case verifying   // grader running; verdicts not yet in
    case graded      // grader finished normally
    case failed      // grader errored or hit its iteration cap
}

struct GoalEvaluation: Codable, Equatable, Sendable {
    var id = UUID()
    var status: EvaluationStatus
    var criteria: [CriterionVerdict]
    var startedAt: Date
    var completedAt: Date?
}
```

- [ ] **Step 4: Persist on `Conversation`**

In `Sources/iris/AppState.swift`, `struct Conversation`:
- Add the stored property next to `lastGoalCompletionReport`: `var lastGoalEvaluation: GoalEvaluation? = nil`.
- Add `case lastGoalEvaluation` to the `CodingKeys` enum.
- In `init(from:)`, after decoding `lastGoalCompletionReport`, add:
  `lastGoalEvaluation = try container.decodeIfPresent(GoalEvaluation.self, forKey: .lastGoalEvaluation)`
- The memberwise `init` already omits `lastGoalCompletionReport` (it has a default); add `lastGoalEvaluation` the same way ONLY if the existing init lists such fields — otherwise leave it (the default `= nil` covers construction). Match exactly how `lastGoalCompletionReport` is handled.

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter GoalEvaluationTests 2>&1 | tail -10` (3 pass) and `swift build 2>&1 | tail -3`.

- [ ] **Step 6: Commit**

```bash
git add Sources/iris/GoalEvaluation.swift Sources/iris/AppState.swift Tests/irisTests/GoalEvaluationTests.swift
git commit -m "feat(eval): GoalEvaluation model + persistence on Conversation (#9)"
```

---

### Task 2: `submit_evaluation` parsing + reconciliation

**Files:**
- Create: `Sources/iris/GoalEvaluationParsing.swift`
- Test: `Tests/irisTests/GoalEvaluationParsingTests.swift`

**Interfaces:**
- Consumes: `Criterion`, `CriterionVerdict`, `JSONValue` (Task 1 / slice A).
- Produces: `enum GoalEvaluationParsing { static func verdicts(from args: [String: JSONValue], criteria: [Criterion]) -> [CriterionVerdict] }`.

- [ ] **Step 1: Write the failing test**

Create `Tests/irisTests/GoalEvaluationParsingTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@Suite("GoalEvaluation parsing")
struct GoalEvaluationParsingTests {
    private func criteria() -> [Criterion] {
        [Criterion(text: "build", kind: .executable, check: "swift build"),
         Criterion(text: "playable", kind: .qualitative, check: nil),
         Criterion(text: "tasteful", kind: .humanJudged, check: nil)]
    }

    @Test("maps submitted verdicts to the right criteria by id")
    func maps() {
        let c = criteria()
        let args: [String: JSONValue] = ["evaluations": .array([
            .object(["criterion_id": .string(c[0].id.uuidString), "verdict": .string("met"), "evidence": .string("exit 0")]),
            .object(["criterion_id": .string(c[1].id.uuidString), "verdict": .string("not_met"), "evidence": .string("crashes on start")])
        ])]
        let out = GoalEvaluationParsing.verdicts(from: args, criteria: c)
        #expect(out.count == 3)
        #expect(out.first { $0.criterionId == c[0].id }?.verdict == .met)
        #expect(out.first { $0.criterionId == c[0].id }?.method == .check)     // executable → check
        #expect(out.first { $0.criterionId == c[1].id }?.verdict == .notMet)
        #expect(out.first { $0.criterionId == c[1].id }?.method == .judge)     // qualitative → judge
    }

    @Test("an omitted humanJudged criterion becomes humanPending, other omissions cannot_verify")
    func reconciliation() {
        let c = criteria()
        // Only the executable criterion is reported; the other two are omitted.
        let args: [String: JSONValue] = ["evaluations": .array([
            .object(["criterion_id": .string(c[0].id.uuidString), "verdict": .string("met"), "evidence": .string("ok")])
        ])]
        let out = GoalEvaluationParsing.verdicts(from: args, criteria: c)
        #expect(out.first { $0.criterionId == c[1].id }?.verdict == .cannotVerify)   // qualitative omitted
        #expect(out.first { $0.criterionId == c[2].id }?.verdict == .humanPending)   // humanJudged omitted
        #expect(out.first { $0.criterionId == c[2].id }?.method == .human)
    }

    @Test("an unknown verdict string falls back to cannot_verify")
    func unknownVerdict() {
        let c = criteria()
        let args: [String: JSONValue] = ["evaluations": .array([
            .object(["criterion_id": .string(c[0].id.uuidString), "verdict": .string("bogus"), "evidence": .string("")])
        ])]
        let out = GoalEvaluationParsing.verdicts(from: args, criteria: c)
        #expect(out.first { $0.criterionId == c[0].id }?.verdict == .cannotVerify)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter GoalEvaluationParsingTests 2>&1 | tail -12`
Expected: FAIL — `cannot find 'GoalEvaluationParsing'`.

- [ ] **Step 3: Implement the parser**

Create `Sources/iris/GoalEvaluationParsing.swift`:

```swift
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter GoalEvaluationParsingTests 2>&1 | tail -8` (3 pass) and `swift build 2>&1 | tail -3`.

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/GoalEvaluationParsing.swift Tests/irisTests/GoalEvaluationParsingTests.swift
git commit -m "feat(eval): submit_evaluation parsing + humanJudged-aware reconciliation (#9)"
```

---

### Task 3: `Principal.evaluator` + the mutation-free evaluator toolset

**Files:**
- Modify: `Sources/iris/SandboxPolicy.swift` (add `.evaluator` to `Principal`)
- Create: `Sources/iris/EvaluatorToolset.swift` (pure filter + the `submit_evaluation` declaration)
- Modify: `Sources/iris/iris.swift` (apply the filter in tool assembly for `.evaluator`)
- Test: `Tests/irisTests/EvaluatorToolsetTests.swift`

**Interfaces:**
- Consumes: `FunctionDeclaration`, `Schema` (slice A).
- Produces: `Principal.evaluator`; `enum EvaluatorToolset { static let allowedNames: Set<String>; static let submitEvaluation: FunctionDeclaration; static func restrict(_ tools: [FunctionDeclaration]) -> [FunctionDeclaration] }`.

- [ ] **Step 1: Write the failing test**

Create `Tests/irisTests/EvaluatorToolsetTests.swift`:

```swift
import Testing
@testable import iris

@Suite("Evaluator toolset")
struct EvaluatorToolsetTests {
    private func fullToolset() -> [FunctionDeclaration] {
        ["read_file", "run_command", "write_file", "goal_complete", "invoke_subagent",
         "propose_goal_contract", "amend_goal_contract", "search_web", "create_skill"].map {
            FunctionDeclaration(name: $0, description: "d", parameters: nil)
        }
    }

    @Test("restrict keeps only read_file, run_command, submit_evaluation")
    func restricts() {
        let out = EvaluatorToolset.restrict(fullToolset())
        let names = Set(out.map { $0.name })
        #expect(names == ["read_file", "run_command", "submit_evaluation"])
    }

    @Test("submit_evaluation is present and its evaluations array declares items")
    func submitDeclared() {
        let out = EvaluatorToolset.restrict(fullToolset())
        let submit = out.first { $0.name == "submit_evaluation" }
        #expect(submit != nil)
        let evals = submit?.parameters?.properties?["evaluations"]
        #expect(evals?.type == "ARRAY")
        #expect(evals?.items != nil)                      // Gemini requires items on arrays
        #expect(submit?.parameters?.required == ["evaluations"])
    }

    @Test("no mutation or goal tool survives")
    func noMutation() {
        let names = Set(EvaluatorToolset.restrict(fullToolset()).map { $0.name })
        for banned in ["write_file", "goal_complete", "invoke_subagent", "propose_goal_contract",
                       "amend_goal_contract", "search_web", "create_skill"] {
            #expect(!names.contains(banned))
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter EvaluatorToolsetTests 2>&1 | tail -12`
Expected: FAIL — `cannot find 'EvaluatorToolset'`.

- [ ] **Step 3: Add the principal**

In `Sources/iris/SandboxPolicy.swift`, add a case to `Principal`:

```swift
public enum Principal: Sendable {
    case main
    case subagent
    case evaluator
}
```

Build immediately (`swift build 2>&1 | tail -20`) and fix any non-exhaustive `switch principal` errors this surfaces by treating `.evaluator` like `.subagent` at each site (it is a sandboxed, non-main context), EXCEPT where this plan says otherwise. Note each file you touch for the reviewer.

- [ ] **Step 4: Create the toolset filter + declaration**

Create `Sources/iris/EvaluatorToolset.swift`:

```swift
import Foundation

/// The evaluator's world is read-only + running the contract's checks + reporting a verdict.
/// This restricts an assembled tool list to exactly that surface (spec §4.1) and guarantees the
/// terminal `submit_evaluation` tool is present.
enum EvaluatorToolset {
    static let allowedNames: Set<String> = ["read_file", "run_command", "submit_evaluation"]

    static let submitEvaluation = FunctionDeclaration(
        name: "submit_evaluation",
        description: "Report your independent verdict for the goal contract and end the evaluation. Provide one entry per criterion you graded. Honesty: use cannot_verify when you genuinely can't determine a criterion; never claim met without evidence. Do not grade human-judged criteria.",
        parameters: Schema(type: "OBJECT", properties: [
            "evaluations": Schema(type: "ARRAY", description: "One verdict per graded criterion.", items: Schema(type: "OBJECT", properties: [
                "criterion_id": Schema(type: "STRING", description: "The id of the criterion (copied from the contract you were given)."),
                "verdict": Schema(type: "STRING", description: "met | not_met | cannot_verify"),
                "evidence": Schema(type: "STRING", description: "Concrete evidence: a command + exit code, a file:line, or a one-sentence observation.")
            ], required: ["criterion_id", "verdict"]))
        ], required: ["evaluations"]))

    /// Keep only the allowed tools, and ensure `submit_evaluation` is present exactly once.
    static func restrict(_ tools: [FunctionDeclaration]) -> [FunctionDeclaration] {
        var kept = tools.filter { allowedNames.contains($0.name) && $0.name != "submit_evaluation" }
        kept.append(submitEvaluation)
        return kept
    }
}
```

- [ ] **Step 5: Apply the filter in assembly**

In `Sources/iris/iris.swift`, the tool list is built at `var toolsList = await executor.getTools()` (~L256), engine tools are appended through ~L432, then `toolsList = ToolIntent.augment(toolsList)` (~L432), then the `restrictToGoalComplete` filter (~L464). Immediately AFTER the `ToolIntent.augment(toolsList)` line and BEFORE the `restrictToGoalComplete` filter, insert:

```swift
        // The evaluator gets a mutation-free surface: read + run + submit_evaluation only (#9).
        if principal == .evaluator {
            toolsList = EvaluatorToolset.restrict(toolsList)
        }
```

(The augmenter still runs first, so `submit_evaluation` — appended by `restrict` after augmentation — will NOT carry an `intent`; that's fine, intent is optional and the evaluator has no UI intent row. Do not special-case it.)

- [ ] **Step 6: Run tests + build**

Run: `swift test --filter EvaluatorToolsetTests 2>&1 | tail -8` (3 pass) and `swift build 2>&1 | tail -3` (Build complete).

- [ ] **Step 7: Commit**

```bash
git add Sources/iris/SandboxPolicy.swift Sources/iris/EvaluatorToolset.swift Sources/iris/iris.swift Tests/irisTests/EvaluatorToolsetTests.swift
git commit -m "feat(eval): Principal.evaluator + mutation-free evaluator toolset (#9)"
```

---

### Task 4: `submit_evaluation` handler + the evaluation-complete callback

**Files:**
- Modify: `Sources/iris/AppState.swift` (add `onEvaluationComplete` map + `recordEvaluation`)
- Modify: `Sources/iris/iris.swift` (`executeFunctionCall`: handle `submit_evaluation`)
- Test: `Tests/irisTests/SubmitEvaluationHandlerTests.swift`

**Interfaces:**
- Consumes: `GoalEvaluationParsing.verdicts(from:criteria:)` (Task 2); `GoalEvaluation`, `EvaluationStatus` (Task 1).
- Produces: `AppState.onEvaluationComplete: [UUID: @Sendable (JSONValue?) -> Void]`; `AppState.recordEvaluation(for:_:)`.

- [ ] **Step 1: Add the callback map + recorder to `AppState`**

In `Sources/iris/AppState.swift`, next to `var onSubagentComplete: [UUID: @Sendable (String) -> Void] = [:]` add:

```swift
    /// Fired by the `submit_evaluation` handler in the EVALUATOR's own conversation; the closure
    /// (registered by GoalEvaluator) reconciles the verdict and writes it to the ORIGINATING
    /// conversation. Keyed by the evaluator conversation id. Mirrors `onSubagentComplete`.
    var onEvaluationComplete: [UUID: @Sendable (JSONValue?) -> Void] = [:]
```

And a recorder used later by GoalEvaluator (Task 5) and by tests:

```swift
    /// Writes a finished evaluation onto the originating conversation (marks it graded/failed).
    func recordEvaluation(for conversationId: UUID, _ evaluation: GoalEvaluation) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].lastGoalEvaluation = evaluation
        saveConversations()
    }
```

- [ ] **Step 2: Write the failing test**

Create `Tests/irisTests/SubmitEvaluationHandlerTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@MainActor
@Suite("submit_evaluation handler")
struct SubmitEvaluationHandlerTests {
    private func response(_ fc: FunctionCall?) -> GeminiResponse {
        let part = Part(text: fc == nil ? "done" : nil, functionCall: fc, functionResponse: nil,
                        thought_signature: nil, thoughtSignature: nil)
        return GeminiResponse(candidates: [Candidate(content: Content(role: "model", parts: [part]))], usageMetadata: nil)
    }

    @Test("submit_evaluation fires onEvaluationComplete with the payload and ends the evaluator loop")
    func firesCallback() async {
        let app = AppState()
        let evalId = UUID()
        app.createNewConversation(id: evalId, isSubagent: true)
        app.setGoal(for: evalId, goal: "grade the work")   // gives the evaluator loop a goal to clear

        // Capture the payload the handler forwards.
        actor Box { var v: JSONValue?; func set(_ x: JSONValue?) { v = x }; func get() -> JSONValue? { v } }
        let box = Box()
        app.onEvaluationComplete[evalId] = { payload in Task { await box.set(payload) } }

        let submit = FunctionCall(name: "submit_evaluation",
            args: ["evaluations": .array([.object(["criterion_id": .string(UUID().uuidString), "verdict": .string("met"), "evidence": .string("ok")])])],
            id: nil, thought_signature: nil, thoughtSignature: nil)
        // Response 1: submit_evaluation. Response 2: text (loop should already be ending).
        let mock = ScriptedLLMClient(responses: [response(submit), response(nil)])
        let engine = IrisEngine(state: app, tier: .medium, principal: .evaluator, client: mock)
        await engine.processInput("grade", source: "System", conversationId: evalId)

        #expect(await box.get() != nil)                                   // callback fired with payload
        #expect(app.conversations.first { $0.id == evalId }?.activeGoal == nil)   // evaluator loop cleared
    }
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `swift test --filter SubmitEvaluationHandlerTests 2>&1 | tail -15`
Expected: FAIL — the model calls `submit_evaluation` but nothing handles it (the loop won't clear / callback never fires).

- [ ] **Step 4: Handle `submit_evaluation` in `executeFunctionCall`**

In `Sources/iris/iris.swift`, in the `executeFunctionCall` if/else-if chain, add a branch (place it right after the `goal_complete` branch, before the final `else`):

```swift
        } else if functionCall.name == "submit_evaluation" {
            let payload = functionCall.args["evaluations"]
            await MainActor.run {
                localState?.onEvaluationComplete[conversationId]?(JSONValue.object(["evaluations": payload ?? .null]))
                localState?.onEvaluationComplete[conversationId] = nil
                localState?.clearGoal(for: conversationId)   // end the evaluator's own loop (mirrors goal_complete)
            }
            result = "Evaluation submitted."
```

- [ ] **Step 5: Run to verify it passes**

Run: `swift test --filter SubmitEvaluationHandlerTests 2>&1 | tail -10` (1 pass) and `swift build 2>&1 | tail -3`.

- [ ] **Step 6: Commit**

```bash
git add Sources/iris/AppState.swift Sources/iris/iris.swift Tests/irisTests/SubmitEvaluationHandlerTests.swift
git commit -m "feat(eval): submit_evaluation handler + evaluation-complete callback (#9)"
```

---

### Task 5: `GoalEvaluator` run + trigger from `goal_complete`

**Files:**
- Create: `Sources/iris/GoalEvaluator.swift` (the fresh-context grader run)
- Create: `Sources/iris/assets/EVALUATOR.md` (grader system prompt) — and confirm it's bundled like other assets
- Modify: `Sources/iris/iris.swift` (`goal_complete` handler: snapshot + kick, main-only)
- Modify: `Sources/iris/AppState.swift` (`beginGoalEvaluation` snapshot; extend the ✕-dismiss + `setDraftContract` to clear `lastGoalEvaluation`)
- Test: `Tests/irisTests/GoalEvaluatorTriggerTests.swift`

**Interfaces:**
- Consumes: `GoalContract`, `IrisEngine(principal:.evaluator)`, `GoalEvaluationParsing.verdicts`, `AppState.onEvaluationComplete`, `recordEvaluation`, `SubagentManager.runSubagent` pattern.
- Produces: `GoalEvaluator.shared.evaluate(contract:workspace:originatingConversationId:)`; `AppState.beginGoalEvaluation(for:contract:)`.

- [ ] **Step 1: Snapshot + verifying-state on `AppState`**

In `Sources/iris/AppState.swift` add:

```swift
    /// Captures the locked contract's criteria as a fresh `.verifying` evaluation BEFORE the goal
    /// is cleared, so the async grader has a snapshot to grade against (spec §3.2). Returns the
    /// snapshot contract for the grader.
    @discardableResult
    func beginGoalEvaluation(for conversationId: UUID, contract: GoalContract) -> GoalContract {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return contract }
        let pending = GoalEvaluation(
            status: .verifying,
            criteria: contract.criteria.map {
                CriterionVerdict(criterionId: $0.id, criterionText: $0.text, kind: $0.kind,
                                 verdict: $0.kind == .humanJudged ? .humanPending : .cannotVerify,
                                 evidence: "", method: $0.kind == .executable ? .check : ($0.kind == .qualitative ? .judge : .human))
            },
            startedAt: Date(), completedAt: nil)
        conversations[idx].lastGoalEvaluation = pending
        saveConversations()
        return contract
    }
```

Also extend the two existing lifecycle sites to clear the evaluation alongside the report:
- In `dismissCompletionReport(for:)` add `conversations[idx].lastGoalEvaluation = nil`.
- In `setDraftContract(for:_:)` (which already clears `lastGoalCompletionReport`) add `conversations[idx].lastGoalEvaluation = nil`.

- [ ] **Step 2: Create the grader run**

Create `Sources/iris/GoalEvaluator.swift`. Model the setup on `SubagentManager.runSubagent` (fresh conversation, fresh engine, role prompt, capped loop). Key differences: `principal: .evaluator`, the grader prompt from `EVALUATOR.md` with the serialized contract appended, and it resolves via `onEvaluationComplete` rather than `onSubagentComplete`.

```swift
import Foundation

final class GoalEvaluator: @unchecked Sendable {
    static let shared = GoalEvaluator()
    private init() {}

    /// Runs a fresh-context grader against `contract` and writes a `GoalEvaluation` onto
    /// `originatingConversationId`. Non-blocking for the caller: dispatch this in a detached Task.
    /// `client` is injectable so tests can drive the grader with a `ScriptedLLMClient` instead of
    /// hitting the network.
    func evaluate(contract: GoalContract, workspace: String?, originatingConversationId originId: UUID,
                  client: any LLMClientProtocol = LLMClient()) async {
        let app = await MainActor.run { AppState.shared }

        let evalId = UUID()
        await MainActor.run {
            app.createNewConversation(id: evalId, isSubagent: true)
            app.updateConversationTitle(id: evalId, title: "Evaluator")
            if let ws = workspace { app.setWorkspace(ws, for: evalId) }  // grader inspects the real workspace
        }

        // Fresh engine, evaluator principal. It never sees the working transcript.
        let engine = IrisEngine(state: app, tier: .hard, principal: .evaluator, roleLabel: "evaluator", client: client)
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
                    app.deleteConversation(id: evalId)   // grader conversation is scratch
                }
            }
        }

        // Kick the grader loop; its activeGoal makes it auto-reprompt until it calls submit_evaluation.
        await MainActor.run { app.setGoal(for: evalId, goal: "Evaluate the completed work against the contract above, then call submit_evaluation.") }
        await engine.processInput("Begin your evaluation. Inspect the workspace, run the checks, then call submit_evaluation.",
                                  source: "System", conversationId: evalId)

        // Safety net: if the loop ended without submit_evaluation, mark the evaluation failed.
        let stillVerifying = await MainActor.run { () -> Bool in
            app.conversations.first { $0.id == originId }?.lastGoalEvaluation?.status == .verifying
        }
        if stillVerifying {
            let failed = GoalEvaluation(
                status: .failed,
                criteria: contract.criteria.map {
                    CriterionVerdict(criterionId: $0.id, criterionText: $0.text, kind: $0.kind,
                                     verdict: $0.kind == .humanJudged ? .humanPending : .cannotVerify,
                                     evidence: "Evaluator ended without submitting a verdict.",
                                     method: $0.kind == .executable ? .check : ($0.kind == .qualitative ? .judge : .human))
                },
                startedAt: Date(), completedAt: Date())
            await MainActor.run {
                app.recordEvaluation(for: originId, failed)
                app.onEvaluationComplete[evalId] = nil
            }
        }
    }

    private static func systemPrompt(for contract: GoalContract) -> String {
        let base = (try? String(contentsOfFile: Bundle.module.path(forResource: "EVALUATOR", ofType: "md") ?? "", encoding: .utf8)) ?? fallbackPrompt
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
```

> **Implementer notes:**
> - Verify the exact `AppState` helpers used exist with these names: `updateConversationTitle(id:title:)`, `setWorkspace(_:for:)`, `deleteConversation(id:)`, `setGoal(for:goal:)`. If a name differs, match the real one (grep `SubagentManager.swift` — it uses the same helpers). If `setWorkspace(_:for:)` doesn't exist, set `conversations[idx].workspacePath` directly via a small helper.
> - `Bundle.module.path(forResource:ofType:)` is how other bundled assets in this target are read (confirm against how `SYSTEM.md`/`EVALUATOR.md` siblings load; mirror that exact call).
> - `IrisEngine.setSystemPrompt(text:)` and `setGoal(for:goal:)` are the same ones `SubagentManager.runSubagent` uses.

- [ ] **Step 3: Create the grader prompt asset**

Create `Sources/iris/assets/EVALUATOR.md`:

```markdown
# Impartial Goal Evaluator

You are an impartial evaluator. You did NOT do the work and have no stake in it passing. Your
job is to independently determine, for each criterion of the locked contract below, whether the
finished work in this workspace actually satisfies it.

## Rules
- Gather your OWN evidence with `read_file` and `run_command`. Do not trust any prior summary.
- For an `executable` criterion, RUN its check command. Exit code 0 → met; nonzero → not_met; if
  you truly cannot run it → cannot_verify. Quote the command and exit code as evidence.
- For a `qualitative` criterion, inspect the artifacts (diffs, files, run the thing) against its
  concrete description. Cite a file:line or command output as evidence.
- For a `humanJudged` criterion, do NOT grade it — omit it from your submission.
- You may ONLY read and run commands. You cannot edit, write, install, or reach the network.
- HONESTY: return `cannot_verify` when you genuinely can't determine a criterion. NEVER claim
  `met` without concrete evidence. You are not here to be nice; you are here to be right.

When done, call `submit_evaluation` with one entry per criterion you graded.
```

Confirm the SwiftPM target's `resources` glob already includes `Sources/iris/assets/*.md` (slice A's `SYSTEM.md` lives there); if `EVALUATOR.md` isn't picked up, add it to `Package.swift` resources the same way.

- [ ] **Step 4: Trigger from `goal_complete` (snapshot + kick, main-only)**

In `Sources/iris/iris.swift`, the `goal_complete` handler currently reads (post slice-A):

```swift
        } else if functionCall.name == "goal_complete", let summary = functionCall.args["summary"]?.stringValue {
            let statusReport = functionCall.args["criteria_status"]
            await MainActor.run {
                localState?.recordCompletionSelfReport(for: conversationId, statusJSON: statusReport)
                localState?.clearGoal(for: conversationId)
                localState?.onSubagentComplete[conversationId]?(summary)
                localState?.onSubagentComplete[conversationId] = nil
            }
            // ...
```

Capture the contract BEFORE `clearGoal`, snapshot it, and kick the grader — only for the main agent with a contract:

```swift
        } else if functionCall.name == "goal_complete", let summary = functionCall.args["summary"]?.stringValue {
            let statusReport = functionCall.args["criteria_status"]
            let contractToGrade: GoalContract? = (principal == .main)
                ? await MainActor.run { localState?.conversations.first(where: { $0.id == conversationId })?.goalContract }
                : nil
            let gradeWorkspace = workspacePath
            await MainActor.run {
                localState?.recordCompletionSelfReport(for: conversationId, statusJSON: statusReport)
                if let c = contractToGrade { localState?.beginGoalEvaluation(for: conversationId, contract: c) }
                localState?.clearGoal(for: conversationId)
                localState?.onSubagentComplete[conversationId]?(summary)
                localState?.onSubagentComplete[conversationId] = nil
            }
            if let c = contractToGrade {
                // Non-blocking: grade in the background; the verdict fills in the chip when ready.
                // Pass the engine's own client so tests drive the grader with a scripted client
                // (in production this is the real LLMClient). `client` here is this IrisEngine's
                // stored client property (from init(...client:)) — capture it into a local first
                // since the detached task can't touch actor-isolated state.
                let graderClient = self.client
                Task.detached { await GoalEvaluator.shared.evaluate(contract: c, workspace: gradeWorkspace, originatingConversationId: conversationId, client: graderClient) }
            }
            await pushToUI(role: .agent, text: summary, conversationId: conversationId)
            // ... rest unchanged (principal == .main skill-check, result = ...)
```

- [ ] **Step 5: Write the trigger test**

Create `Tests/irisTests/GoalEvaluatorTriggerTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@MainActor
@Suite("GoalEvaluator trigger")
struct GoalEvaluatorTriggerTests {
    private func response(_ fc: FunctionCall?) -> GeminiResponse {
        let part = Part(text: fc == nil ? "done" : nil, functionCall: fc, functionResponse: nil,
                        thought_signature: nil, thoughtSignature: nil)
        return GeminiResponse(candidates: [Candidate(content: Content(role: "model", parts: [part]))], usageMetadata: nil)
    }

    @Test("goal_complete on a locked contract snapshots a .verifying evaluation before clearing the goal")
    func snapshots() async {
        let app = AppState()
        let id = UUID()
        app.createNewConversation(id: id)
        var contract = GoalContract(objective: "obj", criteria: [Criterion(text: "c", kind: .qualitative, check: nil)])
        contract.lock()
        app.setGoalContract(for: id, contract)

        let done = FunctionCall(name: "goal_complete", args: ["summary": .string("done")],
                                id: nil, thought_signature: nil, thoughtSignature: nil)
        // The evaluator subagent will also spin up and hit the scripted client; give it a submit_evaluation then text.
        let submit = FunctionCall(name: "submit_evaluation",
            args: ["evaluations": .array([.object(["criterion_id": .string(contract.criteria[0].id.uuidString), "verdict": .string("met"), "evidence": .string("ok")])])],
            id: nil, thought_signature: nil, thoughtSignature: nil)
        let mock = ScriptedLLMClient(responses: [response(done), response(submit), response(nil)])
        let engine = IrisEngine(state: app, tier: .medium, principal: .main, client: mock)
        await engine.processInput("go", source: "System", conversationId: id)

        // The self-report path still clears the goal…
        #expect(app.conversations.first { $0.id == id }?.activeGoal == nil)
        // …and a snapshot evaluation was recorded (verifying, or graded if the detached grader already finished).
        let eval = app.conversations.first { $0.id == id }?.lastGoalEvaluation
        #expect(eval != nil)
        #expect(eval?.criteria.count == 1)
    }
}
```

> This test asserts the SNAPSHOT is created (the deterministic, synchronous part). The detached grader's completion is timing-dependent, so the test only requires `lastGoalEvaluation != nil` with the right criteria count — do not assert `.graded` here (that race is covered by Task 4's handler test).

- [ ] **Step 6: Run + build**

Run: `swift test --filter GoalEvaluatorTriggerTests 2>&1 | tail -10` and `swift build 2>&1 | tail -3`. Also re-run `swift test --filter GoalCompleteStatusTests 2>&1 | tail -3` (slice A) — still green.

- [ ] **Step 7: Commit**

```bash
git add Sources/iris/GoalEvaluator.swift Sources/iris/assets/EVALUATOR.md Sources/iris/iris.swift Sources/iris/AppState.swift Tests/irisTests/GoalEvaluatorTriggerTests.swift
git commit -m "feat(eval): GoalEvaluator run + goal_complete snapshot-and-kick trigger (#9)"
```

---

### Task 6: Vibecop grader caller-role layer

**Files:**
- Modify: `Sources/iris/VibecopService.swift` (`evaluateAction` gains caller-role + check allowlist; grader prompt layer)
- Modify: the approval call path so the evaluator's `run_command` reaches Vibecop as `.evaluator` with the contract's checks (`Sources/iris/AppState.swift` around the `evaluateAction` call ~L747, plus the engine→approval threading)
- Test: `Tests/irisTests/VibecopEvaluatorLayerTests.swift`

**Interfaces:**
- Consumes: nothing new beyond `Principal`.
- Produces: `VibecopService.evaluateAction(toolName:details:workspace:inSandbox:callerRole:allowedCommands:)` with `enum VibecopCallerRole { case agent, evaluator }`.

- [ ] **Step 1: Add the caller role + grader layer to `VibecopService`**

In `Sources/iris/VibecopService.swift`:
- Add `enum VibecopCallerRole: Sendable { case agent, evaluator }`.
- Change the signature to `func evaluateAction(toolName: String, details: String, workspace: String?, inSandbox: Bool = false, callerRole: VibecopCallerRole = .agent, allowedCommands: [String] = []) async throws -> VibecopDecision`.
- After the sandbox-context block and before the `"\n\nProposed Action:"` line, add:

```swift
        if callerRole == .evaluator {
            let allow = allowedCommands.isEmpty ? "(none declared)" : allowedCommands.map { "`\($0)`" }.joined(separator: ", ")
            prompt += """


            CALLER ROLE: EVALUATOR. The caller is grading finished work against a fixed contract.
            Its ONLY legitimate actions are reading files and running these declared check commands:
            \(allow).
            APPROVE reads and the declared checks (and their obvious sub-invocations). ESCALATE or
            DENY anything that writes, edits, deletes, installs, reaches the network, or runs a
            command outside that set — the evaluator must not modify the work it is grading.
            """
        }
```

- [ ] **Step 2: Thread caller-role + checks to the call site**

Trace how the evaluator's `run_command` reaches `VibecopService.shared.evaluateAction` (the call is in `AppState.swift` ~L747, inside the approval helper that also takes `conversationId`/`origin`). Add `callerRole: VibecopCallerRole` and `allowedCommands: [String]` parameters to that approval helper and forward them into `evaluateAction`. The engine calls that helper during tool execution; when `principal == .evaluator`, pass `.evaluator` and the contract's `check` commands. The engine already holds `principal`; carry the contract's checks into the evaluator engine (e.g. store them on `IrisEngine` when constructed for evaluation, or thread from `GoalEvaluator`). Follow the existing `origin`/`conversationId` parameter as the threading template.

> **Implementer:** this is the one cross-file wiring in the slice. Keep the default arguments (`callerRole: .agent`, `allowedCommands: []`) so every existing caller compiles unchanged; only the evaluator path passes the new values. If threading the checks all the way to the call site proves invasive, the acceptable minimal version is: pass `callerRole: .evaluator` (from `principal`) and `allowedCommands: []` — the grader layer still tightens correctly, just without the allowlist specificity. Note in your report which version you shipped.

- [ ] **Step 3: Write the test**

Create `Tests/irisTests/VibecopEvaluatorLayerTests.swift`:

```swift
import Testing
@testable import iris

@Suite("Vibecop evaluator layer")
struct VibecopEvaluatorLayerTests {
    @Test("the evaluator caller role tightens the prompt and lists the allowed checks")
    func buildsGraderPrompt() {
        // The prompt assembly for the evaluator layer is exposed as a pure helper for testability.
        let text = VibecopService.evaluatorLayerText(allowedCommands: ["swift test", "swift build"])
        #expect(text.contains("CALLER ROLE: EVALUATOR"))
        #expect(text.contains("swift test"))
        #expect(text.contains("must not modify"))
    }
}
```

To make that pure helper exist, refactor the Step 1 inline block into a `static func evaluatorLayerText(allowedCommands: [String]) -> String` on `VibecopService` and call it from `evaluateAction`. (This keeps the string testable without invoking a model.)

- [ ] **Step 4: Run + build**

Run: `swift test --filter VibecopEvaluatorLayerTests 2>&1 | tail -6` (1 pass) and `swift build 2>&1 | tail -3`. Re-run the whole goal suite (`swift test --filter Goal 2>&1 | tail -5`) to confirm no threading regressions.

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/VibecopService.swift Sources/iris/AppState.swift Tests/irisTests/VibecopEvaluatorLayerTests.swift
git commit -m "feat(eval): Vibecop evaluator caller-role layer with check allowlist (#9)"
```

---

### Task 7: Drift-reveal completion chip (GUI-verified)

**Files:**
- Modify: `Sources/iris/GoalContractPanel.swift` (the completion chip: render `lastGoalEvaluation` as a two-column drift view)
- Test: none (GUI) — gate is a clean `swift build` + careful self-review

**Interfaces:**
- Consumes: `Conversation.lastGoalEvaluation`, `GoalEvaluation`, `CriterionVerdict`, `CriterionVerdictValue`, `EvaluationStatus`; the existing self-report (`lastGoalCompletionReport`) for the left column.

- [ ] **Step 1: Render the drift view**

The completion chip (`CompletionReportChip` / `CompletionReportSection`) currently renders only the self-report. Extend it so, when `conversation.lastGoalEvaluation` is present, each row shows **criterion + kind badge · self-report verdict (neutral) · grader verdict (colored) + evidence**, with a `⚠ drift` flag when they disagree. Spine = `lastGoalEvaluation.criteria` (each has `criterionId`, `kind`, grader `verdict`, `evidence`); the self-report value is matched best-effort by criterion text against `lastGoalCompletionReport`.

Styling rules (spec §7, Global Constraints):
- **Self-report column:** neutral only — `Image(systemName: "circle.dashed")` / `"questionmark.circle"`, `.foregroundStyle(.secondary)`. NEVER a green check.
- **Grader column:** earns color — `.met` → `checkmark.circle.fill` `.green`; `.notMet` → `xmark.octagon.fill` `.red`; `.cannotVerify` → `questionmark.circle` `.secondary`; `.humanPending` → `person.crop.circle.badge.questionmark` with the text "your call", `.secondary`.
- When `status == .verifying`, the grader column shows a "verifying…" `ProgressView().controlSize(.small)` instead of a verdict.
- A row where self-report says met/verified-ish but grader `verdict == .notMet` gets a small `⚠ drift` badge (`.orange`).
- Use `foregroundStyle` (not `foregroundColor`); give every icon-only element an `.accessibilityLabel`; use a stable `ForEach` id (`CriterionVerdict` is `Identifiable` by `criterionId`).

Keep the existing ✕ dismiss (Task 5 already made it clear both artifacts). Keep the "Independent verification arrives with the drift evaluator (not yet built)." caption ONLY when there is no evaluation yet; when an evaluation exists, drop that caption (the evaluator now exists).

- [ ] **Step 2: Build**

Run: `swift build 2>&1 | tail -4`. Expected: `Build complete!`.

- [ ] **Step 3: Commit**

```bash
git add Sources/iris/GoalContractPanel.swift
git commit -m "feat(eval): two-column drift-reveal completion chip (self-report vs grader) (#9)"
```

- [ ] **Step 4: GUI verification (user `swift run`)**

Ask the human partner to verify: run a `/goal` with at least one `executable` (real `check`) + one `qualitative` + one `humanJudged` criterion; on completion the chip shows the self-report immediately with a "verifying…" grader column; seconds later the grader column fills in with colored verdicts + evidence; a disagreement shows `⚠ drift`; the `humanJudged` row shows "your call"; the ✕ clears everything.

---

## Notes for the implementer

- `swift test` builds the whole package (MLX/ONNX/llama) and can be slow cold; use `--filter <Suite>` while iterating.
- **Do not convert the `activeGoal` gate.** The evaluator loop uses `activeGoal`/`setGoal` exactly like a subagent so it auto-reprompts until `submit_evaluation` clears it.
- **Slice C is non-blocking** — never make a failing grade stop `goal_complete` or re-prompt the working agent. That is slice D.
- Preserve every existing line in the `goal_complete` handler (self-report record, `clearGoal`, `onSubagentComplete` fire+nil, summary `pushToUI`, the main-agent skill-check). Snapshot + kick are ADDED, not replacements.
- The evaluator must never receive the working transcript: it runs in its own fresh conversation. Do not pass parent history into it.
- Reuse the `ScriptedLLMClient` test pattern (`Tests/irisTests/LoopStopEnforcementTests.swift`) for any behavioral test; the `IrisEngine(principal:.evaluator)` constructor accepts the scripted client.
- README/AGENTS: no user-facing README change needed; this is internal machinery surfaced only through the existing completion chip.
```
