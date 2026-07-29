# Implementation Plan: Deterministic Slash Commands

* **Issue**: [#7](https://github.com/bnaylor/iris/issues/7) - Implement additional slash commands
* **Spec**: `docs/specs/2026-07-28-slash-commands-design.md`
* **Date**: 2026-07-28

---

## Task List

- [ ] **Step 1: Auto-Complete Registry (`SlashCommandItem.swift`)**
  - Register new commands and subcommands in `SlashCommandItem.allCommands`.
- [ ] **Step 2: Engine Prompt Invalidation (`iris.swift`)**
  - Expose `invalidateSystemPrompt()` method on `IrisEngine` actor.
- [ ] **Step 3: SkillManager Extensions (`SkillManager.swift`)**
  - Add `readSkillBody(name:)` method to retrieve full `SKILL.md` content.
- [ ] **Step 4: AppState Slash Command Handlers (`AppState.swift`)**
  - Implement `/skills reload [name]` and `/skills show <name>`.
  - Implement `/rules` and `/rules reload`.
  - Implement `/model` and `/model <tier_or_name>`.
  - Implement `/mcp` and `/mcp reload`.
  - Implement `/facts`, `/facts search <query>`, and `/facts probe <entity>`.
  - Implement `/tokens` / `/stats`.
  - Implement `/new` and `/clear`.
  - Fix `/update` handler connecting to `UpdateManager.shared.checkForUpdates()`.
- [ ] **Step 5: Unit Tests (`SlashCommandTests.swift`)**
  - Author test cases for all new slash commands.
- [ ] **Step 6: Verification & Git Commit**
  - Verify all unit tests pass and commit.
