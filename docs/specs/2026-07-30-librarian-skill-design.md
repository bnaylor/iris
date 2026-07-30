# Librarian Skill — Workspace & File Organization — Design Spec

* **Issue**: [#63](https://github.com/bnaylor/iris/issues/63) - Add Librarian skill - basic file organization
* **Date**: 2026-07-30
* **Status**: Approved

## 1. Overview

Agents naturally default to dropping new files, scripts, or temporary documentation into the root `./` directory of whichever workspace they are currently in. This creates workspace pollution ("ants in the workspace") and obscures project structure.

The **Librarian Skill** is a shipped default skill seeded into every Iris installation at `~/.iris/memory/skills/librarian/SKILL.md`. It teaches Iris structured workspace hygiene:
- Cloning repositories into structured locations (`~/src/<repo-name>`).
- Placing code, scripts, documentation, and tests in sensible subdirectories (`src/`, `docs/`, `scripts/`, `assets/`, `tests/`).
- Adhering to layout conventions for specs (`docs/specs/YYYY-MM-DD-*.md`), plans (`docs/plans/YYYY-MM-DD-*.md`), and reviews (`docs/reviews/YYYY-MM-DD-*.md`).
- Avoiding loose files in `$HOME` or root workspace directories.

## 2. Architecture & Seeding

1. **Bundled Asset (`Sources/iris/assets/librarian-SKILL.md`)**:
   An Open Knowledge Format (OKF v0.1) skill markdown file containing YAML frontmatter (`name: librarian`, `description: ...`) and procedural guidelines for file and directory layout.

2. **ShippedSkills Registration (`Sources/iris/ShippedSkills.swift`)**:
   Includes `librarian-SKILL` in `ShippedSkills.seedIfNeeded(.default)` so it is automatically seeded into `~/.iris/memory/skills/librarian/SKILL.md` on Iris startup.

3. **System Steering Alignment (`Sources/iris/assets/SYSTEM.md`)**:
   References the Librarian skill and file layout guidelines so system prompt context guides Iris to maintain clean directory organization.

## 3. Core Guidelines Enforced by the Librarian Skill

- **Repository Management:** Always clone or create project repositories under `~/src/` or `~/work/`. Never create repos directly in `$HOME`.
- **Directory Layout:**
  - `src/` or `Sources/` for implementation code.
  - `docs/` for documentation, with mandatory subdirectories for specs (`docs/specs/YYYY-MM-DD-*.md`), plans (`docs/plans/YYYY-MM-DD-*.md`), and reviews (`docs/reviews/YYYY-MM-DD-*.md`).
  - `scripts/` for operational, automation, or helper scripts.
  - `tests/` or `Tests/` for unit and integration test suites.
- **No Loose Root Files:** Never write generic temporary scripts (`test.py`, `script.sh`, `temp.md`) into root `./`. Place them in dedicated subdirectories or project workspace directories.
- **Descriptive Naming:** Enforce date-prefixed, hyphen-separated kebab-case naming for documentation and assets.

## 4. Verification & Testing

- Unit tests in `Tests/irisTests/LibrarianSkillTests.swift` verify:
  - `librarian-SKILL.md` is valid OKF markdown with valid frontmatter.
  - `ShippedSkills` seeds `librarian/SKILL.md` idempotently.
  - `SkillManager` discovers the `librarian` skill.
