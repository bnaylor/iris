# Tool-Call Intents (all tools) — Design

* **Issue**: [#31](https://github.com/bnaylor/iris/issues/31) — Add intents to all tool calls
* **Builds on**: [#27](https://github.com/bnaylor/iris/issues/27) — `intent` on `run_command`
* **Date**: 2026-07-28
* **Status**: Approved

## Overview

#27 added an optional `intent` field to `run_command` so the model attaches a one-line rationale that the UI shows next to the call. #31 extends that to **every** tool.

Key finding: the display path is **already generic**. `ToolCallParser.parse` reads `args["intent"]` for any tool, and `SystemMessageContent.toolCallRow` renders the intent caption regardless of tool type. So the only work is making the model *offer* an `intent` field on every tool's schema.

## Non-Goals

- No UI changes — the tool-call row already renders `intent` for any tool.
- No change to how the model's `intent` value is consumed at execution time (executors read their own named args and ignore `intent`, exactly as `run_command` does today).
- No new per-tool `intent` semantics — one uniform field/description for all tools.

## Design

### 1. Central intent augmenter (replaces per-tool edits)

Add one helper that injects an optional `intent` property into a tool's parameter schema, and apply it **once** to the fully-assembled tool list rather than editing ~14 schemas by hand (which also means every future tool is covered automatically).

```swift
// New: Sources/iris/ToolIntent.swift
enum ToolIntent {
    static let description =
        "One short phrase: why you're making this tool call (shown to the user)."

    /// Returns the tools with an optional `intent` STRING added to each tool's
    /// parameter schema. Idempotent (skips tools that already declare `intent`);
    /// tools with no parameters get a fresh OBJECT schema carrying only `intent`.
    /// `intent` is never added to `required`.
    static func augment(_ tools: [FunctionDeclaration]) -> [FunctionDeclaration]
}
```

Behavior per tool:
- `parameters == nil` → set `parameters = Schema(type: "OBJECT", properties: ["intent": Schema(type: "STRING", description: ToolIntent.description)], required: nil)`.
- `parameters.properties` present, no `intent` key → add the `intent` property; leave `required` untouched.
- `intent` already present → unchanged (idempotent).

Applied in `iris.swift` immediately after the tool list is assembled (after `executor.getTools()` and all `toolsList.append(...)` calls), **before** the `restrictToGoalComplete` filter and the `fireBeforeToolSelection` hook, so every offered tool carries `intent`.

### 2. Remove `run_command`'s hand-added `intent`

Delete the `intent` property added to `run_command` in `ToolExecutor.getTools()` (#27). Intent now comes from the augmenter for a single source of truth and one consistent description across all tools.

### 3. Steering (`SYSTEM.md`)

Rewrite the `## Communicating While Working` guidance in two ways:

1. **Generalize the per-tool intent guidance** from `run_command`-specific to: for **every** tool call, put a one-line rationale in the tool's `intent` field rather than narrating between calls; the UI shows it beside the call.

2. **Strengthen the high-level declaration** from the current soft phrasing to a firmer, *triggered, position-specific* directive (better compliance than pleading; still probabilistic — no mechanical enforcement, by decision):

   > When a turn will involve more than one tool call, or any multi-step work, your **first output — before the first tool call — must be a single sentence** stating what you're about to do and why. One line, up front, then act; don't narrate each step (the per-tool `intent` fields carry that). Skip the orientation line only for a single quick action.

   Note in the design: this is best-effort steering, not enforcement — a mechanical "declare your plan" nudge is explicitly out of scope for #31.

### 4. UI

No change. Verified: `ToolCallParser` and `toolCallRow` already handle `intent` for any tool.

## Data Flow (unchanged from #27, now for all tools)

model emits `<tool> { …args, intent }` → executor/handler runs using its named args, ignores `intent` → the existing `[TOOL_CALL]` push serializes full `args` (so `intent` rides along) → `ToolCallParser` → `toolCallRow` shows the tool name/command + the intent caption.

## Testing

- **`ToolIntentTests`** (new): `augment(_:)` adds an optional `intent` to each tool (property present, not in `required`); is idempotent for a tool that already has `intent`; wraps an OBJECT schema for a params-less tool.
- **`RunCommandIntentTests`** (update): #27's test asserts `ToolExecutor.shared.getTools()` carries `run_command.intent`. Since intent moves to the augmenter, update it to assert the augmented list (or `ToolIntent.augment(getTools())`) carries an optional `intent` on `run_command`, and that `execute` still ignores `intent`.
- `ToolCallParserTests` already cover generic `intent` display and need no change.

## Risks / Notes

- `goal_complete` gains `intent` alongside its `summary`. Optional, so the model omits it when redundant. Uniformity chosen over exemption.
- The augmenter runs before `restrictToGoalComplete` filtering, so the soft-stop summary turn's `goal_complete` still carries `intent` (harmless).
