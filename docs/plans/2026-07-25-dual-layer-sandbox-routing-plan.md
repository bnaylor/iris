# Dual-Layer Sandbox Routing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route `run_command` per principal — subagents always sandboxed, main agent host-or-sandboxed via a per-conversation → per-workspace → global-default cascade — with `enableSandboxing` reinterpreted as the feature master switch.

**Architecture:** A pure `SandboxPolicy.resolve(...)` computes a `SandboxDecision` from the master switch, principal, the override cascade, and runtime availability. `IrisEngine` (which carries a `Principal`) resolves the decision for each `run_command`, warns once per conversation on a no-runtime fallback, and passes a `useSandbox` flag to `ToolExecutor`, which routes to Piece 1's `SandboxSessionManager` or the host path.

**Tech Stack:** Swift, Swift Concurrency (actors), SwiftUI, Swift Testing (`import Testing`, `@Test`, `#expect`).

## Global Constraints

- `enableSandboxing` is the **feature master switch**: off → all host, no warnings (unchanged legacy behavior); on → dual-layer active.
- Main-agent resolution cascade (highest first): per-conversation override (`Conversation.mainAgentSandbox`, `nil` = inherit) → per-workspace override (`<workspace>/.iris/sandbox.json`, shape `{"mainAgent":"host"|"sandboxed"}`) → global default (`ConfigManager.mainAgentSandboxDefault`, default `host`).
- Subagents are always sandboxed when the master switch is on and a runtime is available; otherwise **warn loudly + run on host** (one system notice per conversation).
- Only `run_command` is routed; `read_file`/`write_file` stay on the host. Vibecop/permission guardrails are unchanged and run before routing.
- Runtime availability = `SandboxingManager.shared.isContainerInstalled`.
- Migration: on first launch after upgrade, if `enableSandboxing == true` and `MAIN_AGENT_SANDBOX_DEFAULT` is unset, seed it to `sandboxed`; fresh installs default to `host`.
- New tests use Swift Testing, matching `Tests/irisTests/SandboxSessionManagerTests.swift`.
- Install stays a Settings/setup-wizard concern; the stale "Run the /sandbox command to install it" error strings are corrected to point at Settings. `/sandbox` is the policy/status command only.

---

### Task 1: `SandboxPolicy` — types, `resolve`, per-workspace override I/O

**Files:**
- Create: `Sources/iris/SandboxPolicy.swift`
- Test: `Tests/irisTests/SandboxPolicyTests.swift`

**Interfaces:**
- Produces:
  - `enum SandboxPref: String, Codable, Sendable { case host, sandboxed }`
  - `enum Principal: Sendable { case main, subagent }`
  - `enum SandboxDecision: Equatable, Sendable { case sandboxed; case host(warnNoRuntime: Bool) }`
  - `enum SandboxPolicy` with:
    - `static func resolve(masterEnabled: Bool, principal: Principal, perConversation: SandboxPref?, perWorkspace: SandboxPref?, globalDefault: SandboxPref, runtimeAvailable: Bool) -> SandboxDecision`
    - `static func perWorkspaceOverride(workspace: String?) -> SandboxPref?`
    - `static func setWorkspaceOverride(_ pref: SandboxPref?, for workspace: String)` (nil clears)

- [ ] **Step 1: Write the failing tests**

