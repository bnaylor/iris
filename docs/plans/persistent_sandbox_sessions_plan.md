# Persistent Sandbox Sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace cold `container run --rm`-per-command with one long-lived container per conversation, running each command via `container exec`, to remove per-command boot overhead and persist in-session disk state.

**Architecture:** A `ContainerRuntime` protocol wraps the `container` CLI (real impl + test mock). A `SandboxSessionManager` actor keys sessions on `conversationId`, lazily creating a detached container and exec'ing commands into it, with workspace-change recreate, idle reaping, self-heal retry, and an in-band reset notice. `ToolExecutor.runCommand` delegates to it when sandboxing is on.

**Tech Stack:** Swift, Swift Concurrency (actors, async/await), Swift Testing (`import Testing`, `@Test`, `#expect`), Apple `container` CLI at `/usr/local/bin/container`.

## Global Constraints

- Timing/exec unchanged for the host path (`enableSandboxing` off → `/bin/zsh -c`, untouched).
- Container name: `"iris-\(conversationId.uuidString.lowercased())"`. The `iris-` prefix is the reaping key.
- Keep-alive process: `sleep infinity`. Mount uses identical host/guest path: `"\(ws):\(ws)"`, workdir `ws` (or `/` when no workspace).
- Reused config: `ConfigManager.enableSandboxing`, `ConfigManager.sandboxImage`. New: `sandboxIdleTimeoutMinutes` (default 30, key `SANDBOX_IDLE_TIMEOUT_MINUTES`).
- Output formatting matches today's `runCommand`: `stdout`, then `"\nStderr: " + stderr` if stderr non-empty, `"Success"` if both empty; on non-zero exit, map through `ToolExecutor.sandboxSetupHint(for:)` and return the hint if it matches.
- New tests use Swift Testing, matching `Tests/irisTests/PerformanceProfilerTests.swift`.
- App quit cannot run async teardown (`AppDelegate.applicationWillTerminate` calls `_exit(0)`); orphan cleanup is done at next launch via `reapOrphans()`.

---

### Task 1: `ContainerRuntime` protocol + CLI implementation

**Files:**
- Create: `Sources/iris/ContainerRuntime.swift`

**Interfaces:**
- Produces:
  - `protocol ContainerRuntime: Sendable` with:
    - `func createDetached(name: String, image: String, mount: String?, workdir: String) async throws`
    - `func exec(name: String, workdir: String, command: String) async throws -> (stdout: String, stderr: String, exitCode: Int32)`
    - `func remove(name: String) async`
    - `func list(prefix: String) async -> [String]`
  - `struct CLIContainerRuntime: ContainerRuntime` shelling out to `/usr/local/bin/container`.
  - `enum ContainerRuntimeError: Error { case launchFailed(String); case createFailed(String) }`

**Note:** `CLIContainerRuntime` needs a real VM to run, so it is build-verified only; its logic is exercised manually in Task 7. The unit-testable logic lives in the manager (Task 2) behind this seam.

- [ ] **Step 1: Write the implementation**

Create `Sources/iris/ContainerRuntime.swift`:

