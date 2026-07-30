# Librarian Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement and seed the `librarian` skill into Iris to enforce file and workspace organization standards, resolving Issue #63.

**Architecture:** Add `Sources/iris/assets/librarian-SKILL.md` in OKF v0.1 format, register it in `ShippedSkills.swift`, reference organization rules in `SYSTEM.md`, and add unit test coverage in `LibrarianSkillTests.swift`.

---

## Tasks

- [ ] **Task 1: Create Bundled Skill Asset (`Sources/iris/assets/librarian-SKILL.md`)**
  - Add OKF v0.1 frontmatter (`name: librarian`, `description: Guidance for workspace file and directory organization...`).
  - Author procedural rules for repository management (`~/src/`), directory layout (`src/`, `docs/`, `scripts/`, `tests/`), and naming conventions.

- [ ] **Task 2: Register Skill in `ShippedSkills.swift`**
  - Add `librarian-SKILL` `SeedItem` to `ShippedSkills.seedIfNeeded(_:)`.
  - Target path: `paths.skillsDir.appendingPathComponent("librarian/SKILL.md")`.

- [ ] **Task 3: Update `SYSTEM.md` Steering Directives**
  - Ensure system prompt context includes file and workspace organization guidance.

- [ ] **Task 4: Add Unit Test Suite (`Tests/irisTests/LibrarianSkillTests.swift`)**
  - Test seeding of `librarian/SKILL.md`.
  - Test OKF frontmatter parsing and `SkillManager` discovery.

- [ ] **Task 5: Execute Test Suite and Verify**
  - Run `swift test` and ensure all suites pass cleanly.
