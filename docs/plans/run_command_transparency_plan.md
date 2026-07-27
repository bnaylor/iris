# run_command Transparency Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Declutter tool-call presentation — carry per-command rationale in a new optional `intent` field on `run_command`, and render tool calls as clean grouped rows whose collapsed twisty is a live "current intent" status line.

**Architecture:** Data-light. The model supplies an optional `intent` per `run_command`; it rides through `args` untouched by execution (the executor reads only `command`) and is already serialized into the existing `[TOOL_CALL]` system message, so the UI parses it with no engine plumbing changes. A pure parser feeds the SwiftUI rendering.

**Tech Stack:** Swift 6 (language mode v6), SwiftUI + AppKit, swift-testing (`import Testing`).

## Global Constraints

- `intent` is added to `run_command` only, as an **optional** parameter (not in `required`). No other tool gets it.
- The executor reads only `args["command"]`; `intent` is ignored at runtime.
- The `[TOOL_CALL]` message format is unchanged (`"[TOOL_CALL]\n" + prettyJSON(of {name, args})`); `intent` appears automatically because it's inside `args`.
- Parser rule: require the `"[TOOL_CALL]\n"` prefix; decode JSON; read `name` (required), and from `args` read `command` and `intent` (both optional). Malformed JSON or missing `name` → `nil`. An empty-string `intent` is treated as `nil`.
- No change to `groupedMessages` — #23 is fixed behaviorally (rationale moves out of interleaved agent bubbles).
- The raw JSON stays in the stored message content (copy/export unaffected); it is simply not shown inline.
- Tests use swift-testing (`import Testing`, `@Suite`, `@Test`, `#expect`), `@testable import iris`, in `Tests/irisTests/`.

---

### Task 1: Add optional `intent` to the run_command schema

**Files:**
- Modify: `Sources/iris/ToolExecutor.swift` (run_command `FunctionDeclaration`, ~lines 8-18)
- Test: `Tests/irisTests/RunCommandIntentTests.swift`

**Interfaces:**
- Produces: `run_command`'s parameter schema now has an optional `"intent"` STRING property. `ToolExecutor.shared.getTools() async -> [FunctionDeclaration]` and `execute(name:args:cwd:conversationId:useSandbox:) async -> String` are unchanged in signature.

- [ ] **Step 1: Write the failing test**

Create `Tests/irisTests/RunCommandIntentTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@Suite("run_command intent")
struct RunCommandIntentTests {
    @Test("run_command schema exposes an optional intent property")
    func schemaHasOptionalIntent() async {
        let tools = await ToolExecutor.shared.getTools()
        let runCmd = tools.first { $0.name == "run_command" }
        #expect(runCmd != nil)
        #expect(runCmd?.parameters?.properties?["intent"] != nil)
        #expect(runCmd?.parameters?.required?.contains("intent") != true)
    }

    @Test("execute runs the command and ignores intent")
    func executeIgnoresIntent() async {
        let result = await ToolExecutor.shared.execute(
            name: "run_command",
            args: ["command": .string("echo transparency_ok"), "intent": .string("verifying")],
            useSandbox: false)
        #expect(result.contains("transparency_ok"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter RunCommandIntentTests 2>&1 | tail -15`