Create `Tests/irisTests/SandboxPolicyTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@Suite("SandboxPolicy.resolve")
struct SandboxPolicyResolveTests {
    private func r(master: Bool = true, principal: Principal = .main,
                   conv: SandboxPref? = nil, ws: SandboxPref? = nil,
                   def: SandboxPref = .host, runtime: Bool = true) -> SandboxDecision {
        SandboxPolicy.resolve(masterEnabled: master, principal: principal,
                              perConversation: conv, perWorkspace: ws,
                              globalDefault: def, runtimeAvailable: runtime)
    }

    @Test("master off -> host, no warning, regardless of anything")
    func masterOff() {
        #expect(r(master: false, principal: .subagent) == .host(warnNoRuntime: false))
        #expect(r(master: false, principal: .main, conv: .sandboxed, runtime: true) == .host(warnNoRuntime: false))
    }

    @Test("subagent is always sandboxed when runtime available")
    func subagentSandboxed() {
        #expect(r(principal: .subagent, def: .host) == .sandboxed)
    }

    @Test("subagent with no runtime warns and falls back to host")
    func subagentNoRuntime() {
        #expect(r(principal: .subagent, runtime: false) == .host(warnNoRuntime: true))
    }

    @Test("main defaults to global default when no overrides")
    func mainGlobalDefault() {
        #expect(r(def: .host) == .host(warnNoRuntime: false))
        #expect(r(def: .sandboxed) == .sandboxed)
    }

    @Test("main sandboxed but no runtime warns + host")
    func mainNoRuntime() {
        #expect(r(def: .sandboxed, runtime: false) == .host(warnNoRuntime: true))
    }

    @Test("per-workspace override beats global default")
    func workspaceBeatsGlobal() {
        #expect(r(ws: .sandboxed, def: .host) == .sandboxed)
        #expect(r(ws: .host, def: .sandboxed) == .host(warnNoRuntime: false))
    }

    @Test("per-conversation override beats per-workspace and global")
    func conversationBeatsAll() {
        #expect(r(conv: .host, ws: .sandboxed, def: .sandboxed) == .host(warnNoRuntime: false))
        #expect(r(conv: .sandboxed, ws: .host, def: .host) == .sandboxed)
    }
}

@Suite("SandboxPolicy per-workspace override I/O")
struct SandboxPolicyIOTests {
    private func tempWorkspace() -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("iris-sbx-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    @Test("missing file -> nil")
    func missing() {
        #expect(SandboxPolicy.perWorkspaceOverride(workspace: tempWorkspace()) == nil)
        #expect(SandboxPolicy.perWorkspaceOverride(workspace: nil) == nil)
    }

    @Test("write then read round-trips")
    func roundTrip() {
        let ws = tempWorkspace()
        SandboxPolicy.setWorkspaceOverride(.sandboxed, for: ws)
        #expect(SandboxPolicy.perWorkspaceOverride(workspace: ws) == .sandboxed)
        SandboxPolicy.setWorkspaceOverride(.host, for: ws)
        #expect(SandboxPolicy.perWorkspaceOverride(workspace: ws) == .host)
    }

    @Test("clear removes the override")
    func clear() {
        let ws = tempWorkspace()
        SandboxPolicy.setWorkspaceOverride(.sandboxed, for: ws)
        SandboxPolicy.setWorkspaceOverride(nil, for: ws)
        #expect(SandboxPolicy.perWorkspaceOverride(workspace: ws) == nil)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SandboxPolicy`
Expected: FAIL — `cannot find 'SandboxPolicy' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/iris/SandboxPolicy.swift`:

