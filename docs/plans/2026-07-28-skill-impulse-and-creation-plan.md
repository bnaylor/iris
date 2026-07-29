# Implementation Plan: Native Skill Management & Self-Improvement Impulse

* **Issue**: [#42](https://github.com/bnaylor/iris/issues/42) - Impulse to write skills / self-improve
* **Spec**: `docs/specs/2026-07-28-skill-impulse-and-creation-design.md`
* **Date**: 2026-07-28

---

## Task List

- [ ] **Step 1: Define `create_skill` Tool Schema (`ToolExecutor.swift`)**
  - Add `create_skill` declaration to `getGeminiTools()` and handler in `executeToolCall()`.
- [ ] **Step 2: Implement Skill Creation & Prompt Invalidation (`ToolExecutor.swift` & `SkillManager.swift`)**
  - Implement file creation with OKF frontmatter and prompt cache invalidation on success.
- [ ] **Step 3: Update System Prompt Guidance (`Sources/iris/assets/SYSTEM.md`)**
  - Add explicit skill creation triggers and guidelines under `## Self-Improvement & Skills`.
- [ ] **Step 4: Add Post-Goal Reflection Trigger (`AppState.swift` & `iris.swift`)**
  - Trigger a lightweight skill evaluation prompt upon `goal_complete` execution.
- [ ] **Step 5: Unit Tests (`SkillCreationTests.swift`)**
  - Author test cases verifying `create_skill` tool execution, OKF frontmatter parsing, and file output.
- [ ] **Step 6: Verification & Git Commit**
  - Verify all unit tests pass and commit changes.