```swift
import Foundation

enum ContainerRuntimeError: Error, Equatable {
    case launchFailed(String)
    case createFailed(String)
}

/// Seam over the `container` CLI so `SandboxSessionManager` is unit-testable without a real VM.
protocol ContainerRuntime: Sendable {
    /// `container run -d --name <name> [-v <mount>] -w <workdir> <image> sleep infinity`
    func createDetached(name: String, image: String, mount: String?, workdir: String) async throws
    /// `container exec -w <workdir> <name> bash -c <command>`
    func exec(name: String, workdir: String, command: String) async throws -> (stdout: String, stderr: String, exitCode: Int32)
    /// `container stop <name>` then `container delete <name>` — best-effort, never throws.
    func remove(name: String) async
    /// Names of existing containers whose name starts with `prefix`.
    func list(prefix: String) async -> [String]
}

struct CLIContainerRuntime: ContainerRuntime {
    private let binary = "/usr/local/bin/container"

    private func runCLI(_ args: [String]) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: binary)
            p.arguments = args
            let out = Pipe(); let err = Pipe()
            p.standardOutput = out; p.standardError = err
            p.terminationHandler = { proc in
                let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                cont.resume(returning: (o, e, proc.terminationStatus))
            }
            do { try p.run() } catch { cont.resume(throwing: ContainerRuntimeError.launchFailed(error.localizedDescription)) }
        }
    }

    func createDetached(name: String, image: String, mount: String?, workdir: String) async throws {
        var args = ["run", "-d", "--name", name]
        if let mount { args += ["-v", mount] }
        args += ["-w", workdir, image, "sleep", "infinity"]
        let r = try await runCLI(args)
        if r.exitCode != 0 {
            throw ContainerRuntimeError.createFailed((r.stdout + r.stderr).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func exec(name: String, workdir: String, command: String) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        try await runCLI(["exec", "-w", workdir, name, "bash", "-c", command])
    }

    func remove(name: String) async {
        _ = try? await runCLI(["stop", name])
        _ = try? await runCLI(["delete", name])
    }

    func list(prefix: String) async -> [String] {
        guard let r = try? await runCLI(["list", "-a", "--format", "json"]),
              let data = r.stdout.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        // Each entry's identifier may be under "configuration.id" or top-level "id"/"name".
        return arr.compactMap { entry -> String? in
            if let id = entry["id"] as? String { return id }
            if let cfg = entry["configuration"] as? [String: Any], let id = cfg["id"] as? String { return id }
            return entry["name"] as? String
        }.filter { $0.hasPrefix(prefix) }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/iris/ContainerRuntime.swift
git commit -m "feat(sandbox): ContainerRuntime seam over the container CLI"
```

---

### Task 2: `SandboxSessionManager` actor + lifecycle + reset notice

**Files:**
- Modify: `Sources/iris/ContainerRuntime.swift` (append the manager) or Create: `Sources/iris/SandboxSessionManager.swift`
- Test: `Tests/irisTests/SandboxSessionManagerTests.swift`

Create a new file `Sources/iris/SandboxSessionManager.swift`.

**Interfaces:**
- Consumes: `ContainerRuntime`, `ContainerRuntimeError` (Task 1); `ToolExecutor.sandboxSetupHint(for:)` (existing static).
- Produces:
  - `actor SandboxSessionManager`
  - `init(runtime: ContainerRuntime, image: @escaping @Sendable () -> String)`
  - `static let shared` (uses `CLIContainerRuntime` + `{ ConfigManager.shared.sandboxImage }`)
  - `func run(command: String, conversationId: UUID, workspace: String?) async -> String`
  - `func endSession(_ conversationId: UUID) async`
  - `func endAll() async`
  - `func reapOrphans() async`
  - `func reapIdle(olderThan seconds: TimeInterval, now: Date = Date()) async`
  - `static let namePrefix = "iris-"`
  - test accessor `func hasSession(_ id: UUID) -> Bool`

- [ ] **Step 1: Write the failing tests**