```swift
import Foundation

/// Whether a principal's `run_command` runs in a sandbox container or on the host.
public enum SandboxPref: String, Codable, Sendable {
    case host
    case sandboxed
}

/// Who is running: the user-facing main agent, or an isolated subagent.
public enum Principal: Sendable {
    case main
    case subagent
}

/// The routing outcome for one command.
public enum SandboxDecision: Equatable, Sendable {
    case sandboxed
    /// Runs on the host. `warnNoRuntime` is true when a sandbox was intended but the runtime
    /// was unavailable (the caller should surface a one-time notice).
    case host(warnNoRuntime: Bool)
}

public enum SandboxPolicy {
    /// Pure resolution — no I/O. See the plan's Global Constraints for the cascade.
    public static func resolve(masterEnabled: Bool,
                               principal: Principal,
                               perConversation: SandboxPref?,
                               perWorkspace: SandboxPref?,
                               globalDefault: SandboxPref,
                               runtimeAvailable: Bool) -> SandboxDecision {
        guard masterEnabled else { return .host(warnNoRuntime: false) }

        let intended: SandboxPref
        switch principal {
        case .subagent:
            intended = .sandboxed
        case .main:
            intended = perConversation ?? perWorkspace ?? globalDefault
        }

        switch intended {
        case .sandboxed:
            return runtimeAvailable ? .sandboxed : .host(warnNoRuntime: true)
        case .host:
            return .host(warnNoRuntime: false)
        }
    }

    // MARK: - Per-workspace override (<workspace>/.iris/sandbox.json)

    private struct WorkspaceConfig: Codable { let mainAgent: SandboxPref }

    private static func url(for workspace: String) -> URL {
        URL(fileURLWithPath: workspace)
            .appendingPathComponent(".iris")
            .appendingPathComponent("sandbox.json")
    }

    public static func perWorkspaceOverride(workspace: String?) -> SandboxPref? {
        guard let workspace,
              let data = try? Data(contentsOf: url(for: workspace)),
              let cfg = try? JSONDecoder().decode(WorkspaceConfig.self, from: data) else {
            return nil
        }
        return cfg.mainAgent
    }

    public static func setWorkspaceOverride(_ pref: SandboxPref?, for workspace: String) {
        let fileURL = url(for: workspace)
        guard let pref else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(WorkspaceConfig(mainAgent: pref)) {
            try? data.write(to: fileURL)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SandboxPolicy`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/SandboxPolicy.swift Tests/irisTests/SandboxPolicyTests.swift
git commit -m "feat(sandbox): SandboxPolicy — resolution cascade + per-workspace override I/O"
```

---

### Task 2: Config `mainAgentSandboxDefault` + migration

**Files:**
- Modify: `Sources/iris/ConfigManager.swift`

**Interfaces:**
- Consumes: `SandboxPref` (Task 1).
- Produces: `ConfigManager.mainAgentSandboxDefault: SandboxPref` (key `MAIN_AGENT_SANDBOX_DEFAULT`, default `host`).

- [ ] **Step 1: Add the property**

After the `sandboxIdleTimeoutMinutes` property block (`ConfigManager.swift:144-146`), add:

```swift
    var mainAgentSandboxDefault: SandboxPref {
        didSet { UserDefaults.standard.set(mainAgentSandboxDefault.rawValue, forKey: "MAIN_AGENT_SANDBOX_DEFAULT") }
    }
```

- [ ] **Step 2: Initialize with migration**

After the `sandboxIdleTimeoutMinutes` init line (`ConfigManager.swift:272`), add. Note `enableSandboxing` is already assigned above (line 269), and `didSet` does NOT fire during `init`, so the seed is persisted with an explicit `UserDefaults.set`:

```swift
        if UserDefaults.standard.object(forKey: "MAIN_AGENT_SANDBOX_DEFAULT") == nil {
            // First run with this key. Preserve the experience of users who already run
            // sandboxed (enableSandboxing on today == sandboxed main agent); fresh installs
            // default to host (the dual-layer model).
            let seeded: SandboxPref = self.enableSandboxing ? .sandboxed : .host
            self.mainAgentSandboxDefault = seeded
            UserDefaults.standard.set(seeded.rawValue, forKey: "MAIN_AGENT_SANDBOX_DEFAULT")
        } else {
            let raw = UserDefaults.standard.string(forKey: "MAIN_AGENT_SANDBOX_DEFAULT") ?? "host"
            self.mainAgentSandboxDefault = SandboxPref(rawValue: raw) ?? .host
        }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/iris/ConfigManager.swift
