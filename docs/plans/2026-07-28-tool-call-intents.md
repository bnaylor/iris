# Tool-Call Intents (all tools) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the `run_command` `intent` pattern (#27) to every tool via one central augmenter, plus strengthened steering.

**Architecture:** A single `ToolIntent.augment(_:)` helper injects an optional `intent` STRING into every tool's parameter schema, applied once to the assembled tool list in `iris.swift`. `run_command`'s hand-added `intent` is removed so intent has one source. The UI already renders `intent` for any tool (no change).

**Tech Stack:** Swift 6 (language mode v6), swift-testing (`import Testing`).

## Global Constraints

- `intent` is an **optional** STRING on every tool, **never** added to `required`. Uniform description: `"One short phrase: why you're making this tool call (shown to the user)."`
- Intent is injected by `ToolIntent.augment(_:)` applied **once** to the fully-assembled `toolsList` in `iris.swift`, **before** `fireBeforeToolSelection` and the `restrictToGoalComplete` filter.
- `augment` is idempotent (skips a tool that already declares `intent`); a tool with `parameters == nil` gets a fresh `OBJECT` schema carrying only `intent`.
- `run_command`'s hand-added `intent` property (from #27) is removed — single source of truth.
- No UI changes: `ToolCallParser` reads `args["intent"]` and `SystemMessageContent.toolCallRow` renders it for any tool.
- Tests use swift-testing (`import Testing`, `@Suite`, `@Test`, `#expect`), `@testable import iris`, in `Tests/irisTests/`.
- Types (from `Models.swift`, all mutable structs): `FunctionDeclaration { var name: String; var description: String; var parameters: Schema? }`, `Schema { var type: String; var properties: [String: Schema]?; var required: [String]?; var description: String? }`.

---

### Task 1: `ToolIntent.augment` helper

**Files:**
- Create: `Sources/iris/ToolIntent.swift`
- Test: `Tests/irisTests/ToolIntentTests.swift`

**Interfaces:**
- Produces: `enum ToolIntent { static let description: String; static func augment(_ tools: [FunctionDeclaration]) -> [FunctionDeclaration] }`

- [ ] **Step 1: Write the failing test**

Create `Tests/irisTests/ToolIntentTests.swift`:

```swift
import Testing
@testable import iris

@Suite("ToolIntent augment")
struct ToolIntentTests {
    @Test("adds an optional intent to a tool that has parameters")
    func addsIntentToParamTool() {
        let tool = FunctionDeclaration(
            name: "t", description: "d",
            parameters: Schema(type: "OBJECT",
                               properties: ["x": Schema(type: "STRING", description: "x")],
                               required: ["x"]))
        let out = ToolIntent.augment([tool]).first!
        #expect(out.parameters?.properties?["intent"]?.type == "STRING")
        #expect(out.parameters?.properties?["x"] != nil)      // existing prop preserved
        #expect(out.parameters?.required == ["x"])            // intent NOT added to required
    }

    @Test("wraps a params-less tool in an OBJECT schema carrying intent")
    func wrapsParamlessTool() {
        let tool = FunctionDeclaration(name: "t", description: "d", parameters: nil)
        let out = ToolIntent.augment([tool]).first!
        #expect(out.parameters?.type == "OBJECT")
        #expect(out.parameters?.properties?["intent"]?.type == "STRING")
        #expect(out.parameters?.required?.contains("intent") != true)
    }

    @Test("is idempotent when intent is already present")
    func idempotent() {
        let tool = FunctionDeclaration(
            name: "t", description: "d",
            parameters: Schema(type: "OBJECT",
                               properties: ["intent": Schema(type: "STRING", description: "bespoke")],
                               required: nil))
        let out = ToolIntent.augment([tool]).first!
        #expect(out.parameters?.properties?["intent"]?.description == "bespoke")  // unchanged
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ToolIntentTests 2>&1 | tail -15`
Expected: FAIL — `cannot find 'ToolIntent' in scope`.

- [ ] **Step 3: Implement the helper**

Create `Sources/iris/ToolIntent.swift`:

```swift
import Foundation

enum ToolIntent {
    static let description =
        "One short phrase: why you're making this tool call (shown to the user)."

    /// Returns `tools` with an optional `intent` STRING added to each tool's parameter
    /// schema. Idempotent (a tool that already declares `intent` is left unchanged). A
    /// tool with no parameters gets a fresh OBJECT schema carrying only `intent`.
    /// `intent` is never added to `required`.
    static func augment(_ tools: [FunctionDeclaration]) -> [FunctionDeclaration] {
        tools.map { original in
            var tool = original
            let intentSchema = Schema(type: "STRING", description: description)
            if var params = tool.parameters {
                var props = params.properties ?? [:]
                if props["intent"] == nil {
                    props["intent"] = intentSchema
                    params.properties = props
                    tool.parameters = params
                }
            } else {
                tool.parameters = Schema(type: "OBJECT", properties: ["intent": intentSchema])
            }
            return tool
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter ToolIntentTests 2>&1 | tail -15`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/ToolIntent.swift Tests/irisTests/ToolIntentTests.swift
git commit -m "feat(tools): ToolIntent.augment adds optional intent to any tool (#31)"
```

---

### Task 2: Wire the augmenter in; remove run_command's hand-added intent

**Files:**
- Modify: `Sources/iris/iris.swift` (apply augment before `fireBeforeToolSelection`)
- Modify: `Sources/iris/ToolExecutor.swift` (remove `run_command`'s `intent` property)
- Modify: `Tests/irisTests/RunCommandIntentTests.swift` (assert against the augmented list)

**Interfaces:**
- Consumes: `ToolIntent.augment(_:)` (Task 1).

- [ ] **Step 1: Apply the augmenter in `iris.swift`**

In `Sources/iris/iris.swift`, find the line `let toolSelectionDecision = await HookManager.shared.fireBeforeToolSelection(tools: toolsList, useSandbox: hooksSandbox)`. Immediately **above** it, insert:

```swift
        // Offer an optional `intent` on every tool so the model can attach a one-line
        // rationale the UI shows next to each call (#31). Central + idempotent, so any
        // future tool is covered automatically.
        toolsList = ToolIntent.augment(toolsList)
