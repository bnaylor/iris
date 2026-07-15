# Iris Library — Core

## Motivation

`docs/libraries.md` introduces "Libraries" as a core Iris concept: a permanent, curated OKF
archive of durable knowledge that Iris maintains and contributes to proactively, plus (later)
external libraries Iris can be pointed at. The `~/.iris` reorganization already renamed the
old `library/` to `memory/artifacts/` specifically to free `memory/library/` for this feature.

This spec is the **own-library core** (the first of two): the `memory/library/` archive, a
shipped, seed-once library-management **skill** (establishing the reusable shipped-skill
delivery mechanism), a seeded starter README, and a prompt nudge to contribute. External
libraries, the `EXTERNAL_LIBRARIES.md` registry, traits, curation/sync, and read-only sources
are **out of scope** — they become a second spec that reuses the delivery mechanism built here.

## Concepts

- **The library** (`~/.iris/memory/library/`): Iris's permanent, self-organized OKF archive —
  the durable knowledge she deliberately keeps (postmortems, lessons, recipes, reusable
  snippets, plans/instructions worth reusing, itineraries, drafts, research notes).
- **Distinct from `memory/artifacts/`**: artifacts hold the working design docs and plans
  produced while *executing a task* (the dev workflow). The library is durable knowledge worth
  returning to. Artifacts are process outputs; the library is curated knowledge. The skill
  states this line explicitly so Iris doesn't conflate them.
- **Iris owns the organization**: some structure, not a flat dump; grouped however makes sense
  to her, evolving over time, recorded in the library's README.

## Components

### 1. `IrisPaths.libraryDir`

Add one accessor and include it in directory creation:

```swift
var libraryDir: URL { memoryDir.appendingPathComponent("library") }   // ~/.iris/memory/library
```

`ensureDirectories()` gains `libraryDir` so the bare archive always exists.

### 2. Shipped-skill delivery — `ShippedSkills` (the reusable mechanism)

A small provisioner that seeds shipped defaults into an install if absent — idempotent and
non-destructive (never overwrites an existing, possibly bot-edited, file). Two shipped assets
live in the app bundle (`Sources/iris/assets/`), the same bundling path SYSTEM.md uses:

- `library.SKILL.md` → seeded to `~/.iris/memory/skills/library/SKILL.md`
- `library-README.md` → seeded to `~/.iris/memory/library/README.md`

```swift
enum ShippedSkills {
    /// Production entry point: reads the bundled assets and seeds them.
    static func seedIfNeeded(_ paths: IrisPaths)

    /// Testable core: seeds the provided contents into `paths`, per-file seed-if-absent.
    static func seed(into paths: IrisPaths, librarySkill: String, libraryReadme: String)
}
```

Rules:
- Seed `library/SKILL.md` only if that file is absent (bot edits are preserved; a deliberate
  delete re-seeds next launch — acceptable for a core skill).
- Seed `library/README.md` only if absent.
- `ensureDirectories()` (called first) guarantees `memory/skills/` and `memory/library/` exist.

**Timing:** `seedIfNeeded(.default)` runs at startup in `IrisApp.init()` **immediately after**
`IrisMigrator.migrate(.default)` — so it seeds into the already-migrated `memory/skills/` and
`memory/library/` locations. Once seeded, the skill is discovered by the existing
`SkillManager.discoverSkills()` with a real readable path; no discovery changes are needed.

The `seed(into:librarySkill:libraryReadme:)` core takes the contents as parameters so it is
unit-testable against a temp-root `IrisPaths` with no bundle dependency.

### 3. Shipped `library.SKILL.md`

OKF-framed skill teaching library management. (`SkillManager.parseFrontmatter` reads
`description:` and falls back to the folder name `library` for the skill name, so OKF
frontmatter is compatible with discovery.)

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

### 4. Shipped `library-README.md` (starter, seeded into the library)

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

### 5. Prompt encouragement

Append one clause to the `AppState` reflection/grooming prompt (the memory-consolidation
trigger): during consolidation, archive any durable learnings, recipes, decisions, or
artifacts worth keeping to `~/.iris/memory/library/` (per the Library Management skill). This
reinforces the "contribute proactively" CUJ; the discovered skill summary already surfaces the
skill itself, so SYSTEM.md is left untouched.

## Testing

- **`IrisPaths`**: `libraryDir` composes to `<root>/memory/library`; `ensureDirectories()`
  creates it (extend `IrisPathsTests`).
- **`ShippedSkills.seed(into:librarySkill:libraryReadme:)`** against a temp root:
  - Fresh install → writes `memory/skills/library/SKILL.md` and `memory/library/README.md`
    with the provided contents.
  - Idempotent/non-destructive → pre-write an edited `SKILL.md`; after `seed`, it is unchanged
    (bot edits preserved); same for the README.
- **Bundle assets present**: `library.SKILL.md` and `library-README.md` load from
  `Bundle.module` and are non-empty (mirrors `SystemSteeringTests`).
- **Startup wiring** (`seedIfNeeded` after the migrator in `IrisApp.init()`) is verified by
  build + grep (consistent with prior startup-wiring tasks).

## Risks & Notes

- **Discovery runs the seeded skill through the guard.** `SkillManager.discoverSkills()`
  sanitizes each `SKILL.md` at `.tier3_canary` (as it does for SOUL and all skills). If Tier 3's
  canary aux-model is unavailable and advanced protection is enabled, that path can fail closed —
  a pre-existing behavior affecting *all* skills/SOUL, not introduced here, but the library skill
  may be the first shipped skill to exercise it on a given install. Verify on-device that the
  seeded skill actually surfaces in the discovered-skills summary; if it does not, that is a
  pre-existing guard/canary issue to address separately, not a defect in this feature.
- **Seeded content is trusted but discovered as a normal (guard-processed) skill** — an accepted
  consequence of the "seed once, then it's hers" delivery choice (it must be editable and have a
  real readable path).

## Out of Scope (→ Spec 2: External Libraries)

- External libraries: registering trees Iris is pointed at.
- `~/.iris/memory/library/EXTERNAL_LIBRARIES.md` registry and the traits schema (read-only /
  curated-by-iris / shared / sync / owners / convert-to-okf / …), with safe non-destructive
  defaults.
- Curation/librarian behaviors (process/categorize dropped notes, generate actions) and
  read-only info sources (non-OKF, mixed media).
- Any dedicated library *tools* — v1 manages the library with existing `read_file`/`write_file`.