git commit -m "feat(sandbox): mainAgentSandboxDefault config + migration for existing users"
```

---

### Task 3: `Conversation` fields + `AppState` helpers

**Files:**
- Modify: `Sources/iris/AppState.swift`

**Interfaces:**
- Consumes: `SandboxPref`, `Principal`, `SandboxDecision`, `SandboxPolicy` (Task 1); `ConfigManager.mainAgentSandboxDefault` (Task 2).
- Produces:
  - `Conversation.mainAgentSandbox: SandboxPref?` (default `nil`), `Conversation.isSubagent: Bool` (default `false`)
  - `AppState.createNewConversation(id: UUID = UUID(), isSubagent: Bool = false)`
  - `AppState.setMainAgentSandbox(for id: UUID, pref: SandboxPref?)`
  - `AppState.effectiveMainSandboxed(_ conv: Conversation) -> Bool`

- [ ] **Step 1: Add the two `Conversation` fields**

In `struct Conversation` (`AppState.swift:24`), add after `goalIterationCount`:

```swift
    var mainAgentSandbox: SandboxPref? = nil
    var isSubagent: Bool = false
```

Add `mainAgentSandbox, isSubagent` to the `CodingKeys` enum (`AppState.swift:45`), and in `init(from:)` (after the `messageCountSinceReflection` decode) add backward-compatible decodes:

```swift
        mainAgentSandbox = try container.decodeIfPresent(SandboxPref.self, forKey: .mainAgentSandbox)
        isSubagent = try container.decodeIfPresent(Bool.self, forKey: .isSubagent) ?? false
```

(The memberwise `init(...)` at `AppState.swift:33` does not list these; they keep their defaults, which is fine — call sites don't set them via that init.)

- [ ] **Step 2: Thread `isSubagent` through `createNewConversation`**

Change `createNewConversation` (`AppState.swift:165`):

```swift
    func createNewConversation(id: UUID = UUID(), isSubagent: Bool = false) {
        var newConv = Conversation(id: id, title: "New Conversation")
        newConv.isSubagent = isSubagent
        conversations.append(newConv)
        selectedConversationId = newConv.id
        saveConversations()

        Task {
            _ = await HookManager.shared.fireSessionStart(conversationId: newConv.id)
        }
    }
```

- [ ] **Step 3: Add the setter and effective-state helper**

Add these methods to `AppState` (near `setWorkspace`, `AppState.swift:198`):

```swift
    func setMainAgentSandbox(for conversationId: UUID, pref: SandboxPref?) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].mainAgentSandbox = pref
            saveConversations()
        }
    }

    /// The resolved main-agent sandbox state for a conversation, used by the sidebar toggle's
    /// checkmark. Subagent conversations are not user-togglable, so this is only meaningful for
    /// main conversations.
    func effectiveMainSandboxed(_ conv: Conversation) -> Bool {
        let decision = SandboxPolicy.resolve(
            masterEnabled: ConfigManager.shared.enableSandboxing,
            principal: .main,
            perConversation: conv.mainAgentSandbox,
            perWorkspace: SandboxPolicy.perWorkspaceOverride(workspace: conv.workspacePath),
            globalDefault: ConfigManager.shared.mainAgentSandboxDefault,
            runtimeAvailable: SandboxingManager.shared.isContainerInstalled)
        return decision == .sandboxed
    }
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/AppState.swift
git commit -m "feat(sandbox): Conversation main-agent-sandbox + isSubagent fields, AppState helpers"
```

---

### Task 4: `IrisEngine.principal` + `SubagentManager` wiring

**Files:**
- Modify: `Sources/iris/iris.swift` (`IrisEngine.init`)
- Modify: `Sources/iris/SubagentManager.swift`

**Interfaces:**
- Consumes: `Principal` (Task 1); `createNewConversation(id:isSubagent:)` (Task 3).
- Produces: `IrisEngine.principal: Principal`.

- [ ] **Step 1: Add `principal` to `IrisEngine`**

In `iris.swift`, add a stored property near the top of `actor IrisEngine` (by `var modelTier`, ~line 11):

```swift
    let principal: Principal
