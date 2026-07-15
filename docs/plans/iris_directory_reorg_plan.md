# ~/.iris Directory Reorganization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Segregate `~/.iris/` into `memory/` + `config/` + `models/` behind a single `IrisPaths` abstraction, auto-migrate existing installs, fix the SOUL split-brain bug, and add `update_soul`/`update_memory` write-tools.

**Architecture:** Introduce `IrisPaths` (injectable-root value type) as the single source of truth for every home-dir path, replacing ~8 duplicated hardcoded derivations. A pure `IrisMigrator` moves old flat files into the new layout at startup (idempotent, non-destructive). Consumers switch to `IrisPaths`; `MemoryManager` gains an `updateSoul` writer and the bot gets `update_soul`/`update_memory` tools that write to the canonical paths.

**Tech Stack:** Swift, swift-testing, Foundation FileManager.

## Global Constraints

- Layout: `memory/` (SOUL.md, USER.md, memory.md, skills/, artifacts/, holographic_memory.sqlite[+ -shm/-wal]); `config/` (settings.json, permissions.json, mcp_servers.json); `models/` (resolved path unchanged).
- Migration is **idempotent** and **non-destructive**: move only if source exists AND destination does not. The single sanctioned deletion is the redundant stray `~/.iris/SOUL.md`, removed only once `memory/SOUL.md` exists.
- Migration must run at startup **before** any manager opens a migrated file (esp. the holographic SQLite DB) — first line of `IrisApp.init()`.
- `IrisPaths.root` is injectable; `IrisMigrator` and `MemoryManager` must be testable against a temp root.
- The old on-disk name `library/` migrates to `memory/artifacts/`.
- Per-workspace `.iris/` (PermissionManager's workspace path, VibecopService, ChatView, ToolExecutor workspace `.iris`) is **out of scope — do not touch**.
- Commit messages end with: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- Spec: `docs/specs/iris_directory_reorg_design.md`.
- Build/test note: a full `swift test` has pre-existing UNRELATED failures (`SandboxTests`, missing `Qwen3.5-2B` GGUF). Use focused `--filter` runs; don't chase those.

---

## File Structure

- Create: `Sources/iris/IrisPaths.swift` — the path source of truth.
- Create: `Sources/iris/IrisMigrator.swift` — one-shot startup migration.
- Create: `Tests/irisTests/IrisPathsTests.swift`, `Tests/irisTests/IrisMigratorTests.swift`, `Tests/irisTests/MemoryToolsTests.swift`.
- Modify (refactor to IrisPaths): `SkillManager.swift`, `MemoryManager.swift`, `HolographicMemoryManager.swift`, `PermissionManager.swift`, `HookManager.swift`, `MCPManager.swift`, `AuxiliaryModelManager.swift`, `CoreMLEvaluator.swift`, `LlamaCPPEngine.swift`, `ModelDownloader.swift`, `TestTokenizer.swift`.
- Modify: `iris.swift` (startup wiring in `IrisApp.init()`; `update_soul`/`update_memory` tool declarations + dispatch), `AppState.swift` (reflection/grooming prompts), `Sources/iris/assets/SYSTEM.md` (path references).

---

## Task 1: IrisPaths — single source of truth

**Files:**
- Create: `Sources/iris/IrisPaths.swift`
- Test: `Tests/irisTests/IrisPathsTests.swift`

**Interfaces:**
- Consumes: nothing (leaf).
- Produces: `struct IrisPaths` with `init(root: URL)`, `static let default`, URL accessors (`memoryDir`, `soulMd`, `userMd`, `memoryMd`, `skillsDir`, `artifactsDir`, `holographicDB`, `configDir`, `settingsJSON`, `permissionsJSON`, `mcpServersJSON`, `modelsDir`), and `func ensureDirectories() throws`.

- [ ] **Step 1: Write the failing tests `Tests/irisTests/IrisPathsTests.swift`**

```swift
import Testing
import Foundation
@testable import iris

@Suite("IrisPaths Tests")
struct IrisPathsTests {

    @Test("accessors compose paths under the injected root")
    func testAccessorsComposeUnderRoot() {
        let root = URL(fileURLWithPath: "/tmp/iris-test-root")
        let p = IrisPaths(root: root)
        #expect(p.memoryDir.path == "/tmp/iris-test-root/memory")
        #expect(p.soulMd.path == "/tmp/iris-test-root/memory/SOUL.md")
        #expect(p.userMd.path == "/tmp/iris-test-root/memory/USER.md")
        #expect(p.memoryMd.path == "/tmp/iris-test-root/memory/memory.md")
        #expect(p.skillsDir.path == "/tmp/iris-test-root/memory/skills")
        #expect(p.artifactsDir.path == "/tmp/iris-test-root/memory/artifacts")
        #expect(p.holographicDB.path == "/tmp/iris-test-root/memory/holographic_memory.sqlite")
        #expect(p.configDir.path == "/tmp/iris-test-root/config")
        #expect(p.settingsJSON.path == "/tmp/iris-test-root/config/settings.json")
        #expect(p.permissionsJSON.path == "/tmp/iris-test-root/config/permissions.json")
        #expect(p.mcpServersJSON.path == "/tmp/iris-test-root/config/mcp_servers.json")
        #expect(p.modelsDir.path == "/tmp/iris-test-root/models")
    }

    @Test("ensureDirectories creates the bucket directories")
    func testEnsureDirectoriesCreatesBuckets() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("iris-ensure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let p = IrisPaths(root: root)
        try p.ensureDirectories()
        for dir in [p.memoryDir, p.skillsDir, p.artifactsDir, p.configDir, p.modelsDir] {
            var isDir: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
            #expect(isDir.boolValue)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter IrisPathsTests`
Expected: FAIL to compile — `cannot find 'IrisPaths' in scope`.

- [ ] **Step 3: Create `Sources/iris/IrisPaths.swift`**

```swift
import Foundation

/// Single source of truth for every path under the home config directory (`~/.iris`).
///
/// Storage is segregated by owner: `memory/` (bot-authored, mutable, guard-sanitized),
/// `config/` (human/app config), and `models/` (downloaded bundles). Every consumer resolves
/// paths through here instead of re-deriving `("~/.iris" as NSString).expandingTildeInPath`,
/// which removes the duplication that produced the SOUL split-brain bug. `root` is injectable
/// so `IrisMigrator` and the memory managers can be unit-tested against a temp directory.
struct IrisPaths: Sendable {
    let root: URL

    init(root: URL) { self.root = root }

    static let `default` = IrisPaths(
        root: URL(fileURLWithPath: ("~/.iris" as NSString).expandingTildeInPath)
    )

    // memory/
    var memoryDir: URL { root.appendingPathComponent("memory") }
    var soulMd: URL { memoryDir.appendingPathComponent("SOUL.md") }
    var userMd: URL { memoryDir.appendingPathComponent("USER.md") }
    var memoryMd: URL { memoryDir.appendingPathComponent("memory.md") }
    var skillsDir: URL { memoryDir.appendingPathComponent("skills") }
    var artifactsDir: URL { memoryDir.appendingPathComponent("artifacts") }
    var holographicDB: URL { memoryDir.appendingPathComponent("holographic_memory.sqlite") }

    // config/
    var configDir: URL { root.appendingPathComponent("config") }
    var settingsJSON: URL { configDir.appendingPathComponent("settings.json") }
    var permissionsJSON: URL { configDir.appendingPathComponent("permissions.json") }
    var mcpServersJSON: URL { configDir.appendingPathComponent("mcp_servers.json") }

    // models/ (resolved path unchanged from the old layout)
    var modelsDir: URL { root.appendingPathComponent("models") }

    /// Create the bucket directories if absent. Called by the migrator and by managers that
    /// need their directory to exist before writing.
    func ensureDirectories() throws {
        for dir in [memoryDir, skillsDir, artifactsDir, configDir, modelsDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter IrisPathsTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/IrisPaths.swift Tests/irisTests/IrisPathsTests.swift
git commit -m "feat(paths): add IrisPaths single source of truth for ~/.iris layout

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: IrisMigrator — one-shot startup migration

**Files:**
- Create: `Sources/iris/IrisMigrator.swift`
- Test: `Tests/irisTests/IrisMigratorTests.swift`

**Interfaces:**
- Consumes: `IrisPaths` (Task 1) — `root`, `ensureDirectories()`, and the memory/config accessors.
- Produces: `enum IrisMigrator { static func migrate(_ paths: IrisPaths) }`.

- [ ] **Step 1: Write the failing tests `Tests/irisTests/IrisMigratorTests.swift`**

```swift
import Testing
import Foundation
@testable import iris

@Suite("IrisMigrator Tests")
struct IrisMigratorTests {

    /// Fresh temp root with an optional old-flat-layout seed.
    private func makeRoot() -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("iris-migrate-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func write(_ url: URL, _ text: String) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    @Test("fresh install: creates buckets, moves nothing")
    func testFreshInstall() {
        let root = makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let p = IrisPaths(root: root)
        IrisMigrator.migrate(p)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: p.memoryDir.path, isDirectory: &isDir) && isDir.boolValue)
        #expect(FileManager.default.fileExists(atPath: p.configDir.path, isDirectory: &isDir) && isDir.boolValue)
    }

    @Test("old flat layout: files land at new paths")
    func testMovesOldLayout() {
        let root = makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let p = IrisPaths(root: root)
        write(root.appendingPathComponent("USER.md"), "user")
        write(root.appendingPathComponent("memory.md"), "mem")
        write(root.appendingPathComponent("skills/a/SKILL.md"), "skill")
        write(root.appendingPathComponent("library/proj/specs/x.md"), "spec")
        write(root.appendingPathComponent("settings.json"), "{}")
        write(root.appendingPathComponent("permissions.json"), "[]")
        write(root.appendingPathComponent("mcp_servers.json"), "{}")
        write(root.appendingPathComponent("prompts/SOUL.md"), "canonical-soul")

        IrisMigrator.migrate(p)

        #expect(read(p.userMd) == "user")
        #expect(read(p.memoryMd) == "mem")
        #expect(read(p.skillsDir.appendingPathComponent("a/SKILL.md")) == "skill")
        #expect(read(p.artifactsDir.appendingPathComponent("proj/specs/x.md")) == "spec")
        #expect(read(p.settingsJSON) == "{}")
        #expect(read(p.permissionsJSON) == "[]")
        #expect(read(p.mcpServersJSON) == "{}")
        #expect(read(p.soulMd) == "canonical-soul")
        // old locations gone
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("USER.md").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("prompts/SOUL.md").path))
    }

    @Test("SOUL dedup: read-copy is canonical, stray root SOUL.md deleted")
    func testSoulDedup() {
        let root = makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let p = IrisPaths(root: root)
        write(root.appendingPathComponent("prompts/SOUL.md"), "canonical")
        write(root.appendingPathComponent("SOUL.md"), "stray-newer")
        IrisMigrator.migrate(p)
        #expect(read(p.soulMd) == "canonical")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("SOUL.md").path))
    }

    @Test("idempotent + non-destructive: re-run does not overwrite migrated files")
    func testIdempotentNonDestructive() {
        let root = makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let p = IrisPaths(root: root)
        write(p.userMd, "already-migrated")           // destination already exists
        write(root.appendingPathComponent("USER.md"), "old-flat")  // stale source lingering
        IrisMigrator.migrate(p)
        #expect(read(p.userMd) == "already-migrated")  // NOT overwritten
        IrisMigrator.migrate(p)                        // second run is a no-op
        #expect(read(p.userMd) == "already-migrated")
    }

    @Test("holographic DB moves with its WAL sidecars")
    func testHolographicSidecars() {
        let root = makeRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let p = IrisPaths(root: root)
        write(root.appendingPathComponent("holographic_memory.sqlite"), "db")
        write(root.appendingPathComponent("holographic_memory.sqlite-shm"), "shm")
        write(root.appendingPathComponent("holographic_memory.sqlite-wal"), "wal")
        IrisMigrator.migrate(p)
        #expect(read(p.holographicDB) == "db")
        #expect(read(p.memoryDir.appendingPathComponent("holographic_memory.sqlite-shm")) == "shm")
        #expect(read(p.memoryDir.appendingPathComponent("holographic_memory.sqlite-wal")) == "wal")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter IrisMigratorTests`
Expected: FAIL to compile — `cannot find 'IrisMigrator' in scope`.

- [ ] **Step 3: Create `Sources/iris/IrisMigrator.swift`**

```swift
import Foundation

/// One-shot migration of an old flat `~/.iris` layout to the segregated
/// `memory/` + `config/` + `models/` layout.
///
/// Idempotent and non-destructive: each file moves only if the source exists and the
/// destination does not, so re-runs and partially-migrated installs are safe. The one
/// sanctioned deletion is the redundant stray `~/.iris/SOUL.md` (the never-read copy), removed
/// only once the canonical `memory/SOUL.md` is in place. Must run before any manager opens a
/// migrated file (notably the holographic SQLite DB — moving an open WAL database corrupts it).
enum IrisMigrator {
    static func migrate(_ paths: IrisPaths) {
        let fm = FileManager.default
        try? paths.ensureDirectories()
        let root = paths.root

        // memory/ files
        moveIfNeeded(fm, from: root.appendingPathComponent("USER.md"), to: paths.userMd)
        moveIfNeeded(fm, from: root.appendingPathComponent("memory.md"), to: paths.memoryMd)
        moveIfNeeded(fm, from: root.appendingPathComponent("skills"), to: paths.skillsDir)
        moveIfNeeded(fm, from: root.appendingPathComponent("library"), to: paths.artifactsDir)

        // holographic DB + WAL sidecars
        moveIfNeeded(fm, from: root.appendingPathComponent("holographic_memory.sqlite"), to: paths.holographicDB)
        moveIfNeeded(fm, from: root.appendingPathComponent("holographic_memory.sqlite-shm"),
                     to: paths.memoryDir.appendingPathComponent("holographic_memory.sqlite-shm"))
        moveIfNeeded(fm, from: root.appendingPathComponent("holographic_memory.sqlite-wal"),
                     to: paths.memoryDir.appendingPathComponent("holographic_memory.sqlite-wal"))

        // config/ files
        moveIfNeeded(fm, from: root.appendingPathComponent("settings.json"), to: paths.settingsJSON)
        moveIfNeeded(fm, from: root.appendingPathComponent("permissions.json"), to: paths.permissionsJSON)
        moveIfNeeded(fm, from: root.appendingPathComponent("mcp_servers.json"), to: paths.mcpServersJSON)

        // SOUL: the actively-read prompts/SOUL.md is canonical; the stray root SOUL.md is the
        // redundant never-read copy and is deleted once the canonical one exists.
        moveIfNeeded(fm, from: root.appendingPathComponent("prompts/SOUL.md"), to: paths.soulMd)
        let straySoul = root.appendingPathComponent("SOUL.md")
        if fm.fileExists(atPath: paths.soulMd.path), fm.fileExists(atPath: straySoul.path) {
            try? fm.removeItem(at: straySoul)
        }
    }

    /// Move only when the source exists and the destination does not — idempotent and never
    /// overwrites an already-migrated file.
    private static func moveIfNeeded(_ fm: FileManager, from: URL, to: URL) {
        guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { return }
        try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.moveItem(at: from, to: to)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter IrisMigratorTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/IrisMigrator.swift Tests/irisTests/IrisMigratorTests.swift
git commit -m "feat(paths): add idempotent non-destructive IrisMigrator

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Refactor consumers to IrisPaths + wire migrator at startup

**Files (Modify):** `SkillManager.swift`, `MemoryManager.swift`, `HolographicMemoryManager.swift`, `PermissionManager.swift`, `HookManager.swift`, `MCPManager.swift`, `AuxiliaryModelManager.swift`, `CoreMLEvaluator.swift`, `LlamaCPPEngine.swift`, `ModelDownloader.swift`, `TestTokenizer.swift`, `iris.swift`.

**Interfaces:**
- Consumes: `IrisPaths` (Task 1), `IrisMigrator.migrate(_:)` (Task 2).
- Produces: `MemoryManager` gains a settable `var paths: IrisPaths` (default `.default`) used by all its path accessors — consumed by Task 4's tests and tools.

This task is a mechanical one-to-one substitution: replace each hardcoded `~/.iris`-derived path with the matching `IrisPaths.default` accessor (use `.path` where a `String` is required, the URL where a `URL` is required). The resolved `models/` path is unchanged, so model consumers are pure-consistency refactors with no behavior change. Do not touch any per-workspace `.iris/` path.

- [ ] **Step 1: `MemoryManager.swift` — inject IrisPaths (settable for tests)**

Replace the top of the class (the `configDir`/`memoryPath`/`userProfilePath`/`init`) with:

```swift
class MemoryManager: @unchecked Sendable {
    static let shared = MemoryManager()

    /// Settable so tests can point the manager at a temp root. Production uses `.default`.
    var paths: IrisPaths = .default

    private var memoryPath: String { paths.memoryMd.path }
    private var userProfilePath: String { paths.userMd.path }

    private init() {
        try? paths.ensureDirectories()
        if !FileManager.default.fileExists(atPath: memoryPath) {
            try? "Memory is currently empty.".write(toFile: memoryPath, atomically: true, encoding: .utf8)
        }
        if !FileManager.default.fileExists(atPath: userProfilePath) {
            try? "User profile is currently empty.".write(toFile: userProfilePath, atomically: true, encoding: .utf8)
        }
    }
```

Leave `getMemory`/`updateMemory`/`getUserProfile`/`updateUserProfile` as-is (they read the computed `memoryPath`/`userProfilePath`, now IrisPaths-backed).

- [ ] **Step 2: `SkillManager.swift` — read SOUL/skills via IrisPaths**

Delete `let configDir = ("~/.iris" as NSString).expandingTildeInPath`. Change:
- `let path = "\(configDir)/prompts/SOUL.md"` → `let path = IrisPaths.default.soulMd.path`
- `let skillsDir = "\(configDir)/skills"` → `let skillsDir = IrisPaths.default.skillsDir.path`
- In `parseFrontmatter`, the returned `**Path:** ~/.iris/skills/\(folderName)/SKILL.md` → `**Path:** ~/.iris/memory/skills/\(folderName)/SKILL.md`

- [ ] **Step 3: `HolographicMemoryManager.swift` — DB path via IrisPaths**

Replace the `else` branch body (lines ~181-189) that builds `configDir`/`dbPath`:

```swift
        } else {
            try? IrisPaths.default.ensureDirectories()
            let dbPath = IrisPaths.default.holographicDB.path
            dbPool = try DatabasePool(path: dbPath, configuration: configuration)
            dbQueue = nil
            try migrator.migrate(dbPool!)
        }
```

- [ ] **Step 4: `PermissionManager.swift` — global permissions via IrisPaths**

Replace the `private init()` body:

```swift
    private init() {
        try? IrisPaths.default.ensureDirectories()
        globalPermissionsURL = IrisPaths.default.permissionsJSON
    }
```

Leave `projectPermissionsURL(for:)` (the workspace `.iris/permissions.json`) untouched.

- [ ] **Step 5: `HookManager.swift`, `MCPManager.swift` — config files via IrisPaths**

- HookManager: `configPathOverride ?? ("~/.iris/settings.json" as NSString).expandingTildeInPath` → `configPathOverride ?? IrisPaths.default.settingsJSON.path`
- MCPManager: `return ("~/.iris/mcp_servers.json" as NSString).expandingTildeInPath` → `return IrisPaths.default.mcpServersJSON.path`

- [ ] **Step 6: Model consumers — resolve `models/` via IrisPaths (path unchanged)**

- `AuxiliaryModelManager.swift` init: replace
  ```swift
  let configDir = ("~/.iris" as NSString).expandingTildeInPath
  self.modelsDir = "\(configDir)/models"
  ```
  with `self.modelsDir = IrisPaths.default.modelsDir.path`
- `CoreMLEvaluator.swift`: `let basePath = ("~/.iris/models/" as NSString).expandingTildeInPath` → `let basePath = IrisPaths.default.modelsDir.path`
- `LlamaCPPEngine.swift`: `let path = ("~/.iris/models/" as NSString).expandingTildeInPath + "/" + config.modelPathOrName` → `let path = IrisPaths.default.modelsDir.appendingPathComponent(config.modelPathOrName).path`
- `ModelDownloader.swift` (three sites at ~lines 38, 80, 96): each `("~/.iris/models/" as NSString).expandingTildeInPath` → `IrisPaths.default.modelsDir.path`
- `TestTokenizer.swift`: `URL(fileURLWithPath: ("/Users/bnaylor/.iris/models/distilbert-prompt-injection.mlmodelc" as NSString).expandingTildeInPath)` → `IrisPaths.default.modelsDir.appendingPathComponent("distilbert-prompt-injection.mlmodelc")`

- [ ] **Step 7: `iris.swift` — run the migrator first at startup**

In `IrisApp.init()`, make migration the very first statement (before `NSApplication` setup), so it runs before any manager opens a migrated file:

```swift
    init() {
        IrisMigrator.migrate(.default)
        NSApplication.shared.setActivationPolicy(.regular)
```

- [ ] **Step 8: Verify — no stray hardcoded home paths, build, existing tests pass**

Run: `grep -rn '"~/.iris' Sources/iris/*.swift`
Expected: **no matches** except `IrisPaths.swift` (the one `static let default`). Any per-workspace `.iris` references (workspace-relative, not `~/.iris`) are fine.

Run: `IRIS_ONNX_TEST_BUNDLE="$HOME/.iris/models/deberta-v3-base-prompt-injection-v2.onnx" swift test --filter "IrisPathsTests|IrisMigratorTests|InjectionGuardTests|SystemSteeringTests"`
Expected: PASS. (Full build must succeed; these suites confirm no compile regressions in the touched modules.)

- [ ] **Step 9: Commit**

```bash
git add Sources/iris/*.swift
git commit -m "refactor(paths): route all ~/.iris consumers through IrisPaths; migrate at startup

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Memory write-tools (update_soul / update_memory)

**Files:**
- Modify: `Sources/iris/MemoryManager.swift` (add `updateSoul`), `Sources/iris/iris.swift` (tool declarations + dispatch)
- Test: `Tests/irisTests/MemoryToolsTests.swift`

**Interfaces:**
- Consumes: `MemoryManager` with settable `paths` (Task 3), `IrisPaths` (Task 1). `IrisEngine` has `var systemPrompt: Content!` (reset by assigning `nil`).
- Produces: `MemoryManager.updateSoul(content:)`; `update_soul`/`update_memory` tools.

- [ ] **Step 1: Write the failing tests `Tests/irisTests/MemoryToolsTests.swift`**

```swift
import Testing
import Foundation
@testable import iris

@Suite("Memory Tools Tests", .serialized)
struct MemoryToolsTests {

    private func withTempPaths(_ body: (IrisPaths) -> Void) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("iris-tools-\(UUID().uuidString)")
        let p = IrisPaths(root: root)
        try? p.ensureDirectories()
        let previous = MemoryManager.shared.paths
        MemoryManager.shared.paths = p
        defer { MemoryManager.shared.paths = previous; try? FileManager.default.removeItem(at: root) }
        body(p)
    }

    @Test("updateSoul writes memory/SOUL.md")
    func testUpdateSoul() {
        withTempPaths { p in
            MemoryManager.shared.updateSoul(content: "new soul")
            #expect((try? String(contentsOf: p.soulMd, encoding: .utf8)) == "new soul")
        }
    }

    @Test("updateMemory writes memory/memory.md")
    func testUpdateMemory() {
        withTempPaths { p in
            MemoryManager.shared.updateMemory(content: "new memory")
            #expect((try? String(contentsOf: p.memoryMd, encoding: .utf8)) == "new memory")
        }
    }

    @Test("updateUserProfile writes memory/USER.md")
    func testUpdateUserProfile() {
        withTempPaths { p in
            MemoryManager.shared.updateUserProfile(content: "new user")
            #expect((try? String(contentsOf: p.userMd, encoding: .utf8)) == "new user")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter MemoryToolsTests`
Expected: FAIL — `value of type 'MemoryManager' has no member 'updateSoul'`.

- [ ] **Step 3: Add `updateSoul` to `MemoryManager.swift`**

After `updateMemory(content:)`, add:

```swift
    func getSoul() -> String {
        (try? String(contentsOf: paths.soulMd, encoding: .utf8)) ?? ""
    }

    func updateSoul(content: String) {
        try? paths.ensureDirectories()
        try? content.write(to: paths.soulMd, atomically: true, encoding: .utf8)
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter MemoryToolsTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Declare the tools in `iris.swift`**

Immediately after the `update_user_profile` `toolsList.append(...)` block, add:

```swift
        toolsList.append(FunctionDeclaration(
            name: "update_soul",
            description: "Overwrite your core identity file (SOUL.md). Use this to durably evolve your persona, values, and standing directives. Keep it coherent and concise.",
            parameters: Schema(
                type: "OBJECT",
                properties: [
                    "content": Schema(type: "STRING", description: "The new complete text content for SOUL.md")
                ],
                required: ["content"]
            )
        ))
        toolsList.append(FunctionDeclaration(
            name: "update_memory",
            description: "Overwrite your mid-term memory file (memory.md). Use this to consolidate durable facts, project context, and recurring workflows.",
            parameters: Schema(
                type: "OBJECT",
                properties: [
                    "content": Schema(type: "STRING", description: "The new complete text content for memory.md")
                ],
                required: ["content"]
            )
        ))
```

- [ ] **Step 6: Dispatch the tools in `iris.swift`**

Immediately after the `update_user_profile` dispatch branch, add:

```swift
        } else if functionCall.name == "update_soul", let content = functionCall.args["content"]?.stringValue {
            MemoryManager.shared.updateSoul(content: content)
            systemPrompt = nil   // invalidate cache so the new SOUL loads next turn
            result = "Soul updated. It will take effect on the next turn."
        } else if functionCall.name == "update_memory", let content = functionCall.args["content"]?.stringValue {
            MemoryManager.shared.updateMemory(content: content)
            result = "Memory updated."
```

- [ ] **Step 7: Verify wiring and build**

Run: `grep -n "update_soul\|update_memory\|systemPrompt = nil" Sources/iris/iris.swift`
Expected: `update_soul` and `update_memory` each appear twice (declaration + dispatch); `systemPrompt = nil` appears in the `update_soul` branch (and the existing `init`).

Run: `swift test --filter "MemoryToolsTests|SystemSteeringTests"`
Expected: PASS (build succeeds, tools compile and write correctly).

- [ ] **Step 8: Commit**

```bash
git add Sources/iris/MemoryManager.swift Sources/iris/iris.swift Tests/irisTests/MemoryToolsTests.swift
git commit -m "feat(memory): add update_soul/update_memory tools writing canonical paths

update_soul invalidates the cached system prompt so persona edits take effect
next turn. Closes the SOUL split-brain loop: the tool writes the same
IrisPaths.soulMd that loadSOUL reads.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Prompt/string updates

**Files (Modify):** `Sources/iris/AppState.swift`, `Sources/iris/assets/SYSTEM.md`

**Interfaces:**
- Consumes: the `update_soul`/`update_memory`/`update_user_profile` tool names (Task 4) and the new `memory/…` paths (Task 3).
- Produces: nothing (prompt copy).

- [ ] **Step 1: Update the reflection prompt (`AppState.swift:239` and `:289`)**

In both the multi-line reflection prompt (~line 239) and the `reflectionPrompt` string (~line 289), replace the sentence:

> `If so, use \`write_file\` or \`read_file\` to update \`~/.iris/skills/\`, \`update_user_profile\` to update \`USER.md\`, or update your core \`SOUL.md\`.`

with:

> `If so, use \`update_soul\` to evolve your persona, \`update_user_profile\` to update the user profile, \`update_memory\` to consolidate durable facts, and \`write_file\`/\`read_file\` under \`~/.iris/memory/skills/\` for skills.`

- [ ] **Step 2: Update the grooming prompt (`AppState.swift:241`)**

Replace `Ensure ALL memory files (\`~/.iris/skills/*\`, \`USER.md\`, \`SOUL.md\`) use the Open Knowledge Format` with `Ensure ALL memory files (\`~/.iris/memory/skills/*\`, \`~/.iris/memory/USER.md\`, \`~/.iris/memory/SOUL.md\`) use the Open Knowledge Format`.

- [ ] **Step 3: Update `Sources/iris/assets/SYSTEM.md` path references**

- In "Workspace Conventions"/"Development Workflow"/"Artifacts & Design Docs"/"Memory Formatting" sections, replace `~/.iris/skills/` with `~/.iris/memory/skills/`.
- Replace `~/.iris/library/<project>/specs/` (Development Workflow) and `~/.iris/library/<project_name>/` (Artifacts & Design Docs) with `~/.iris/memory/artifacts/<project>/specs/` and `~/.iris/memory/artifacts/<project_name>/` respectively.

- [ ] **Step 4: Verify old path references are gone**

Run: `grep -rn "iris/skills\|iris/library\|~/.iris/SOUL\|~/.iris/USER" Sources/iris/AppState.swift Sources/iris/assets/SYSTEM.md`
Expected: no `iris/library` and no bare `~/.iris/skills` (all now `~/.iris/memory/…`); no references to the old flat `~/.iris/SOUL.md` / `~/.iris/USER.md`.

Run: `swift test --filter SystemSteeringTests`
Expected: PASS (SYSTEM.md still loads with its key sections).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/AppState.swift Sources/iris/assets/SYSTEM.md
git commit -m "docs(prompt): point steering + reflection prompts at memory/ paths and write-tools

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

- **Spec coverage:** IrisPaths abstraction → Task 1. Migration (idempotent/non-destructive, SOUL dedup, WAL sidecars, timing) → Task 2 (logic) + Task 3 Step 7 (startup wiring). Consumer refactor of all ~8 hardcoders → Task 3. SOUL bug fix (write path == read path) → Task 3 (SkillManager reads `IrisPaths.default.soulMd`) + Task 4 (`update_soul` writes the same). New write-tools + system-prompt invalidation → Task 4. Prompt/SYSTEM.md updates → Task 5. Testing (IrisPaths, migrator temp-root cases, tool handlers) → Tasks 1/2/4. Layout `memory/`+`config/`+`models/`, `library/`→`artifacts/` → Tasks 1-3. Out-of-scope per-workspace `.iris/` → explicitly untouched in Task 3 Steps 4/6.
- **Placeholder scan:** none — every code and command step is concrete.
- **Type consistency:** `IrisPaths` accessors and `ensureDirectories()` (Task 1) are used with identical names in Tasks 2-4. `IrisMigrator.migrate(_:)` (Task 2) is called identically in Task 3 Step 7. `MemoryManager.paths` (Task 3) and `MemoryManager.updateSoul(content:)` (Task 4) match their test usages. `systemPrompt = nil` matches the existing `IrisEngine.systemPrompt: Content!`.
- **Note on Task 3/5 testability:** the consumer refactor and prompt copy are verified by grep + build + existing-suite runs (no new unit test), because they are path substitutions and prompt strings; the behavioral coverage lives in the IrisPaths/migrator/tool unit tests.