```

- [ ] **Step 2: Remove `run_command`'s hand-added intent**

In `Sources/iris/ToolExecutor.swift`, in the `run_command` declaration, change the `properties` block from:

```swift
                properties: [
                    "command": Schema(type: "STRING", description: "The command to run in bash/zsh"),
                    "intent": Schema(type: "STRING", description: "One short phrase: why you're running this command (shown to the user; keep it under ~8 words).")
                ],
                required: ["command"]
```

to:

```swift
                properties: [
                    "command": Schema(type: "STRING", description: "The command to run in bash/zsh")
                ],
                required: ["command"]
```

- [ ] **Step 3: Update #27's test to the augmented path**

In `Tests/irisTests/RunCommandIntentTests.swift`, replace the `schemaHasOptionalIntent` test with:

```swift
    @Test("run_command exposes an optional intent property after augmentation")
    func schemaHasOptionalIntent() async {
        let tools = ToolIntent.augment(await ToolExecutor.shared.getTools())
        let runCmd = tools.first { $0.name == "run_command" }
        #expect(runCmd?.parameters?.properties?["intent"] != nil)
        #expect(runCmd?.parameters?.required?.contains("intent") != true)
    }
```

Leave the `executeIgnoresIntent` test unchanged (the executor still ignores `intent`).

- [ ] **Step 4: Build**

Run: `swift build 2>&1 | tail -6`
Expected: `Build complete!`

- [ ] **Step 5: Run the affected tests**

Run: `swift test --filter RunCommandIntentTests 2>&1 | tail -6` and `swift test --filter ToolIntentTests 2>&1 | tail -4`
Expected: both suites pass (RunCommandIntentTests 2/2, ToolIntentTests 3/3).

- [ ] **Step 6: Commit**

```bash
git add Sources/iris/iris.swift Sources/iris/ToolExecutor.swift Tests/irisTests/RunCommandIntentTests.swift
git commit -m "feat(tools): inject intent into all tools; drop run_command's bespoke intent (#31)"
```

---

### Task 3: Strengthen and generalize the steering

**Files:**
- Modify: `Sources/iris/assets/SYSTEM.md` (the `## Communicating While Working` section)

**Interfaces:** none.

- [ ] **Step 1: Rewrite the first two paragraphs**

In `Sources/iris/assets/SYSTEM.md`, replace the first two paragraphs of `## Communicating While Working` — from `Before starting multi-step or exploratory work` through `so per-command narration in the chat is\nredundant.` — with:

```markdown
When a turn will involve more than one tool call, or any multi-step work, your
first output — before the first tool call — must be a single sentence stating
what you're about to do and why. One line, up front, then act; don't narrate each
step. Don't leave the user watching a silent "thinking" indicator wondering what
you're chasing. For a single quick action (one read, one edit, a direct answer),
skip the orientation line; no preamble needed.

For every tool call, put its specific rationale in the tool's `intent` field (one
short phrase) rather than as prose between calls — the UI shows that intent next
to the call, so per-call narration in the chat is redundant.
```

Leave the following paragraph (beginning `When a request is genuinely ambiguous`) and the `## Voice` heading unchanged.

- [ ] **Step 2: Confirm the edit**

Run: `grep -n "every tool call\|first output — before the first tool call" Sources/iris/assets/SYSTEM.md`
Expected: both phrases present.

- [ ] **Step 3: Build (bundle still assembles)**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/iris/assets/SYSTEM.md
git commit -m "docs(steering): intent on every tool + firmer plan-declaration (#31)"
```

---

## Notes for the implementer

- `swift test` builds the whole package (MLX/ONNX/llama deps) and can be slow cold; use `--filter <SuiteName>` while iterating.
- `Schema`'s memberwise init allows omitting `properties`/`required`/`description` (existing call sites do this), so `Schema(type: "STRING", description: …)` and `Schema(type: "OBJECT", properties: […])` compile as written.
- Do not touch `ChatView.swift`/`ToolCallParser.swift` — the display path is already generic for any tool's `intent`.
- README: per AGENTS.md, no user-facing README change is needed (intent is an internal steering/UX detail already documented for #27); skip unless you spot an existing tool-transparency section that should mention "all tools."