Expected: FAIL — the `intent` property assertion fails (schema doesn't have it yet).

- [ ] **Step 3: Add the `intent` property**

In `Sources/iris/ToolExecutor.swift`, in the `run_command` declaration, replace the `properties`/`required` block:

```swift
                properties: [
                    "command": Schema(type: "STRING", description: "The command to run in bash/zsh")
                ],
                required: ["command"]
```

with:

```swift
                properties: [
                    "command": Schema(type: "STRING", description: "The command to run in bash/zsh"),
                    "intent": Schema(type: "STRING", description: "One short phrase: why you're running this command (shown to the user; keep it under ~8 words).")
                ],
                required: ["command"]
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter RunCommandIntentTests 2>&1 | tail -15`
Expected: PASS (2 tests). (`echo transparency_ok` runs on the host since `useSandbox: false`.)

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/ToolExecutor.swift Tests/irisTests/RunCommandIntentTests.swift
git commit -m "feat(tools): optional intent field on run_command (#27)"
```

---

### Task 2: `ToolCallParser` pure helper

**Files:**
- Create: `Sources/iris/ToolCallParser.swift`
- Test: `Tests/irisTests/ToolCallParserTests.swift`

**Interfaces:**
- Produces:
  - `struct ToolCallDisplay: Equatable { let name: String; let command: String?; let intent: String? }`
  - `enum ToolCallParser { static func parse(_ messageText: String) -> ToolCallDisplay? }`

- [ ] **Step 1: Write the failing test**

Create `Tests/irisTests/ToolCallParserTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@Suite("ToolCallParser")
struct ToolCallParserTests {
    private func msg(_ json: String) -> String { "[TOOL_CALL]\n" + json }

    @Test("run_command with command and intent")
    func withIntent() {
        let d = ToolCallParser.parse(msg(#"{"name":"run_command","args":{"command":"npm test","intent":"check the fix"}}"#))
        #expect(d == ToolCallDisplay(name: "run_command", command: "npm test", intent: "check the fix"))
    }

    @Test("run_command without intent")
    func noIntent() {
        let d = ToolCallParser.parse(msg(#"{"name":"run_command","args":{"command":"ls"}}"#))
        #expect(d?.command == "ls")
        #expect(d?.intent == nil)
    }

    @Test("non-run_command tool parses name, no command")
    func otherTool() {
        let d = ToolCallParser.parse(msg(#"{"name":"read_file","args":{"path":"/tmp/x"}}"#))
        #expect(d?.name == "read_file")
        #expect(d?.command == nil)
    }

    @Test("non-tool-call text returns nil")
    func notToolCall() {
        #expect(ToolCallParser.parse("Auto-continuing goal loop (iteration 2)...") == nil)
    }

    @Test("malformed JSON returns nil")
    func malformed() {
        #expect(ToolCallParser.parse(msg("{not json")) == nil)
    }

    @Test("empty intent is treated as nil")
    func emptyIntent() {
        let d = ToolCallParser.parse(msg(#"{"name":"run_command","args":{"command":"ls","intent":""}}"#))
        #expect(d?.intent == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ToolCallParserTests 2>&1 | tail -15`
Expected: FAIL — `cannot find 'ToolCallParser' in scope`.

- [ ] **Step 3: Implement the parser**

Create `Sources/iris/ToolCallParser.swift`:

```swift
import Foundation

struct ToolCallDisplay: Equatable {
    let name: String
    let command: String?   // run_command only
    let intent: String?
}

enum ToolCallParser {
    static let prefix = "[TOOL_CALL]\n"

    /// Parse a system message into displayable tool-call fields. Returns nil for
    /// non-tool-call text or malformed JSON.
    static func parse(_ messageText: String) -> ToolCallDisplay? {
        guard messageText.hasPrefix(prefix) else { return nil }
        let json = String(messageText.dropFirst(prefix.count))
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = dict["name"] as? String else { return nil }
        let args = dict["args"] as? [String: Any]
        let command = args?["command"] as? String
        let intentRaw = args?["intent"] as? String
        let intent = (intentRaw?.isEmpty == false) ? intentRaw : nil
        return ToolCallDisplay(name: name, command: command, intent: intent)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter ToolCallParserTests 2>&1 | tail -15`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/ToolCallParser.swift Tests/irisTests/ToolCallParserTests.swift
git commit -m "feat(ui): pure parser for tool-call display fields (#27)"
```

---

### Task 3: Clean tool-call rows + grouped twisty with live current-intent

**Files:**
- Modify: `Sources/iris/ChatView.swift` — `SystemMessageContent` (~lines 613-667) and `SystemGroupView` (~lines 569-611)
- Test: none (SwiftUI rendering; GUI-verified in Step 5)

**Interfaces:**
- Consumes: `ToolCallParser.parse(_:) -> ToolCallDisplay?`, `ToolCallDisplay` (Task 2).

- [ ] **Step 1: Replace the tool-call branch in `SystemMessageContent`**

In `Sources/iris/ChatView.swift`, replace the whole `body` of `SystemMessageContent` (the `if text.hasPrefix("[TOOL_CALL]\n") { … } else { fallbackView }` block, and the now-unused `@State private var isExpanded`) with a parser-driven clean row. Replace from `@State private var isExpanded = false` (the one inside `SystemMessageContent`) through the end of `body`'s tool-call branch, so the struct reads:

```swift
struct SystemMessageContent: View {
    let text: String

    var body: some View {
        if let call = ToolCallParser.parse(text) {
            toolCallRow(call)
        } else {
            fallbackView
        }
    }

    @ViewBuilder
    private func toolCallRow(_ call: ToolCallDisplay) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let command = call.command {
                HStack(spacing: 6) {
                    Text("$").foregroundColor(.secondary)
                    Text(command).foregroundColor(.primary)
                }
                .font(.caption.monospaced())
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundColor(.blue).font(.caption2)
                    Text(call.name).font(.caption.bold()).foregroundColor(.primary)
                }
            }
            if let intent = call.intent {
                Text(intent)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, call.command != nil ? 14 : 0)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }
```

Leave the existing `private var fallbackView: some View { … }` (immediately after `body` in the current file) exactly as-is — the closing brace of the struct stays after it.

- [ ] **Step 2: Update `SystemGroupView` — header count + live collapsed status**

Replace the entire `SystemGroupView` struct with:

```swift
struct SystemGroupView: View {
    let messages: [ChatMessage]
    @State private var isExpanded = false

    private var toolCalls: [ToolCallDisplay] {
        messages.compactMap { ToolCallParser.parse($0.content) }
    }
    private var allToolCalls: Bool { !messages.isEmpty && toolCalls.count == messages.count }

    private var headerText: String {
        if allToolCalls {
            return toolCalls.count == 1 ? "1 command" : "\(toolCalls.count) commands"
        }
        return (messages.count > 1 && isExpanded) ? "System Events (\(messages.count))" : "System Event"
    }

    /// Live "current intent": the most recent tool call's intent (or command / name).
    /// If the last message is a non-tool system line, show that line instead.
    private var collapsedStatus: String? {
        guard let last = messages.last else { return nil }
        if let call = ToolCallParser.parse(last.content) {
            return call.intent ?? call.command ?? call.name
        }
        return last.content
    }

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if messages.count > 1 {
                        Button(action: { withAnimation { isExpanded.toggle() } }) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .foregroundColor(.secondary).frame(width: 14)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Spacer().frame(width: 14)
                    }
                    Image(systemName: "gearshape.fill")
                    Text(headerText)
                }
                .font(.caption.bold())
                .foregroundColor(.secondary)

                if isExpanded || messages.count == 1 {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(messages) { msg in
                            SystemMessageContent(text: msg.content)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.leading, 22)
                } else if let status = collapsedStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, 22)
                }
            }
            Spacer()
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -6`
Expected: `Build complete!`

- [ ] **Step 4: Run the full suite (no regressions in parser/schema)**

Run: `swift test --filter ToolCallParserTests 2>&1 | tail -3` and `swift test --filter RunCommandIntentTests 2>&1 | tail -3`
Expected: both suites still pass.

- [ ] **Step 5: GUI verification (manual — ask the user to run `swift run`)**

Ask the human partner to verify in the running app:
- A `run_command` renders as a clean `$ <command>` row with the intent as a dim caption beneath (no raw-JSON box).
- Several commands in a run collapse into one twisty headed `N commands`; collapsed, it shows the current command's intent and updates as new commands stream; expanding shows every command + intent.
- A non-`run_command` tool shows a simple named row; non-tool system lines (e.g. `[blocked]`, `[sandbox]`) still render.

- [ ] **Step 6: Commit**

```bash
git add Sources/iris/ChatView.swift
git commit -m "feat(ui): clean grouped tool-call rows with live current-intent (#27, #23)"
```

---

### Task 4: Steering — put per-command rationale in `intent`

**Files:**
- Modify: `Sources/iris/assets/SYSTEM.md` (the `## Communicating While Working` section)
- Test: none (prose directive)

**Interfaces:** none.

- [ ] **Step 1: Revise the section**

In `Sources/iris/assets/SYSTEM.md`, replace the first paragraph of `## Communicating While Working` (the paragraph beginning "Before starting multi-step or exploratory work" through "no preamble needed.") with:

```markdown
Before starting multi-step or exploratory work — several tool calls, searching
across the codebase, or open-ended investigation — say what you're about to do
and why in one short line before you start, then proceed. One high-level
declaration up front is enough; don't narrate every step with its own message.
Don't leave the user watching a silent "thinking" indicator wondering what
you're chasing. For quick single-step actions (one read, one edit, a direct
answer), just do them; no preamble needed.

When you run a shell command, put its specific rationale in the `run_command`
`intent` field (one short phrase) rather than as prose between commands — the UI
shows that intent next to the command, so per-command narration in the chat is
redundant.
```

Leave the following paragraph (about ambiguity / clarifying questions) unchanged.

- [ ] **Step 2: Confirm the change is in the shipped asset**

Run: `grep -n "intent" Sources/iris/assets/SYSTEM.md`
Expected: the new `run_command` `intent` guidance line is present.

- [ ] **Step 3: Build (bundle still assembles)**

Run: `swift build 2>&1 | tail -3`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/iris/assets/SYSTEM.md
git commit -m "docs(steering): route per-command rationale into run_command intent (#27)"
```

---

## Notes for the implementer

- `swift test` builds the whole package (MLX/ONNX/llama deps) and can be slow on a cold build; use `--filter <SuiteName>` while iterating.
- Task 3 is the only GUI-verified task; it depends on Task 2's parser. Task 1 and Task 4 are independent of each other and of the UI, but keep the plan order so `intent` exists before the steering references it.
- Do not reintroduce a raw-JSON inline expander — the design intentionally drops it (the JSON remains in the stored message for copy/export).