Create `Tests/irisTests/SandboxSessionManagerTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

/// Records calls and lets tests script exec results / failures.
final class MockRuntime: ContainerRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var created: [String] = []
    private(set) var removed: [String] = []
    private(set) var execCount = 0
    var existing: [String] = []                 // returned by list()
    var execResult: (String, String, Int32) = ("ok", "", 0)
    var failNextExec = false                     // throw once, then succeed

    func createDetached(name: String, image: String, mount: String?, workdir: String) async throws {
        lock.lock(); created.append(name); lock.unlock()
    }
    func exec(name: String, workdir: String, command: String) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        lock.lock(); execCount += 1; let fail = failNextExec; failNextExec = false; let r = execResult; lock.unlock()
        if fail { throw ContainerRuntimeError.launchFailed("boom") }
        return r
    }
    func remove(name: String) async { lock.lock(); removed.append(name); lock.unlock() }
    func list(prefix: String) async -> [String] { lock.lock(); defer { lock.unlock() }; return existing.filter { $0.hasPrefix(prefix) } }

    var createdCount: Int { lock.lock(); defer { lock.unlock() }; return created.count }
    var removedNames: [String] { lock.lock(); defer { lock.unlock() }; return removed }
}

@Suite("SandboxSessionManager")
struct SandboxSessionManagerTests {
    private func mgr(_ runtime: ContainerRuntime) -> SandboxSessionManager {
        SandboxSessionManager(runtime: runtime, image: { "ubuntu:latest" })
    }

    @Test("first command lazily creates exactly one container")
    func lazyCreate() async {
        let rt = MockRuntime()
        let m = mgr(rt)
        let id = UUID()
        _ = await m.run(command: "echo hi", conversationId: id, workspace: "/ws")
        #expect(rt.createdCount == 1)
        #expect(await m.hasSession(id))
    }

    @Test("concurrent first commands still create exactly one container")
    func concurrentCreateOnce() async {
        let rt = MockRuntime()
        let m = mgr(rt)
        let id = UUID()
        await withTaskGroup(of: Void.self) { g in
            for _ in 0..<8 { g.addTask { _ = await m.run(command: "echo", conversationId: id, workspace: "/ws") } }
            await g.waitForAll()
        }
        #expect(rt.createdCount == 1)
    }

    @Test("second command reuses the container (no new create)")
    func reuse() async {
        let rt = MockRuntime()
        let m = mgr(rt)
        let id = UUID()
        _ = await m.run(command: "a", conversationId: id, workspace: "/ws")
        _ = await m.run(command: "b", conversationId: id, workspace: "/ws")
        #expect(rt.createdCount == 1)
        #expect(rt.execCount == 2)
    }

    @Test("changing workspace removes old container and creates a new one")
    func workspaceChange() async {
        let rt = MockRuntime()
        let m = mgr(rt)
        let id = UUID()
        _ = await m.run(command: "a", conversationId: id, workspace: "/ws1")
        _ = await m.run(command: "b", conversationId: id, workspace: "/ws2")
        #expect(rt.createdCount == 2)
        #expect(rt.removedNames.count == 1)
    }

    @Test("output matches host formatting: stderr labeled, empty -> Success")
    func formatting() async {
        let rt = MockRuntime()
        rt.execResult = ("", "", 0)
        let m = mgr(rt)
        let out = await m.run(command: "x", conversationId: UUID(), workspace: nil)
        #expect(out == "Success")

        let rt2 = MockRuntime()
        rt2.execResult = ("hello", "warn", 0)
        let m2 = mgr(rt2)
        let out2 = await m2.run(command: "x", conversationId: UUID(), workspace: nil)
        #expect(out2 == "hello\nStderr: warn")
    }

    @Test("endSession removes the container; next run recreates")
    func endSession() async {
        let rt = MockRuntime()
        let m = mgr(rt)
        let id = UUID()
        _ = await m.run(command: "a", conversationId: id, workspace: "/ws")
        await m.endSession(id)
        #expect(!(await m.hasSession(id)))
        #expect(rt.removedNames.count == 1)
        _ = await m.run(command: "b", conversationId: id, workspace: "/ws")
        #expect(rt.createdCount == 2)
    }

    @Test("reapOrphans removes every iris- prefixed container")
    func reapOrphans() async {
        let rt = MockRuntime()
        rt.existing = ["iris-aaa", "iris-bbb", "other-ccc"]
        let m = mgr(rt)
        await m.reapOrphans()
        #expect(rt.removedNames.sorted() == ["iris-aaa", "iris-bbb"])
    }

    @Test("reapIdle removes only stale sessions; next run recreates with a reset notice")
    func reapIdleAndNotice() async {
        let rt = MockRuntime()
        let m = mgr(rt)
        let id = UUID()
        _ = await m.run(command: "a", conversationId: id, workspace: "/ws")
        // Everything is stale relative to a far-future 'now'.
        await m.reapIdle(olderThan: 60, now: Date().addingTimeInterval(3600))
        #expect(!(await m.hasSession(id)))
        let out = await m.run(command: "b", conversationId: id, workspace: "/ws")
        #expect(out.hasPrefix("[sandbox]"))
        #expect(out.contains("reclaimed"))
    }

    @Test("first-ever creation emits no reset notice")
    func firstCreateNoNotice() async {
        let rt = MockRuntime()
        let m = mgr(rt)
        let out = await m.run(command: "a", conversationId: UUID(), workspace: "/ws")
        #expect(!out.hasPrefix("[sandbox]"))
    }

    @Test("exec failing once triggers a single recreate+retry and a reset notice")
    func selfHeal() async {
        let rt = MockRuntime()
        rt.failNextExec = true
        let m = mgr(rt)
        let id = UUID()
        let out = await m.run(command: "a", conversationId: id, workspace: "/ws")
        #expect(rt.createdCount == 2)   // initial + recreate
        #expect(out.hasPrefix("[sandbox]"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SandboxSessionManager`
Expected: FAIL — `cannot find 'SandboxSessionManager' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/iris/SandboxSessionManager.swift`:

