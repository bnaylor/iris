# Iris Library Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Iris's permanent OKF library (`~/.iris/memory/library/`) with a seed-once shipped library-management skill and a starter README, plus a reflection-prompt nudge to contribute.

**Architecture:** `IrisPaths` gains a `libraryDir` accessor. A new `ShippedSkills` provisioner (run at startup after `IrisMigrator`) seeds two bundled assets — the library skill and a library README — into the migrated `memory/` layout, seed-if-absent so bot edits are preserved. Once seeded, the skill is discovered by the existing unchanged `SkillManager`.

**Tech Stack:** Swift, swift-testing, `Bundle.module` resource bundling, Foundation FileManager.

## Global Constraints

- Library path: `~/.iris/memory/library/` (`IrisPaths.libraryDir`), distinct from `memory/artifacts/`.
- Seeding is idempotent and non-destructive: write a file only if it is absent (never overwrite a bot-edited file).
- `ShippedSkills.seedIfNeeded(.default)` runs in `IrisApp.init()` immediately **after** `IrisMigrator.migrate(.default)`.
- Bundle assets live in `Sources/iris/assets/` (carried by the existing `.process("assets")` rule; that dir bundles under the target — same as `SYSTEM.md`). No Package.swift change expected.
- The seeded skill file must be named `SKILL.md` under `memory/skills/library/` so `SkillManager.discoverSkills()` finds it. Bundle asset names are free (`library-SKILL.md`, `library-README.md`).
- The `ShippedSkills.seed(into:librarySkill:libraryReadme:)` core takes contents as parameters (no bundle dependency) so it is unit-testable against a temp root.
- Commit messages end with: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
- Spec: `docs/specs/library_core_design.md`. Build note: full `swift test` has pre-existing UNRELATED failures (`SandboxTests`, missing Qwen GGUF) — use focused `--filter` runs.

---

## File Structure

- Modify: `Sources/iris/IrisPaths.swift` — add `libraryDir`, include it in `ensureDirectories()`.
- Create: `Sources/iris/assets/library-SKILL.md`, `Sources/iris/assets/library-README.md` — shipped content.
- Create: `Sources/iris/ShippedSkills.swift` — the seeder (`seedIfNeeded` + testable `seed` core + `bundledText`).
- Create: `Tests/irisTests/ShippedSkillsTests.swift`.
- Modify: `Tests/irisTests/IrisPathsTests.swift` — cover `libraryDir`.
- Modify: `Sources/iris/iris.swift` (`IrisApp.init()`) — wire the seeder after the migrator.
- Modify: `Sources/iris/AppState.swift` — append the library clause to both reflection prompts.

---

## Task 1: IrisPaths.libraryDir

**Files:**
- Modify: `Sources/iris/IrisPaths.swift`
- Test: `Tests/irisTests/IrisPathsTests.swift`

**Interfaces:**
- Consumes: existing `IrisPaths` (`memoryDir`, `ensureDirectories()`).
- Produces: `var libraryDir: URL` (= `memory/library`), included in `ensureDirectories()`.

- [ ] **Step 1: Add the failing assertions to `Tests/irisTests/IrisPathsTests.swift`**

In `testAccessorsComposeUnderRoot`, add after the `artifactsDir` expectation:

```swift
        #expect(p.libraryDir.path == "/tmp/iris-test-root/memory/library")
```

In `testEnsureDirectoriesCreatesBuckets`, change the `for dir in [...]` list to include `p.libraryDir`:

```swift
        for dir in [p.memoryDir, p.skillsDir, p.artifactsDir, p.libraryDir, p.configDir, p.modelsDir] {
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter IrisPathsTests`
Expected: FAIL to compile — `value of type 'IrisPaths' has no member 'libraryDir'`.

- [ ] **Step 3: Add `libraryDir` to `Sources/iris/IrisPaths.swift`**

Add the accessor immediately after the `artifactsDir` line:

