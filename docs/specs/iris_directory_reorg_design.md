# ~/.iris Directory Reorganization

## Motivation

`~/.iris/` is a flat dump: bot-authored memory (`SOUL.md`, `USER.md`, `memory.md`, `skills/`,
`artifacts/`, the holographic-memory SQLite DB), human/app config (`settings.json`,
`permissions.json`, `mcp_servers.json`), downloaded `models/`, and stray artifacts all sit
side by side. The path `("~/.iris" as NSString).expandingTildeInPath` is **re-derived
independently in ~8 files**, each appending its own subpaths. That duplication has no single
source of truth, obscures the trust boundary (memory files are guard-sanitized as untrusted;
config is not), and has already produced a real bug:

- **The SOUL.md split-brain bug.** `SkillManager.loadSOUL()` reads `~/.iris/prompts/SOUL.md`,
  but there is no dedicated write tool — the bot updates its persona via generic `write_file`,
  guided by a reflection prompt that just says "your core `SOUL.md`". The bot writes
  `~/.iris/SOUL.md` (a different file the engine never reads), so persona edits silently never
  take effect. Two divergent copies now exist.

This spec segregates `~/.iris/` by ownership behind a single path abstraction, migrates
existing installs, fixes the SOUL bug by aligning the write path with the read path, and adds
first-class tools for updating the memory files (encouraging the bot to actually use them).

**Scope note:** this concerns the *home* config dir `~/.iris/`. The per-workspace `.iris/`
directory (project-local `vibecop.md`, `permissions.json`) is a separate concept and is **out
of scope** — untouched.

## Target Layout

```
~/.iris/
  memory/        # bot-authored, mutable, guard-sanitized — the bot's "mind"
    SOUL.md
    USER.md
    memory.md
    skills/
    artifacts/
    holographic_memory.sqlite        (+ -shm, -wal sidecars)
  config/        # human/app config, NOT bot-authored
    settings.json
    permissions.json
    mcp_servers.json
  models/        # downloaded model bundles — resolved path unchanged
```

No `cache/` bucket: nothing in code writes disposable files, so there is no consumer to
justify it (YAGNI). It can be added later if a code writer appears.

## Components

### 1. `IrisPaths` — single source of truth

A value type that owns every home-directory path. Injectable root makes it and the migrator
unit-testable against a temp directory.

```swift
struct IrisPaths {
    let root: URL                       // default: ~/.iris

    // memory/
    var memoryDir: URL                  // root/memory
    var soulMd: URL                     // memory/SOUL.md
    var userMd: URL                     // memory/USER.md
    var memoryMd: URL                   // memory/memory.md
    var skillsDir: URL                  // memory/skills
    var artifactsDir: URL               // memory/artifacts
    var holographicDB: URL              // memory/holographic_memory.sqlite

    // config/
    var configDir: URL                  // root/config
    var settingsJSON: URL               // config/settings.json
    var permissionsJSON: URL            // config/permissions.json
    var mcpServersJSON: URL             // config/mcp_servers.json

    // models/ (resolved path unchanged from today)
    var modelsDir: URL                  // root/models

    func ensureDirectories() throws     // create memory/, config/, models/ if absent

    static let `default` = IrisPaths(root: ~/.iris)
}
```

All current hardcoders are refactored to read from `IrisPaths` (`.default` in production):
`SkillManager` (SOUL, skills), `MemoryManager` (USER, memory), `HolographicMemoryManager`
(DB), `PermissionManager` (global `permissions.json` only — its workspace path is untouched),
`HookManager` (`settings.json`), `MCPManager` (`mcp_servers.json`), `AuxiliaryModelManager`,
`CoreMLEvaluator`, `LlamaCPPEngine`, `ModelDownloader` (all `models/`). The hardcoded absolute
path in `TestTokenizer` is updated too.

Managers that need test injection (see Testing) hold an `IrisPaths` defaulting to `.default`.

### 2. `IrisMigrator` — one-shot startup migration

A pure function `IrisMigrator.migrate(_ paths: IrisPaths)` that brings an old flat install to
the new layout. Properties:

- **Idempotent** — re-running is a no-op.
- **Non-destructive** — moves, never deletes (one sanctioned exception below). A move happens
  **only if the destination does not already exist**, so a partially-migrated or
  already-migrated install is safe.
- **Fresh installs** — no old files to move; it just ensures the new directories exist.

Moves performed (old → new):

| Old | New |
| --- | --- |
| `~/.iris/prompts/SOUL.md` | `memory/SOUL.md` |
| `~/.iris/USER.md` | `memory/USER.md` |
| `~/.iris/memory.md` | `memory/memory.md` |
| `~/.iris/skills/` | `memory/skills/` |
| `~/.iris/library/` | `memory/artifacts/` |
| `~/.iris/holographic_memory.sqlite` (+ `-shm`, `-wal`) | `memory/…` |
| `~/.iris/settings.json` | `config/settings.json` |
| `~/.iris/permissions.json` | `config/permissions.json` |
| `~/.iris/mcp_servers.json` | `config/mcp_servers.json` |

