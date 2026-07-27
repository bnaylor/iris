---
type: design
title: run_command Transparency Refactor
description: Declutter tool-call presentation — per-command intent on run_command, grouped clean-row twisty with a live "current intent" collapsed status line.
tags: [ui, chatview, tools, transparency, steering]
timestamp: 2026-07-27
---

# run_command Transparency Refactor

Closes [#27](https://github.com/bnaylor/iris/issues/27) and [#23](https://github.com/bnaylor/iris/issues/23).

## Problem

Agentic runs currently render as a noisy alternation: per-iteration commentary (an
**agent** bubble) followed by a `[TOOL_CALL]` (a **system** message), repeated. Two
consequences:

- **#27:** each command carries its own prose commentary and its own nested raw-JSON
  expander — "doing precisely what I asked for, but a bit much."
- **#23:** `groupedMessages` (`ChatView.swift`) batches only *consecutive* system
  messages; the interleaved agent bubbles split every run, so each `[TOOL_CALL]` lands
  in its own single-element "System Event" twisty.

Both stem from the same root: per-command rationale lives in free-text agent bubbles
*between* the tool calls. Move that rationale onto the tool call itself and both improve.

## Goal

- One high-level directional line at the start of a multi-step run (ordinary agent text).
- Per-command rationale carried in an `intent` field on `run_command`, shown *with* the
  command inside a single grouped twisty of clean rows.
- Collapsed, the twisty is a live status line showing the current command's intent.

## Non-Goals

- Vibecop consuming `intent` as decision context. Separate feature. When built, it must
  obey a strict asymmetry: `intent` may **raise** scrutiny, never **lower** it (an
  injected or self-serving intent must not be grounds for approval).
- Adding `intent` to tools other than `run_command`. Start with `run_command` only.
- Reworking `groupedMessages`. #23 is fixed behaviorally (see below), not by code.
- Forcing the model to comply. Presentation tidiness is best-effort; non-compliance
  (stray narration between calls) is cosmetic only, never a correctness/safety issue.

## Design

### 1. Schema — `ToolExecutor.getTools()`

Add an optional `intent` property to `run_command`'s parameter schema
(`Sources/iris/ToolExecutor.swift`, ~line 14):

```swift
properties: [
    "command": Schema(type: "STRING", description: "The command to run in bash/zsh"),
    "intent": Schema(type: "STRING", description: "One short phrase: why you're running this command (shown to the user; keep it under ~8 words).")
],
required: ["command"]
```

`intent` is **not** in `required`. `execute` (`ToolExecutor.swift` ~line 81) reads only
`args["command"]`, so `intent` is ignored at runtime — no execution plumbing changes.

### 2. Steering — `SYSTEM.md` "Communicating While Working"

Revise the section so it directs:

- When beginning a multi-step run, state the plan in **one short line** of ordinary text
  (the directional summary) — not a play-by-play.
- For each `run_command`, put that command's rationale in its `intent` field rather than
  narrating between calls.

Keep it a directive about *where* rationale goes, not a mandate that eliminates all text.

### 3. Data flow (unchanged plumbing)

Model emits `run_command { command, intent }` → `execute` runs `command`, ignores
`intent` → the existing `[TOOL_CALL]` push (`iris.swift` ~line 516) already serializes the
full `args` to JSON, so `intent` is present in the message with no code change → the UI
parses it.

The raw JSON remains the stored message content, so copy/export still include full args;
it is simply no longer shown inline.

### 4. UI — `ChatView.swift`

**Parser (pure, unit-tested).** Extract a helper that turns a `[TOOL_CALL]` message into
displayable fields:

```swift
struct ToolCallDisplay: Equatable {
    let name: String
    let command: String?   // run_command only
    let intent: String?
}

enum ToolCallParser {
    /// Returns nil for non-tool-call text or malformed JSON.
    static func parse(_ messageText: String) -> ToolCallDisplay?
}
```

Parsing rule: require the `[TOOL_CALL]\n` prefix; decode the JSON; read `name`, and from
`args` read `command` and `intent` (each optional). Malformed JSON → `nil`.

**Row rendering (`SystemMessageContent`).** Replace the current tool-call branch (the
nested "Tool Execution: <name>" box with its own raw-JSON expander) with a clean row:

- `run_command`: `$ <command>` in a monospaced primary font; below it, `intent` as a dim
  secondary caption. Omit the caption when `intent` is absent/empty.
- Any other tool: a single row showing the tool `name` (bold), no JSON.
- Non-tool-call system text: unchanged (`fallbackView`).

**Group header + collapsed status line (`SystemGroupView`).** Let `toolCalls` be the
messages in the group that parse as tool calls.

- Header text: if every message in the group is a tool call, `"\(toolCalls.count) commands"`
  (singular "command" when 1); otherwise keep the existing `"System Event"` /
  `"System Events (N)"`.
- Collapsed with count > 1: show a **status line** = the intent of the *most recent* tool
  call in the group (its `$ command` + intent, or just intent). If the group's last
  message is a non-tool system line, show that line instead. Because the view observes the
  `messages` array, this updates automatically as new `[TOOL_CALL]`s append — a live
  "current intent."
- Expanded: every message rendered as its row (all commands + intents).
- Single-message group: render inline as one row (as today).

### 5. #23 resolution

No change to `groupedMessages`. Once rationale moves into `intent` and the model emits a
single leading declaration instead of per-call prose, the `[TOOL_CALL]`s in a run are
consecutive `.system` messages again, so they group into one twisty. If the model still
narrates between calls, groups split — accepted as cosmetic (see Non-Goals).

## Testing

**Unit (`ToolCallParser`, pure):**
- `run_command` with `command` + `intent` → both parsed.
- `run_command` with `command`, no `intent` → `intent == nil`.
- A non-`run_command` tool → `command == nil`, `name` parsed.
- Non-`[TOOL_CALL]` text → `nil`.
- Malformed JSON after the prefix → `nil`.

**Unit (executor):** `execute("run_command", args: ["command": "echo hi", "intent": "x"])`
runs the command and is unaffected by `intent` (i.e., behaves identically to without it).

**GUI-verified by the user:** clean rows render; grouped twisty collapses to a live
current-intent status line and updates as commands stream; expanding shows all
commands+intents; non-run_command tools and non-tool system lines still render sanely.

## Risks / Notes

- `intent` is model-generated: it can be inaccurate or self-serving. The UI presents it as
  the model's stated reason (dim caption tied to the command), not as fact.
- Tidy grouping and the live status line depend on model behavior; both degrade gracefully
  to the current-style split rendering when the model narrates between calls.