```swift
    var artifactsDir: URL { memoryDir.appendingPathComponent("artifacts") }
    var libraryDir: URL { memoryDir.appendingPathComponent("library") }
```

Add `libraryDir` to the `ensureDirectories()` list:

```swift
        for dir in [memoryDir, skillsDir, artifactsDir, libraryDir, configDir, modelsDir] {
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter IrisPathsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/IrisPaths.swift Tests/irisTests/IrisPathsTests.swift
git commit -m "feat(paths): add IrisPaths.libraryDir for the permanent library

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: ShippedSkills seeder + bundle assets

**Files:**
- Create: `Sources/iris/assets/library-SKILL.md`, `Sources/iris/assets/library-README.md`
- Create: `Sources/iris/ShippedSkills.swift`
- Test: `Tests/irisTests/ShippedSkillsTests.swift`

**Interfaces:**
- Consumes: `IrisPaths` (`skillsDir`, `libraryDir`, `ensureDirectories()`) from Task 1.
- Produces: `enum ShippedSkills { static func seedIfNeeded(_ paths: IrisPaths); static func seed(into paths: IrisPaths, librarySkill: String, libraryReadme: String); static func bundledText(_ resource: String) -> String }` — consumed by Task 3.

- [ ] **Step 1: Create `Sources/iris/assets/library-SKILL.md`**

```markdown
---
type: skill
title: Library Management
description: Maintain your permanent OKF library — decide what durable knowledge to keep, organize it well, and contribute to it proactively.
tags: [library, memory, okf, curation]
timestamp: 2026-07-15
---

# Library Management

You maintain a permanent library of durable knowledge at `~/.iris/memory/library/`.

## What the library is
Your curated, permanent archive — the knowledge you deliberately choose to keep. It is
distinct from `~/.iris/memory/artifacts/`, which holds the working design docs and plans
produced while executing a task. Artifacts are process outputs; the library is durable
knowledge worth returning to.

## What belongs here
Postmortems, lessons learned, recipes and how-tos, reusable snippets, plans and instructions
worth reusing, itineraries, drafted correspondence, research notes, and any artifact you
create or are asked to save that has lasting value.

## Organize it
Keep some structure — do not dump everything flat. Group by topic, project, or type in
whatever way makes sense to you, and evolve the structure as the library grows. Record your
chosen organization in `~/.iris/memory/library/README.md` so it stays coherent over time.

## Format
Write entries as OKF Markdown: a YAML frontmatter block (`type`, `title`, `description`,
`tags`, `timestamp`) followed by the content, and cross-link related entries with Markdown
links to build a navigable graph.

## Contribute proactively
When a task produces something durable — a lesson, a reusable procedure, a decision and its
rationale, a useful draft — save it to the library without being asked. During memory
consolidation, sweep recent work for anything worth archiving, and prefer adding to an
existing entry over creating fragments.

Manage the library with your normal file tools (`read_file`, `write_file`, `run_command`).
```

- [ ] **Step 2: Create `Sources/iris/assets/library-README.md`**

```markdown
---
type: index
title: Iris Library
description: Purpose and organization of Iris's permanent knowledge library.
tags: [library, index, okf]
timestamp: 2026-07-15
---

# Iris Library

This is your permanent, curated archive of durable knowledge — postmortems, lessons, recipes,
plans, drafts, research, and any artifact worth keeping. It is distinct from
`~/.iris/memory/artifacts/` (working design docs and plans from executing tasks).

Organize this space however makes sense to you; keep some structure rather than a flat dump,
and record your chosen organization here as it evolves. Write entries in OKF Markdown and
cross-link related material.

_You may rewrite or replace this file as your library takes shape._
```

- [ ] **Step 3: Write the failing tests `Tests/irisTests/ShippedSkillsTests.swift`**

```swift
import Testing
import Foundation
@testable import iris

@Suite("ShippedSkills Tests")
struct ShippedSkillsTests {