**SOUL dedup (sanctioned deletion):** `prompts/SOUL.md` (the copy the engine actually reads)
becomes `memory/SOUL.md`. The redundant stray `~/.iris/SOUL.md` is **deleted** — the user has
the canonical copy elsewhere and explicitly authorized removing it. This is the migrator's only
deletion; it is guarded to run only when `memory/SOUL.md` has been established from the
read-copy, so persona content is never lost to it.

**Timing (critical):** the migrator must run at launch **before any manager opens a migrated
file** — in particular before `HolographicMemoryManager` opens the SQLite DB (moving an open
WAL database corrupts it) and before `SkillManager`/`MemoryManager` read persona/profile.
`IrisMigrator.migrate` is therefore invoked once, synchronously, at the very start of app
launch (in `IrisApp.init()` / earliest bootstrap), before the singletons are used, and calls
`ensureDirectories()` first.

### 3. Memory write-tools

Give the bot first-class tools that write to the `IrisPaths`-resolved canonical locations, so
it never guesses a path (closing the SOUL bug at the source and encouraging use). Mirror the
existing `update_user_profile` wiring (`FunctionDeclaration` in `iris.swift`; dispatch branch
that calls a `MemoryManager` method).

- **`update_soul`** — overwrite `memory/SOUL.md`. Handler also **invalidates the cached system
  prompt** (`ensureSystemPrompt` caches `systemPrompt`; reset it so the new SOUL takes effect
  next turn).
- **`update_memory`** — overwrite `memory/memory.md`.
- **`update_user_profile`** — already exists; repointed at `memory/USER.md` via the refactor.

All three memory-file writers are consolidated in `MemoryManager` (which already owns
`USER.md`/`memory.md`), writing through `IrisPaths`. `SkillManager.loadSOUL()` reads
`IrisPaths.default.soulMd` — the same file `update_soul` writes.

### 4. Prompt/string updates

- `AppState` reflection + grooming prompts: replace `~/.iris/skills/`, bare `USER.md`/`SOUL.md`
  references with the new `memory/…` paths, and name the write-tools explicitly ("use
  `update_soul`, `update_user_profile`, and `update_memory` to consolidate; use `write_file`
  under `~/.iris/memory/skills/` for skills").
- `SYSTEM.md` (shipped steering): update its `~/.iris/skills/` and `~/.iris/library/…`
  references to `~/.iris/memory/skills/` and `~/.iris/memory/artifacts/…`.

## Testing

- **`IrisPaths`**: given a known root, every accessor composes the expected path
  (`root/memory/SOUL.md`, `root/config/settings.json`, `root/models`, …).
- **`IrisMigrator`** against a temp root (pure, no globals):
  - fresh install (no old files) → creates `memory/`, `config/`, `models/`; moves nothing.
  - full old flat layout → every file lands at its new path; old locations empty.
  - idempotent → a second `migrate` call changes nothing.
  - destination exists → an old file is **not** moved over an existing new file (no overwrite).
  - SOUL dedup → `prompts/SOUL.md` → `memory/SOUL.md`; stray `~/.iris/SOUL.md` removed.
  - holographic DB → `.sqlite`, `-shm`, `-wal` all move together.
- **Write-tools**: `MemoryManager` methods (`updateSoul`/`updateMemory`/`updateUserProfile`),
  exercised with an injected temp-root `IrisPaths`, write to `memory/SOUL.md`,
  `memory/memory.md`, `memory/USER.md` respectively. The tool declarations + dispatch wiring in
  `iris.swift`, and the `update_soul` system-prompt-cache invalidation, are verified by
  build + grep (consistent with how the SYSTEM.md wiring task was verified).

## Risks & Notes

- **WAL database move.** Must happen before the DB is opened (see Timing). The migrator moves
  the `.sqlite` plus its `-shm`/`-wal` sidecars as a set; if the DB was already opened at the
  new location on a prior run, the destination-exists guard skips it.
- **Blast radius.** ~8 files change from hardcoded strings to `IrisPaths`. Each is a
  mechanical, one-to-one substitution; the resolved `models/` path is unchanged, so model
  consumers are refactor-only (no migration, no behavior change).
- **Bot-facing path references.** Any skill or memory the bot previously wrote referencing old
  paths (e.g. `~/.iris/skills/…`) will be migrated on disk; the prompt updates keep future
  writes pointed at the new tree.
- **Per-workspace `.iris/`** is deliberately untouched — different concept, different owner.

## Out of Scope

- The per-workspace `.iris/` directory (vibecop, workspace permissions).
- A `cache/` bucket (no code writer today).
- A dedicated CoreML/models re-layout (models path is unchanged).
