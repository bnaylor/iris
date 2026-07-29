# Design Spec: Native Skill Management & Self-Improvement Impulse

* **Issue**: [#42](https://github.com/bnaylor/iris/issues/42) - Impulse to write skills / self-improve
* **Date**: 2026-07-28
* **Status**: Approved

---

## 1. Problem Statement

Iris currently lacks an active impulse to author skills (`SKILL.md`) during or after complex tasks. 

Root cause analysis reveals three friction points:
1. **Tooling Asymmetry:** `update_soul`, `update_user_profile`, and `update_memory` exist as native first-class tools, whereas skill creation requires generic `write_file` with manual path creation (`~/.iris/memory/skills/<name>/SKILL.md`) and OKF YAML frontmatter formatting. LLMs naturally favor explicit native tools over complex file path conventions.
2. **Timing of Reflection:** Reflection triggers only after 30 messages (`shouldReflect`), long after the specific context of a difficult task has passed. There is no post-goal or post-task evaluation step.
3. **Prompt Guidance:** `SYSTEM.md` lacks clear, actionable triggers specifying *when* a skill should be authored.

---

## 2. Proposed Architecture

### Pillar A: Native `create_skill` Tool Call

Add a native Swift tool `create_skill` (and `delete_skill`) in `ToolExecutor.swift`:

```json
{
  "name": "create_skill",
  "description": "Create or update a reusable procedural skill in the local library (~/.iris/memory/skills/<name>/SKILL.md).",
  "parameters": {
    "type": "object",
    "properties": {
      "name": { "type": "string", "description": "Short hyphenated skill identifier (e.g. gke-deployment-debug)" },
      "description": { "type": "string", "description": "Clear, high-signal summary of what this skill does and when to trigger it" },
      "body": { "type": "string", "description": "Full Markdown body containing numbered steps, exact commands, pitfalls, and verification steps" }
    },
    "required": ["name", "description", "body"]
  }
}
```

#### Execution Logic (`ToolExecutor.swift`):
1. Normalizes skill name to kebab-case (`gke-deployment-debug`).
2. Generates OKF YAML frontmatter:
   ```yaml
   ---
   name: gke-deployment-debug
   description: High-signal summary...
   type: skill
   timestamp: 2026-07-28T...
   ---
   ```
3. Writes to `~/.iris/memory/skills/<name>/SKILL.md`.
4. Automatically calls `await IrisEngine.shared.invalidateSystemPrompt()` so the new skill is discovered on the next turn.
5. Emits a clean confirmation message.

---

### Pillar B: Post-Goal & Task Skill Triggers

1. **`goal_complete` Hook:** When an autonomous loop completes via `goal_complete`, Iris appends a lightweight system reflection event before idling:
   > *"System Event [Goal Completion Reflection]: Goal completed. Evaluate the steps taken during this goal. Did you discover a non-obvious workflow, overcome a platform bug, or execute a complex multi-step sequence? If so, call `create_skill` now to save the procedure to your permanent skill library."*

2. **System Prompt Guidance (`SYSTEM.md`):**
   Add explicit guidance under `## Self-Improvement & Skills`:
   * **When to call `create_skill`:**
     - You executed a 5+ step non-trivial workflow that succeeded.
     - You overcame a non-obvious build, tool, or environment error.
     - The user instructed a specific procedure or workflow preference.
     - You discovered a reusable recipe or runbook.

---

## 3. Benefits & Impact

* **Zero Friction:** Creating a skill is a single tool call, matching `update_memory` and `update_user_profile`.
* **Automatic System Prompt Sync:** Newly created skills are immediately available in subsequent turns.
* **Proactive Self-Improvement:** Goal completion triggers prompt the agent while task context is fresh.