```swift
import Foundation

/// Owns one long-lived container per conversation. Commands run via `container exec`; disk state
/// persists within a session. An `actor` so concurrent tool calls serialize and lazy creation
/// happens exactly once.
actor SandboxSessionManager {
    static let namePrefix = "iris-"

    struct Session { let name: String; var mountedWorkspace: String?; var lastUsed: Date }

    private let runtime: ContainerRuntime
    private let image: @Sendable () -> String
    private var sessions: [UUID: Session] = [:]
    /// Conversations whose container was lost (idle-reaped or died mid-session). The next `run`
    /// recreates and prefixes a reset notice, distinguishing an unexpected reset from a cold start.
    private var lostSessions: Set<UUID> = []

    static let shared = SandboxSessionManager(runtime: CLIContainerRuntime(),
                                              image: { ConfigManager.shared.sandboxImage })

    init(runtime: ContainerRuntime, image: @escaping @Sendable () -> String) {
        self.runtime = runtime
        self.image = image
    }

    func hasSession(_ id: UUID) -> Bool { sessions[id] != nil }

    private func name(for id: UUID) -> String { "\(Self.namePrefix)\(id.uuidString.lowercased())" }

    private static let resetNotice = """
    [sandbox] This session's container was reclaimed after being idle; previously installed \
    packages and temp files were cleared (your workspace files on disk are untouched). Re-run any \
    setup (installs/builds) before relying on them.
    """

    func run(command: String, conversationId id: UUID, workspace: String?) async -> String {
        let wasLost = lostSessions.contains(id)
        var created = false

        // Recreate if the workspace changed (agent-initiated — not a "loss").
        if let s = sessions[id], s.mountedWorkspace != workspace {
            await runtime.remove(name: s.name)
            sessions[id] = nil
        }

        if sessions[id] == nil {
            do { try await create(id, workspace: workspace); created = true }
            catch { return creationError(error) }
        }

        let workdir = workspace ?? "/"
        do {
            let r = try await runtime.exec(name: name(for: id), workdir: workdir, command: command)
            sessions[id]?.lastUsed = Date()
            return decorate(format(r), notice: wasLost && created, for: id)
        } catch {
            // Container likely died/was reaped: mark lost, recreate once, retry.
            lostSessions.insert(id)
            await runtime.remove(name: name(for: id))
            sessions[id] = nil
            do {
                try await create(id, workspace: workspace)
                let r = try await runtime.exec(name: name(for: id), workdir: workdir, command: command)
                sessions[id]?.lastUsed = Date()
                return decorate(format(r), notice: true, for: id)
            } catch {
                return "Error executing sandboxed command: \(error)"
            }
        }
    }

    func endSession(_ id: UUID) async {
        if let s = sessions[id] { await runtime.remove(name: s.name) }
        sessions[id] = nil
        lostSessions.remove(id)
    }

    func endAll() async {
        for (_, s) in sessions { await runtime.remove(name: s.name) }
        sessions.removeAll()
    }

    func reapOrphans() async {
        for n in await runtime.list(prefix: Self.namePrefix) { await runtime.remove(name: n) }
    }

    func reapIdle(olderThan seconds: TimeInterval, now: Date = Date()) async {
        for (id, s) in sessions where now.timeIntervalSince(s.lastUsed) > seconds {
            await runtime.remove(name: s.name)
            sessions[id] = nil
            lostSessions.insert(id)
        }
    }

    // MARK: - Helpers

    private func create(_ id: UUID, workspace: String?) async throws {
        let mount = workspace.map { "\($0):\($0)" }
        try await runtime.createDetached(name: name(for: id), image: image(),
                                         mount: mount, workdir: workspace ?? "/")
        sessions[id] = Session(name: name(for: id), mountedWorkspace: workspace, lastUsed: Date())
    }

    private func format(_ r: (stdout: String, stderr: String, exitCode: Int32)) -> String {
        var result = r.stdout
        if !r.stderr.isEmpty { result += "\nStderr: " + r.stderr }
        if r.exitCode != 0, let hint = ToolExecutor.sandboxSetupHint(for: result) { return hint }
        return result.isEmpty ? "Success" : result
    }

    private func decorate(_ output: String, notice: Bool, for id: UUID) -> String {
        guard notice else { return output }
        lostSessions.remove(id)
        return Self.resetNotice + "\n\n" + output
    }

    private func creationError(_ error: Error) -> String {
        if case ContainerRuntimeError.createFailed(let msg) = error,
           let hint = ToolExecutor.sandboxSetupHint(for: msg) {
            return hint
        }
        return "Error: could not start the sandbox container: \(error)"
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SandboxSessionManager`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/SandboxSessionManager.swift Tests/irisTests/SandboxSessionManagerTests.swift
git commit -m "feat(sandbox): SandboxSessionManager actor with lifecycle, reap, self-heal, reset notice"
```

---

### Task 3: Config knob `sandboxIdleTimeoutMinutes`

**Files:**
- Modify: `Sources/iris/ConfigManager.swift` (property near the other sandbox settings + init read)

**Interfaces:**
- Produces: `ConfigManager.sandboxIdleTimeoutMinutes: Int` (default 30, key `SANDBOX_IDLE_TIMEOUT_MINUTES`).

- [ ] **Step 1: Add the property**

After the `sandboxImage` property block (`ConfigManager.swift:140-142`), add:

```swift
    var sandboxIdleTimeoutMinutes: Int {
        didSet { UserDefaults.standard.set(sandboxIdleTimeoutMinutes, forKey: "SANDBOX_IDLE_TIMEOUT_MINUTES") }
    }