```

Change the initializer (`iris.swift:17`) to accept it with a `.main` default:

```swift
    init(state: AppState, tier: ModelTier = .medium, principal: Principal = .main) {
        self.state = state
        self.modelTier = tier
        self.principal = principal
        systemPrompt = nil
    }
```

(`AppState.swift:105`'s `IrisEngine(state: self)` keeps the `.main` default — no change needed there.)

- [ ] **Step 2: Mark subagent conversations and engine**

In `SubagentManager.swift`, change the conversation creation (line 28) to pass `isSubagent: true`:

```swift
            appState.createNewConversation(id: subagentId, isSubagent: true)
```

And the engine construction (line 41):

```swift
        let engine = IrisEngine(state: appState, tier: tier, principal: .subagent)
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/iris/iris.swift Sources/iris/SubagentManager.swift
git commit -m "feat(sandbox): tag IrisEngine with Principal; mark subagent conversations"
```

---

### Task 5: Routing — engine resolves the decision, warns once; ToolExecutor honors `useSandbox`

**Files:**
- Modify: `Sources/iris/iris.swift` (`executeFunctionCall`, `executeToolWithHooks`, add a warned set)
- Modify: `Sources/iris/ToolExecutor.swift` (`execute`, `runCommand`, error strings)

**Interfaces:**
- Consumes: `SandboxPolicy.resolve`, `SandboxPolicy.perWorkspaceOverride`, `SandboxDecision`, `IrisEngine.principal` (Tasks 1, 4); `ConfigManager.mainAgentSandboxDefault` (Task 2).

**Note:** Wiring — verified by build. Piece 1's `SandboxSessionManager` is unchanged.

- [ ] **Step 1: Add a per-conversation warned set to the engine**

In `actor IrisEngine`, add a stored property (near `principal`):

```swift
    /// Conversations already shown the "no sandbox runtime" fallback notice (deduped).
    private var warnedNoRuntime: Set<UUID> = []
```

- [ ] **Step 2: Resolve the decision in `executeFunctionCall` and thread it through**

`executeFunctionCall` (`iris.swift:496`) already has `conversationId` and `workspacePath`. In the branch that calls `executeToolWithHooks` (the two call sites at ~`:598` and `:603`), compute `useSandbox` for `run_command` first. Add this helper method to `IrisEngine`:

```swift
    /// Resolves whether a run_command for this conversation should be sandboxed, emitting the
    /// no-runtime fallback notice once per conversation. Non-run_command tools return false.
    private func resolveUseSandbox(toolName: String, conversationId: UUID, workspacePath: String?) async -> Bool {
        guard toolName == "run_command" else { return false }
        let localState = state
        let perConv = await MainActor.run {
            localState?.conversations.first(where: { $0.id == conversationId })?.mainAgentSandbox
        }
        let decision = SandboxPolicy.resolve(
            masterEnabled: ConfigManager.shared.enableSandboxing,
            principal: principal,
            perConversation: perConv,
            perWorkspace: SandboxPolicy.perWorkspaceOverride(workspace: workspacePath),
            globalDefault: ConfigManager.shared.mainAgentSandboxDefault,
            runtimeAvailable: SandboxingManager.shared.isContainerInstalled)

        switch decision {
        case .sandboxed:
            return true
        case .host(let warn):
            if warn, !warnedNoRuntime.contains(conversationId) {
                warnedNoRuntime.insert(conversationId)
                await pushToUI(role: .system,
                               text: "[sandbox] No container runtime available — running on the host WITHOUT isolation. Install it in Iris Settings → Sandboxing to enable sandboxing.",
                               conversationId: conversationId)
            }
            return false
        }
    }
