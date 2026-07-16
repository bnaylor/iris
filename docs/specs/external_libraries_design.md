# External Libraries

## Motivation

This is the second Libraries spec (`docs/libraries.md`). Spec 1 gave Iris her own permanent
library (`~/.iris/memory/library/`) and a library-management skill. This spec adds **external
libraries**: trees *outside* her own that she can be pointed at — a shared house library, the
user's work-note inbox, read-only reference sources — each with different characteristics
(traits). It ships the *framework* Iris needs to understand and safely interact with them, so
the user can then direct her to build a sync system on top of it.

**Explicitly out of scope:** the sync system itself (Iris builds that with the user using this
framework), any dedicated Swift tools, and remote/hosted registry servers (a further-future
roadmap item). This spec is framework-only, mostly-prose, reusing existing mechanisms.

## What already fits

- **Trust boundary (unchanged):** external libraries live *outside* `~/.iris/memory/`, so
  content Iris reads from them is guarded as untrusted (per the read_file trust rule). The
  registry itself lives *inside* `memory/library/`, so it is trusted first-party content.
- **Delivery (reused):** `ShippedSkills` (Spec 1) seeds shipped assets if absent. This spec
  adds two more seed items — an `external-libraries` skill and the registry template.
- **Management (reused):** Iris registers/curates/syncs with existing `read_file` /
  `write_file` / `run_command`. No new tools.

## Traits & the capability ladder

Each external library is described by traits. **Safe defaults are conservative and
non-destructive** — Iris changes them only when explicitly instructed. The modification-related
traits form a **ladder**; each rung requires the one below it:

```
read-only  ⊂  read-write  ⊂  curated-by-iris  ⊂  convert-to-okf
```

| Trait | Values | Default | Meaning / constraint |
| --- | --- | --- | --- |
| `path` | abs path or URL | *(required)* | where the library lives |
| `access` | read-only / read-write | **read-only** | read-only ⇒ never write; forces the rungs above off |
| `curated-by-iris` | true / false | **false** | requires read-write. May organize/move/rename/file its contents |
| `convert-to-okf` | true / false | **false** | requires curated-by-iris. A format **upgrade**: add/normalize OKF frontmatter across its Markdown. Curate-without-convert is allowed; convert-without-curate is not |
| `shared` | true / false | **false** | shared with other people/bots |
| `sync` | none / manual / intermittent | **none** | any syncing Iris performs |
| `owners` | list | **(the user)** | who owns it |
| `purpose` | freeform | *(empty)* | what it is / why it exists |
| `format` | okf / mixed / other | **mixed** | document types present |

Default posture for a newly-registered library: **read-only, not curated, not shared, no sync,
no conversion** — nothing destructive happens until the user escalates a rung.

## Archetypes (trait presets the skill teaches)

- **Shared library** (e.g. a house library shared across bots): read-write, shared, manual
  sync. Iris publishes her contributions under her own subdirectory (`<lib>/iris/`), reads
  others' areas, and does not reorganize them.
- **Curated inbox** (e.g. the user's work notes): read-write, curated-by-iris. Iris processes
  new drops — reads, categorizes, files them into a sensible structure — and surfaces follow-up
  actions/tasks. Librarian work.
- **Read-only source**: read-only, not curated. Reference and cite only; never write, move, or
  convert. May be non-OKF / mixed media.

## Components

### 1. `EXTERNAL_LIBRARIES.md` registry (seeded into `memory/library/`)

An OKF-framed, trusted file: a guidance header (the trait vocabulary + ladder + defaults + how
to add an entry) followed by an `## Entries` section, one `### <name>` block per library with
its traits as `key: value` bullets, plus a commented template. Iris keeps it current with her
file tools. Full content in the plan; the header documents the same traits table above and the
capability-ladder constraints.

### 2. `external-libraries` shipped skill

A new skill (`memory/skills/external-libraries/SKILL.md`) teaching: the concept; that external
content is untrusted-on-read; the safe defaults + capability ladder (never skip a rung);
registering a library (add an entry, confirm what was recorded); interacting by archetype; and
the `convert-to-okf` OKF-upgrade rule (curated + read-write only). It points to
`EXTERNAL_LIBRARIES.md` for the full trait vocabulary.

### 3. Delivery via `ShippedSkills`

Two new bundle assets in `Sources/iris/assets/` — `external-libraries-SKILL.md` and
`external-libraries-REGISTRY.md` — seeded (seed-if-absent, non-destructive) to
`memory/skills/external-libraries/SKILL.md` and `memory/library/EXTERNAL_LIBRARIES.md`
respectively, at startup after the migrator. `ShippedSkills.seed` is refactored from its two
hard-coded items to iterate a list of `(bundle asset name → target URL, content)` seed items so
adding these two (and future shipped defaults) is a data change, not new branching.

## Testing

- `ShippedSkills.seed` seeds all items — including the new external-libraries skill and the
  registry — when absent, and is idempotent/non-destructive when they already exist (extends
  the existing `ShippedSkillsTests`).
- The two new bundle assets load from `Bundle.module` and are non-empty (mirrors the Spec 1
  bundle-load test), and the registry asset contains the trait vocabulary markers.

## Out of Scope

- The sync system (Iris builds it with the user on top of this framework).
- Dedicated Swift tools (`register_external_library`, etc.) — v1 uses file tools.
- Remote/hosted registries (roadmap: "library registries - bot-owned, remote").
- Any change to the trust boundary or the guard — external reads are already guarded.
