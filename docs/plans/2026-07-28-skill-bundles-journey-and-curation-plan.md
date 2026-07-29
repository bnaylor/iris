# Implementation Plan: Skill Bundles, Journey Timeline & Autonomous Curator

* **Issue**: [#44](https://github.com/bnaylor/iris/issues/44) - Further tweaks to skill-curation
* **Spec**: `docs/specs/2026-07-28-skill-bundles-journey-and-curation-design.md`
* **Date**: 2026-07-28

---

## Task List

- [ ] **Step 1: Implement Skill Bundle Manager (`SkillBundleManager.swift`)**
  - Add `SkillBundleManager` to persist `~/.iris/memory/bundles.json`.
  - Add `/bundle` command handlers in `AppState.swift` and `SlashCommandItem.swift`.
- [ ] **Step 2: Implement `/journey` Learning Timeline (`JourneyManager.swift`)**
  - Build `JourneyManager` to scan OKF frontmatter across memories, skills, and FactStore.
  - Add `/journey` command handler in `AppState.swift` and `SlashCommandItem.swift`.
- [ ] **Step 3: Implement Autonomous Skill Curator (`SkillCurator.swift`)**
  - Build `SkillCurator` to grade skills against OKF rubric, prune corrupt skills, and write `~/.iris/memory/curator/REPORT.md`.
  - Add `/skills curate` subcommand handler in `AppState.swift`.
- [ ] **Step 4: Unit Tests (`SkillCurationAdvancementsTests.swift`)**
  - Author test suite covering skill bundles, journey timeline scanning, and curation reporting.
- [ ] **Step 5: Verification & Git Commit**
  - Verify all unit tests pass and commit.