```

Then update the two `executeToolWithHooks` calls in `executeFunctionCall` to compute and pass `useSandbox`. Replace the approval branch (`:596-601`) and the else branch (`:603`) so each computes it. Concretely, before the `if needsApproval {` block, add:

```swift
            let useSandbox = await resolveUseSandbox(toolName: functionCall.name, conversationId: conversationId, workspacePath: workspacePath)
```

and change both `executeToolWithHooks(...)` calls to pass `useSandbox: useSandbox`:

```swift
                    result = await executeToolWithHooks(name: functionCall.name, args: functionCall.args, cwd: workspacePath, conversationId: conversationId, useSandbox: useSandbox)
```
```swift
                result = await executeToolWithHooks(name: functionCall.name, args: functionCall.args, cwd: workspacePath, conversationId: conversationId, useSandbox: useSandbox)
```

- [ ] **Step 3: Thread `useSandbox` through `executeToolWithHooks` and the executor**

Change `executeToolWithHooks` signature (`iris.swift:610`):

```swift
    private func executeToolWithHooks(name: String, args: [String: JSONValue], cwd: String?, conversationId: UUID?, useSandbox: Bool) async -> String {
```

Change its `executor.execute` call (`iris.swift:628`):

```swift
        var result = await executor.execute(name: name, args: execArgs, cwd: cwd, conversationId: conversationId, useSandbox: useSandbox)
```

- [ ] **Step 4: `ToolExecutor` — accept and honor `useSandbox`, fix stale strings**

In `ToolExecutor.swift`, change `execute` (`:78`) to add the parameter and pass it to `runCommand`:

```swift
    func execute(name: String, args: [String: JSONValue], cwd: String? = nil, conversationId: UUID? = nil, useSandbox: Bool = false) async -> String {
```
```swift
        case "run_command":
            guard let command = args["command"]?.stringValue else { return "Error: Missing command" }
            return await runCommand(command, cwd: cwd, conversationId: conversationId, useSandbox: useSandbox)
```

Change `runCommand` (`:108`) to key off `useSandbox` instead of `ConfigManager.shared.enableSandboxing`, and fix the two stale error strings. The delegation branch:

```swift
    private func runCommand(_ command: String, cwd: String?, conversationId: UUID? = nil, useSandbox: Bool = false) async -> String {
        if useSandbox, let conversationId {
            guard SandboxingManager.shared.isContainerInstalled else {
                return "Error: sandboxing is on but the container runtime isn't installed. Open Iris Settings → Sandboxing to install it, or turn sandboxing off."
            }
            let expandedCwd = cwd.map { ($0 as NSString).expandingTildeInPath }
            return await SandboxSessionManager.shared.run(command: command, conversationId: conversationId, workspace: expandedCwd)
        }
        return await withCheckedContinuation { continuation in
            // ...existing body...
```

Inside the `withCheckedContinuation` body, change the inner sandbox branch (`:120`) and the setup-hint guard (`:160`) to use `useSandbox` instead of `ConfigManager.shared.enableSandboxing`, and fix the string at `:122`:

```swift
            if useSandbox {
                guard SandboxingManager.shared.isContainerInstalled else {
                    continuation.resume(returning: "Error: sandboxing is on but the container runtime isn't installed. Open Iris Settings → Sandboxing to install it, or turn sandboxing off.")
                    return
                }
                // ...existing --rm construction...
```
```swift
                if useSandbox, proc.terminationStatus != 0,
                   let hint = Self.sandboxSetupHint(for: result) {
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add Sources/iris/iris.swift Sources/iris/ToolExecutor.swift
git commit -m "feat(sandbox): principal-based routing in the engine; ToolExecutor honors useSandbox"
```

---

### Task 6: `/sandbox` command (status + per-workspace override)

**Files:**
- Modify: `Sources/iris/AppState.swift` (`sendMessage` dispatch + a handler)

**Interfaces:**
- Consumes: `SandboxPolicy`, `SandboxPref` (Task 1); `emitCommandOutput(_:format:to:)` (existing); `effectiveMainSandboxed` (Task 3).

**Note:** Wiring — verified by build. Reuses the existing command-output sugar and the `.command` markdown render path.

- [ ] **Step 1: Dispatch `/sandbox` in `sendMessage`**

In `AppState.sendMessage`, add a branch in the command chain (e.g. right after the `/skills` branch at `AppState.swift:249`):

```swift
        } else if trimmed == "/sandbox" || trimmed.hasPrefix("/sandbox ") {
            handleSandboxCommand(trimmed, convId: convId)
            return
```

- [ ] **Step 2: Implement the handler**

Add to `AppState`:

```swift
    private func handleSandboxCommand(_ trimmed: String, convId: UUID) {
        guard let conv = conversations.first(where: { $0.id == convId }) else { return }
        let args = trimmed.dropFirst("/sandbox".count).trimmingCharacters(in: .whitespaces)

        // Sub-command: /sandbox workspace <host|sandboxed|clear>
        if args.hasPrefix("workspace") {
            let value = args.dropFirst("workspace".count).trimmingCharacters(in: .whitespaces).lowercased()
            guard let ws = conv.workspacePath else {
                emitCommandOutput("No workspace is linked to this conversation. Link one first (right-click → Link to Workspace…).", format: .markdown, to: convId)
                return
            }
            switch value {
            case "host": SandboxPolicy.setWorkspaceOverride(.host, for: ws)
            case "sandboxed": SandboxPolicy.setWorkspaceOverride(.sandboxed, for: ws)
            case "clear": SandboxPolicy.setWorkspaceOverride(nil, for: ws)
            default:
                emitCommandOutput("Usage: `/sandbox workspace host|sandboxed|clear`", format: .markdown, to: convId)
                return
            }
            emitCommandOutput("Per-workspace main-agent sandbox set to **\(value)** for `\(ws)`.", format: .markdown, to: convId)
            return
        }

        // No arg (or anything else): report status.
        let master = ConfigManager.shared.enableSandboxing
        let runtime = SandboxingManager.shared.isContainerInstalled
        let effective = effectiveMainSandboxed(conv)
        let source: String
        if conv.mainAgentSandbox != nil { source = "this conversation" }
        else if SandboxPolicy.perWorkspaceOverride(workspace: conv.workspacePath) != nil { source = "workspace `.iris/sandbox.json`" }
        else { source = "global default" }

        let body = """
        **Sandbox policy**

        - Feature master switch: **\(master ? "on" : "off")**
        - Container runtime installed: **\(runtime ? "yes" : "no")**
        - Main agent (this conversation): **\(effective ? "sandboxed" : "host")** — from \(source)
        - Global default: **\(ConfigManager.shared.mainAgentSandboxDefault.rawValue)**
        - Subagents: **always sandboxed** when the master switch is on and a runtime is present

        Set a per-workspace default with `/sandbox workspace host|sandboxed|clear`.
        """
        emitCommandOutput(body, format: .markdown, to: convId)
    }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/iris/AppState.swift
git commit -m "feat(sandbox): /sandbox status + per-workspace override command"
```

---

### Task 7: UI — Settings picker + relabel; sidebar toggle

**Files:**
- Modify: `Sources/iris/SettingsView.swift`
- Modify: `Sources/iris/ChatView.swift`

**Interfaces:**
- Consumes: `ConfigManager.mainAgentSandboxDefault`, `SandboxPref` (Tasks 1, 2); `effectiveMainSandboxed`, `setMainAgentSandbox`, `Conversation.isSubagent` (Task 3).

**Note:** SwiftUI; verified by build + manual smoke.

- [ ] **Step 1: Settings — relabel master + add main-agent default picker**

In `SettingsView.swift`, relabel the master toggle (`:431`) and, inside the `if config.enableSandboxing {` block (`:450`), add a picker. Change the toggle label:

```swift
                    Toggle("Enable sandboxing", isOn: $config.enableSandboxing)
```

and inside the `if config.enableSandboxing {` block, above the `TextField("Sandbox Image"...)`, add:

```swift
                        Picker("Main agent (default)", selection: $config.mainAgentSandboxDefault) {
                            Text("Host").tag(SandboxPref.host)
                            Text("Sandboxed").tag(SandboxPref.sandboxed)
                        }
                        .help("Where the main agent runs by default. Subagents are always sandboxed. Override per workspace via /sandbox, or per conversation via the sidebar right-click menu.")
```

- [ ] **Step 2: Sidebar — add the toggle under "Link to Workspace…"**

In `ChatView.swift`, in the conversation `contextMenu` (`:38-52`), directly after the `Button("Link to Workspace...")` item, add:

```swift
                                if !conv.isSubagent {
                                    Toggle("Sandbox main agent", isOn: Binding(
                                        get: { state.effectiveMainSandboxed(conv) },
                                        set: { state.setMainAgentSandbox(for: conv.id, pref: $0 ? .sandboxed : .host) }
                                    ))
                                    .disabled(!ConfigManager.shared.enableSandboxing)
                                }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Manual smoke test**

1. Settings: toggle "Enable sandboxing" on; confirm the "Main agent (default)" picker appears; set it to Host.
2. New conversation, link a workspace. Right-click → confirm "Sandbox main agent" appears unchecked (global default host). Check it; run a command → verify it runs sandboxed (a fresh `iris-*` container for that conversation). Uncheck → command runs on host.
3. Spawn a subagent (a task that dispatches one) → confirm its commands run sandboxed regardless of the main setting, and the subagent conversation's right-click menu does NOT show the toggle.
4. `/sandbox` → confirm the status report; `/sandbox workspace sandboxed` then `/sandbox` → confirm source now says workspace.
5. With the runtime uninstalled + master on + main sandboxed: run a command → confirm the one-time `[sandbox] No container runtime…` notice, then host execution; a second command in the same conversation does not repeat the notice.

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/SettingsView.swift Sources/iris/ChatView.swift
git commit -m "feat(sandbox): settings main-agent-default picker + sidebar sandbox toggle"
```

---

## Self-Review

**Spec coverage:**
- Master switch reinterpretation → Task 5 (routing keys off resolved decision; master off → host) + Task 7 (relabel). ✓
- Subagents always sandboxed → Task 1 (`resolve`) + Task 4 (`.subagent` principal). ✓
- Main-agent cascade (conversation → workspace → global) → Task 1 (`resolve`) + Task 3 (fields/helpers). ✓
- No-runtime warn+host, deduped per conversation → Task 5 (`resolveUseSandbox` + `warnedNoRuntime`). ✓
- Migration seeding `mainAgentSandboxDefault` → Task 2. ✓
- Per-workspace `.iris/sandbox.json` → Task 1 (I/O) + Task 6 (`/sandbox workspace`). ✓
- `/sandbox` status/policy command + fixed stale strings → Task 6 + Task 5 (strings). ✓
- UI: settings picker + relabel, sidebar toggle (checkmark = effective, hidden for subagents, disabled when master off) → Task 7. ✓
- `read_file`/`write_file` unchanged; guardrails unchanged → only `run_command` computes `useSandbox` (Task 5); no other tool paths touched. ✓
- Piece 1 mechanism unchanged → `SandboxSessionManager` not modified. ✓

**Placeholder scan:** No TBD/TODO; all code and tests concrete.

**Type consistency:** `SandboxPref`, `Principal`, `SandboxDecision`, `SandboxPolicy.resolve(masterEnabled:principal:perConversation:perWorkspace:globalDefault:runtimeAvailable:)`, `perWorkspaceOverride(workspace:)`, `setWorkspaceOverride(_:for:)`, `mainAgentSandboxDefault`, `mainAgentSandbox`, `isSubagent`, `effectiveMainSandboxed(_:)`, `setMainAgentSandbox(for:pref:)`, `principal`, `useSandbox`, `resolveUseSandbox(toolName:conversationId:workspacePath:)` are used identically across tasks.