    private func tempPaths() -> IrisPaths {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("iris-seed-\(UUID().uuidString)")
        return IrisPaths(root: root)
    }
    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    @Test("seeds the library skill and README when absent")
    func testSeedsWhenAbsent() {
        let p = tempPaths(); defer { try? FileManager.default.removeItem(at: p.root) }
        ShippedSkills.seed(into: p, librarySkill: "SKILL BODY", libraryReadme: "README BODY")
        #expect(read(p.skillsDir.appendingPathComponent("library/SKILL.md")) == "SKILL BODY")
        #expect(read(p.libraryDir.appendingPathComponent("README.md")) == "README BODY")
    }

    @Test("does not overwrite existing (bot-edited) files")
    func testIdempotentNonDestructive() {
        let p = tempPaths(); defer { try? FileManager.default.removeItem(at: p.root) }
        try? p.ensureDirectories()
        let skillDir = p.skillsDir.appendingPathComponent("library")
        try? FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try? "MY EDITS".write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try? "MY README".write(to: p.libraryDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        ShippedSkills.seed(into: p, librarySkill: "SHIPPED", libraryReadme: "SHIPPED README")

        #expect(read(skillDir.appendingPathComponent("SKILL.md")) == "MY EDITS")
        #expect(read(p.libraryDir.appendingPathComponent("README.md")) == "MY README")
    }

    @Test("bundled assets load and are non-empty")
    func testBundledAssetsLoad() {
        #expect(ShippedSkills.bundledText("library-SKILL").contains("Library Management"))
        #expect(ShippedSkills.bundledText("library-README").contains("Iris Library"))
    }
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `swift test --filter ShippedSkillsTests`
Expected: FAIL to compile — `cannot find 'ShippedSkills' in scope`.

- [ ] **Step 5: Create `Sources/iris/ShippedSkills.swift`**

```swift
import Foundation

/// Seeds shipped default content (currently the library skill + library README) into an
/// install if absent. Idempotent and non-destructive: a file is written only when missing, so
/// bot edits are preserved and a deliberately deleted file re-seeds on the next launch. Runs at
/// startup after `IrisMigrator`, so it seeds into the already-migrated `memory/` layout. Once
/// seeded, the library skill is picked up by the existing `SkillManager.discoverSkills()`.
enum ShippedSkills {

    /// Production entry point: reads the bundled assets and seeds them.
    static func seedIfNeeded(_ paths: IrisPaths) {
        seed(into: paths,
             librarySkill: bundledText("library-SKILL"),
             libraryReadme: bundledText("library-README"))
    }

    /// Testable core: seeds the provided contents, per-file seed-if-absent. An empty string
    /// skips that item (e.g. a bundle asset that failed to load).
    static func seed(into paths: IrisPaths, librarySkill: String, libraryReadme: String) {
        try? paths.ensureDirectories()
        let fm = FileManager.default

        if !librarySkill.isEmpty {
            let skillDir = paths.skillsDir.appendingPathComponent("library")
            let skillFile = skillDir.appendingPathComponent("SKILL.md")
            if !fm.fileExists(atPath: skillFile.path) {
                try? fm.createDirectory(at: skillDir, withIntermediateDirectories: true)
                try? librarySkill.write(to: skillFile, atomically: true, encoding: .utf8)
            }
        }

        if !libraryReadme.isEmpty {
            let readmeFile = paths.libraryDir.appendingPathComponent("README.md")
            if !fm.fileExists(atPath: readmeFile.path) {
                try? libraryReadme.write(to: readmeFile, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Read a bundled markdown asset by resource name (no extension). Returns "" if missing so a
    /// packaging error skips seeding rather than crashing.
    static func bundledText(_ resource: String) -> String {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return text
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter ShippedSkillsTests`
Expected: PASS (3 tests). If `testBundledAssetsLoad` can't find the resource, confirm the `.md` files are under `Sources/iris/assets/`.

- [ ] **Step 7: Commit**

```bash
git add Sources/iris/assets/library-SKILL.md Sources/iris/assets/library-README.md Sources/iris/ShippedSkills.swift Tests/irisTests/ShippedSkillsTests.swift
git commit -m "feat(library): add ShippedSkills seeder + bundled library skill/README

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Wire seeding at startup + reflection-prompt encouragement

**Files:**
- Modify: `Sources/iris/iris.swift` (`IrisApp.init()`)
- Modify: `Sources/iris/AppState.swift` (both reflection prompts)

**Interfaces:**
- Consumes: `ShippedSkills.seedIfNeeded(_:)` (Task 2).
- Produces: nothing new (integration + prompt copy).

- [ ] **Step 1: Seed at startup in `iris.swift`**

In `IrisApp.init()`, add the seed call immediately after the migrator (before the `NSApplication` setup):

```swift
    init() {
        IrisMigrator.migrate(.default)
        ShippedSkills.seedIfNeeded(.default)
        NSApplication.shared.setActivationPolicy(.regular)
```

- [ ] **Step 2: Append the library clause to the multi-line reflection prompt in `AppState.swift`**

Replace (the end of the first paragraph of the `/reflect` prompt, ~line 238):

```
for skills.

            Additionally, perform
```

with:

```
for skills. When you learn something durable — a lesson, recipe, decision, or reusable artifact — archive it to your permanent library at `~/.iris/memory/library/` (see your Library Management skill).

            Additionally, perform
```

- [ ] **Step 3: Append the library clause to the single-line reflection prompt in `AppState.swift`**

Replace (in the automatic `reflectionPrompt` string, ~line 289):

```
for skills. Output a transparent summary
```

with:

```
for skills. When you learn something durable — a lesson, recipe, decision, or reusable artifact — archive it to your permanent library at `~/.iris/memory/library/` (see your Library Management skill). Output a transparent summary
```

- [ ] **Step 4: Verify wiring, paths, and build**

Run: `grep -n "ShippedSkills.seedIfNeeded" Sources/iris/iris.swift`
Expected: one hit, immediately after `IrisMigrator.migrate(.default)`.

Run: `grep -c "memory/library/" Sources/iris/AppState.swift`
Expected: `2` (both reflection prompts updated).

Run: `swift test --filter "IrisPathsTests|ShippedSkillsTests|SystemSteeringTests"`
Expected: PASS (build succeeds; seeding + paths intact).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/iris.swift Sources/iris/AppState.swift
git commit -m "feat(library): seed library skill at startup; nudge reflection to archive

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-Review

- **Spec coverage:** `IrisPaths.libraryDir` + ensureDirectories → Task 1. Shipped-skill delivery (`ShippedSkills.seedIfNeeded`/`seed`, seed-if-absent, testable core) → Task 2. Bundled `library-SKILL.md` (OKF, the full skill content) + `library-README.md` (OKF starter) → Task 2. Startup wiring after migrator → Task 3 Step 1. Reflection-prompt encouragement → Task 3 Steps 2-3. Discovery unchanged (no SkillManager edit) → confirmed (nothing in the plan touches it). Testing (IrisPaths, seeder seed/idempotent, bundle load) → Tasks 1-2. Out-of-scope external libraries → untouched.
- **Placeholder scan:** none — every code and command step is concrete, including both full asset files.
- **Type consistency:** `libraryDir` (Task 1) is used by name in Task 2's seeder and tests. `ShippedSkills.seed(into:librarySkill:libraryReadme:)`, `seedIfNeeded(_:)`, and `bundledText(_:)` (Task 2) match Task 3's call and the tests. Bundle resource names `library-SKILL`/`library-README` match the asset filenames.
- **Note on Task 3 testability:** startup wiring and prompt copy are verified by grep + build (no new unit test), consistent with prior startup-wiring tasks; behavioral coverage lives in the Task 2 seeder tests.