```

- [ ] **Step 2: Initialize it**

After the `sandboxImage` init line (`ConfigManager.swift:266`), add:

```swift
        let savedIdle = UserDefaults.standard.integer(forKey: "SANDBOX_IDLE_TIMEOUT_MINUTES")
        self.sandboxIdleTimeoutMinutes = savedIdle == 0 ? 30 : savedIdle
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/iris/ConfigManager.swift
git commit -m "feat(sandbox): sandboxIdleTimeoutMinutes config (default 30)"
```

---

### Task 4: Wire `run_command` to the session manager

**Files:**
- Modify: `Sources/iris/ToolExecutor.swift` (`execute`, `runCommand`)
- Modify: `Sources/iris/iris.swift` (`executeToolWithHooks`, its call sites in `executeFunctionCall`)

**Interfaces:**
- Consumes: `SandboxSessionManager.shared.run(command:conversationId:workspace:)` (Task 2).

**Note:** Wiring — verified by build. When sandboxing is on and a `conversationId` is present, `run_command` routes to the persistent session; otherwise the existing paths are unchanged.

- [ ] **Step 1: Thread `conversationId` through `ToolExecutor.execute`**

Change the signature (`ToolExecutor.swift:78`):

```swift
    func execute(name: String, args: [String: JSONValue], cwd: String? = nil, conversationId: UUID? = nil) async -> String {
```

And the `run_command` case (`ToolExecutor.swift:80-82`):

```swift
        case "run_command":
            guard let command = args["command"]?.stringValue else { return "Error: Missing command" }
            return await runCommand(command, cwd: cwd, conversationId: conversationId)
```

- [ ] **Step 2: Delegate to the session manager in `runCommand`**

Change `runCommand`'s signature (`ToolExecutor.swift:108`) and add the delegation branch at the very top of its body, before the existing `withCheckedContinuation`:

```swift
    private func runCommand(_ command: String, cwd: String?, conversationId: UUID? = nil) async -> String {
        if ConfigManager.shared.enableSandboxing, let conversationId {
            guard SandboxingManager.shared.isContainerInstalled else {
                return "Error: Sandboxing is enabled but the container runtime is not installed. Run the /sandbox command to install it, or disable sandboxing in settings."
            }
            return await SandboxSessionManager.shared.run(command: command, conversationId: conversationId, workspace: cwd)
        }
        return await withCheckedContinuation { continuation in
            // ...existing body unchanged...
        }
    }
```

(The existing `enableSandboxing` branch inside the continuation remains as the fallback for the no-`conversationId` case.)

- [ ] **Step 3: Thread `conversationId` through the engine**

In `iris.swift`, change `executeToolWithHooks` (`iris.swift:610`):

```swift
    private func executeToolWithHooks(name: String, args: [String: JSONValue], cwd: String?, conversationId: UUID?) async -> String {
```

Change its `executor.execute` call (`iris.swift:628`):

```swift
        var result = await executor.execute(name: name, args: execArgs, cwd: cwd, conversationId: conversationId)
```

Update the two call sites in `executeFunctionCall` (`iris.swift:598` and `:603`) to pass `conversationId: conversationId`:

```swift
                    result = await executeToolWithHooks(name: functionCall.name, args: functionCall.args, cwd: workspacePath, conversationId: conversationId)
```

```swift
                result = await executeToolWithHooks(name: functionCall.name, args: functionCall.args, cwd: workspacePath, conversationId: conversationId)
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/ToolExecutor.swift Sources/iris/iris.swift
git commit -m "feat(sandbox): route sandboxed run_command through the persistent session manager"
```

---

### Task 5: Startup reap, idle reaper, and conversation-delete teardown

**Files:**
- Modify: `Sources/iris/iris.swift` (`IrisApp.init` — reap + idle-reaper task)
- Modify: `Sources/iris/AppState.swift` (`deleteConversation` — end the session)

**Interfaces:**
- Consumes: `SandboxSessionManager.shared.reapOrphans()`, `.reapIdle(olderThan:)`, `.endSession(_:)` (Task 2).

**Note:** App-quit teardown is intentionally omitted — `applicationWillTerminate` calls `_exit(0)`, so async cleanup can't run. `reapOrphans()` at next launch is the authoritative cleanup. Wiring — verified by build.

- [ ] **Step 1: Reap orphans + start the idle reaper at launch**

In `IrisApp.init()` (`iris.swift:682`), after `ShippedSkills.seedIfNeeded(.default)`, add:

```swift
        Task {
            await SandboxSessionManager.shared.reapOrphans()
            while true {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000) // every 5 min
                let minutes = await MainActor.run { ConfigManager.shared.sandboxIdleTimeoutMinutes }
                await SandboxSessionManager.shared.reapIdle(olderThan: TimeInterval(minutes * 60))
            }
        }
```

- [ ] **Step 2: End the session when a conversation is deleted**

In `AppState.deleteConversation(_:)` (`AppState.swift:205`), immediately after the existing `cancelTasks(for: id)` call, add:

```swift
        Task { await SandboxSessionManager.shared.endSession(id) }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/iris/iris.swift Sources/iris/AppState.swift
git commit -m "feat(sandbox): startup orphan reap, idle reaper loop, delete-conversation teardown"
```

---

### Task 6: Ship the `sandbox-usage` skill

**Files:**
- Create: `Sources/iris/assets/sandbox-usage-SKILL.md`
- Modify: `Sources/iris/ShippedSkills.swift` (add a seed item)

**Interfaces:**
- Consumes: `ShippedSkills.bundledText(_:)`, `paths.skillsDir` (existing).

**Note:** Bundled markdown is copied into resources by `Package.swift`'s `.process("assets")` (already covers the folder). Seeding is idempotent/non-destructive. Verified by build (asset loads via `Bundle.module`).

- [ ] **Step 1: Create the skill asset**

Create `Sources/iris/assets/sandbox-usage-SKILL.md`:

```markdown
---
type: skill
title: sandbox-usage
description: How to use the per-conversation sandbox container efficiently (persistent disk state, non-persistent shell state, idle resets).
tags: [sandbox, shell, efficiency]
timestamp: 2026-07-25
---

# Using the Sandbox Efficiently

When sandboxing is enabled, `run_command` runs inside a Linux container that lives for the whole
conversation. The active workspace is mounted at the **same absolute path** as on the host, so a
file written with `write_file` is visible to your commands at that path.

## What persists, what doesn't

- **Disk state persists** within the session: packages you install, files you create, and build
  artifacts remain available to later commands. Install or build once, then reuse — don't
  reinstall every command.
- **Shell state does NOT persist across separate `run_command` calls.** Each command is a fresh
  process, so `cd` and `export` do not carry over. Instead:
  - Chain within one command: `cd subdir && make`.
  - Use absolute paths.
  - Set environment inline: `FOO=bar ./script.sh`.

## Efficiency

- Prefer a few combined commands over many tiny ones. Chaining with `&&` is cheaper and clearer
  than issuing each step as its own `run_command`.

## Idle resets

An idle session's container may be reclaimed after a period of inactivity to free resources. When
that happens, in-container disk state is cleared (your **host workspace files are never touched**).
You will see a notice prefixed to the next command's output:

> `[sandbox] This session's container was reclaimed after being idle; ...`

Treat that notice as a signal to re-run any setup (installs/builds) before relying on it.
```

- [ ] **Step 2: Add the seed item**

In `ShippedSkills.seedIfNeeded` (`ShippedSkills.swift:13-22`), add to the array:

```swift
            SeedItem(content: bundledText("sandbox-usage-SKILL"),
                     target: paths.skillsDir.appendingPathComponent("sandbox-usage/SKILL.md")),
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Verify the asset resolves**

Run: `swift test --filter SandboxSessionManager` (a proxy build+link of the test target)
Expected: PASS. (The asset is loaded at runtime via `Bundle.module`; this confirms packaging compiles. Runtime seeding is confirmed in Task 7 manual check.)

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/assets/sandbox-usage-SKILL.md Sources/iris/ShippedSkills.swift
git commit -m "feat(sandbox): ship the sandbox-usage skill"
```

---

### Task 7: Settings toggle + manual verification

**Files:**
- Modify: `Sources/iris/SettingsView.swift` (idle-timeout control near the sandbox settings)

**Interfaces:**
- Consumes: `ConfigManager.shared.sandboxIdleTimeoutMinutes` (Task 3).

- [ ] **Step 1: Add the idle-timeout control**

Locate the sandbox section in `SettingsView.swift` (search for `enableSandboxing` / `sandboxImage`). Next to those controls, add a stepper bound to the config (match the file's existing binding style; example):

```swift
            Stepper("Sandbox idle timeout: \(ConfigManager.shared.sandboxIdleTimeoutMinutes) min",
                    value: Binding(
                        get: { ConfigManager.shared.sandboxIdleTimeoutMinutes },
                        set: { ConfigManager.shared.sandboxIdleTimeoutMinutes = max(1, $0) }),
                    in: 1...240)
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Manual verification (real container runtime)**

Enable sandboxing, bind a workspace, then in one conversation:
1. Run `apt-get install -y jq` (or `pip install …`), then a second command using it — confirm the tool it installed is still present (disk state persisted).
2. Time ~10 quick commands; confirm per-command latency is well under the ~0.85s cold-boot cost.
3. Set `sandboxIdleTimeoutMinutes` to 1, wait ~6 min idle, run a command — confirm the `[sandbox] … reclaimed …` notice appears exactly once and the container is fresh.
4. Delete the conversation; confirm the `iris-<id>` container is gone (`container ls -a`).
5. Force-quit and relaunch; confirm no `iris-` containers survive (startup reap).

- [ ] **Step 4: Commit**

```bash
git add Sources/iris/SettingsView.swift
git commit -m "feat(sandbox): settings control for sandbox idle timeout"
```

---

## Self-Review

**Spec coverage:**
- Persistent container per conversation + `container exec` → Tasks 1, 2, 4. ✓
- `ContainerRuntime` seam (testable) → Task 1. ✓
- Lazy create (once under concurrency) → Task 2 (`lazyCreate`, `concurrentCreateOnce`). ✓
- Exec workdir + host-parity output formatting → Task 2 (`format`, `formatting` test). ✓
- Workspace-change recreate → Task 2 (`workspaceChange`). ✓
- Teardown: conversation delete → Task 5; app-quit → documented as startup reap (`_exit(0)` constraint); startup reap → Task 5 + Task 2 (`reapOrphans`). ✓
- Idle reaper (config default 30) → Tasks 2 (`reapIdle`), 3, 5. ✓
- Self-heal recreate+retry → Task 2 (`selfHeal`). ✓
- Session-reset notice (only on unexpected loss, not first cold start) → Task 2 (`reapIdleAndNotice`, `firstCreateNoNotice`, `selfHeal`). ✓
- `sandbox-usage` skill (seeded, OKF, content) → Task 6. ✓
- Config `sandboxIdleTimeoutMinutes` + Settings → Tasks 3, 7. ✓
- `conversationId` threading → Task 4. ✓
- Reused guardrails/host path unchanged → Tasks 4 (delegation branch only when sandboxing on + id present). ✓

**Placeholder scan:** No TBD/TODO; all code and test bodies concrete. The only non-verbatim edit is Task 7's Settings control (matches file's binding style) — acceptable as UI glue with a working example given.

**Type consistency:** `run(command:conversationId:workspace:)`, `endSession(_:)`, `endAll()`, `reapOrphans()`, `reapIdle(olderThan:now:)`, `hasSession(_:)`, `namePrefix`, and `ContainerRuntime`'s four methods are used identically across Tasks 1–5. `execute(...conversationId:)` and `executeToolWithHooks(...conversationId:)` signatures match their call sites in Task 4. ✓
