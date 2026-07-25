# Dual-Layer Sandbox Routing (Piece 2a)

## Motivation

Piece 1 gave every conversation its own persistent sandbox container, but *whether* a command
is sandboxed is still a single global boolean (`enableSandboxing`): on → everything sandboxed,
off → everything on the host. There is no distinction between the **main agent** (doing the
user's real work on their Mac) and **subagents** (running untrusted/exploratory code). Today,
if the main agent runs on the host, subagents do too — losing the isolation that is exactly
where it matters most.

This spec implements the **dual-layer** model: the **main agent runs where the user chooses
(host by default, sandboxed per policy)**, while **subagents are always sandboxed**. It is the
direct answer to the roadmap's *"allow even the main agent's access to be sandboxed —
per-workspace?"* plus Iris's own proposal that subagents be isolated by default.

This is **Piece 2a**. The host-side restriction layer for the main agent — directory
anchoring, an "open mode" for home-dir access, `/tmp` unrestricted — is **Piece 2b** and out
of scope here.

**Explicitly out of scope:** Piece 2b (host restrictions), any change to `read_file`/`write_file`
(they remain on the host), and the sandbox *mechanism* itself (Piece 1's `SandboxSessionManager`
is reused unchanged).

## Policy model

`enableSandboxing` is **reinterpreted as the sandboxing feature master switch**:

- **Off (default) → everything on the host, no warnings.** Byte-identical to today's behavior;
  users who don't want sandboxing see no change and no noise.
- **On → the dual-layer is active.**

When the master switch is **on**, a command's routing is decided per principal:

- **Subagent → always sandboxed.** If the container runtime is unavailable → **warn loudly,
  run on host** (see No-runtime fallback).
- **Main agent → resolve a preference through a cascade, highest precedence first:**
  1. **Per-conversation override** (`Conversation.mainAgentSandbox`, `nil` = inherit)
  2. **Per-workspace override** (`<workspace>/.iris/sandbox.json`)
  3. **Global default** (`ConfigManager.mainAgentSandboxDefault`, default `host`)

  If the resolved preference is `sandboxed` and the runtime is available → sandboxed; if
  `sandboxed` but the runtime is unavailable → warn + host; if `host` → host (no warning).

Only `run_command` is routed. `read_file`/`write_file` stay on the host as before, and the
Vibecop/permission guardrails still decide *whether* a command runs, before routing decides
*where*.

### No-runtime fallback

When a sandbox was intended (a subagent, or a main agent resolved to `sandboxed`) but
`SandboxingManager.shared.isContainerInstalled` is false, the command runs on the host and a
**one-per-conversation** system notice is emitted:

```
[sandbox] No container runtime available — running on the host WITHOUT isolation. Install it
via /sandbox to enable sandboxing.
```

De-duped per conversation so it appears once, not on every command.

### Migration / backward-compatibility

Reinterpreting `enableSandboxing` must not silently change the experience of a user who has it
on today (where the main agent is currently sandboxed):

- Add `ConfigManager.mainAgentSandboxDefault` (`host` | `sandboxed`, default `host`).
- **One-time migration:** on first launch after upgrade, if `enableSandboxing == true` and no
  `MAIN_AGENT_SANDBOX_DEFAULT` key exists yet, seed it to `sandboxed`. Existing sandboxed-main
  users keep a sandboxed main agent; fresh installs default to `host` (the dual-layer vision).

## Components

Each unit is small and independently testable.

### `SandboxPolicy` (new file, pure logic)

```swift
enum SandboxPref: String, Codable, Sendable { case host, sandboxed }

enum Principal: Sendable { case main, subagent }

enum SandboxDecision: Equatable, Sendable {
    case sandboxed
    case host(warnNoRuntime: Bool)
}

enum SandboxPolicy {
    /// Pure resolution — no I/O. All inputs are provided by the caller.
    static func resolve(
        masterEnabled: Bool,
        principal: Principal,
        perConversation: SandboxPref?,
        perWorkspace: SandboxPref?,
        globalDefault: SandboxPref,
        runtimeAvailable: Bool
    ) -> SandboxDecision
}
```

Resolution:
- `masterEnabled == false` → `.host(warnNoRuntime: false)`.
- `principal == .subagent` → intended `sandboxed`.
- else intended = `perConversation ?? perWorkspace ?? globalDefault`.
- intended `sandboxed`: `runtimeAvailable ? .sandboxed : .host(warnNoRuntime: true)`.
- intended `host`: `.host(warnNoRuntime: false)`.

### Per-workspace override loader (new, thin I/O)

`SandboxPolicy.perWorkspaceOverride(workspace: String?) -> SandboxPref?` reads
`<workspace>/.iris/sandbox.json` (shape `{"mainAgent":"host"|"sandboxed"}`), returning `nil`
when absent/unreadable. Kept separate from `resolve` so the policy stays pure and testable.
A writer `SandboxPolicy.setWorkspaceOverride(_:for:)` persists it (used by the `/sandbox`
command).

### `Principal` on `IrisEngine`

`IrisEngine` gains a `let principal: Principal` set at construction: `.main` from
`AppState`, `.subagent` from `SubagentManager`. This is the authoritative source for routing.

### `Conversation` fields

- `mainAgentSandbox: SandboxPref?` (default `nil` = inherit) — the per-conversation override the
  sidebar toggle writes.
- `isSubagent: Bool` (default `false`, set `true` when `SubagentManager` creates the
  conversation) — so the UI can hide the toggle for subagent conversations.

Both decode with `decodeIfPresent` for backward-compatible loading of old saved conversations.

### Routing decision in the engine

Resolution happens in `IrisEngine.executeFunctionCall` (which already holds `conversationId`
and `workspacePath` and can read `AppState`), not in `ToolExecutor` (which stays a dumb
executor). For a `run_command` call the engine:
1. reads the conversation's `mainAgentSandbox` and calls
   `SandboxPolicy.perWorkspaceOverride(workspace:)`,
2. calls `SandboxPolicy.resolve(...)` with `masterEnabled: ConfigManager.enableSandboxing`,
   `runtimeAvailable: SandboxingManager.shared.isContainerInstalled`,
3. if `.host(warnNoRuntime: true)` and this conversation hasn't been warned yet → `pushToUI`
   the notice and record the conversation as warned,
4. passes a resolved `useSandbox: Bool` into `executeToolWithHooks` → `executor.execute` →
   `runCommand`.

### `ToolExecutor` change

`execute`/`runCommand` gain `useSandbox: Bool` (default `false`). `runCommand` replaces its
internal `ConfigManager.shared.enableSandboxing` check with the passed `useSandbox`: when true
and `conversationId` present → `SandboxSessionManager` (Piece 1); otherwise the host path. No
other change to Piece 1's manager.

## UI

- **Settings:** the existing sandbox checkbox now reads as the feature master switch; add a
  "Main agent (default): Host / Sandboxed" picker bound to `mainAgentSandboxDefault`, shown when
  the master switch is on.
- **Sidebar context menu:** directly below "Link to Workspace…", a menu item that toggles the
  conversation's main-agent sandboxing. It shows a checkmark reflecting the conversation's
  **effective** (fully-resolved) sandbox state; selecting it writes an explicit
  `Conversation.mainAgentSandbox` override set to the flipped value. It is **disabled with a
  hint** when the master switch is off, and **hidden** for subagent conversations
  (`isSubagent == true`).
- **Workspace chip / conversation header:** surface the effective main-agent sandbox state
  (e.g. a small "host" / "sandboxed" badge) so it's visible without opening the menu.
- **`/sandbox` command:** currently there is **no** `/sandbox` command — only a stale reference
  in a `ToolExecutor` error string ("Run the `/sandbox` command to install it") that was never
  implemented. This spec introduces a real one and repairs the string:
  - `/sandbox` (no arg) → reports the effective policy for the active conversation and where it
    came from (conversation / workspace / global), plus runtime-installed status.
  - `/sandbox workspace host|sandboxed|clear` → writes/clears the per-workspace override
    (`.iris/sandbox.json`) for the active conversation's workspace.
  - Runtime **install** stays where it is (Settings / setup wizard); the misleading error string
    is corrected to point there instead of at `/sandbox`, so `/sandbox` is unambiguously the
    policy/status command.

## Configuration

- Reinterpreted: `enableSandboxing` → feature master switch (semantics change; value/key
  unchanged).
- New: `mainAgentSandboxDefault: SandboxPref` (key `MAIN_AGENT_SANDBOX_DEFAULT`, default `host`,
  migration seeds `sandboxed` for existing `enableSandboxing == true` installs).

## Testing

- **`SandboxPolicy.resolve` truth table (unit):**
  - master off → `.host(warnNoRuntime:false)` for every principal/preference.
  - subagent, runtime available → `.sandboxed`; subagent, no runtime → `.host(warnNoRuntime:true)`.
  - main, global default `host`, no overrides → `.host(warnNoRuntime:false)`.
  - main, global default `sandboxed`, runtime available → `.sandboxed`; no runtime →
    `.host(warnNoRuntime:true)`.
  - per-workspace override beats global default; per-conversation override beats per-workspace.
  - main resolved `sandboxed` with per-conversation `host` override → `.host(warnNoRuntime:false)`.
- **Per-workspace loader (unit):** reads a written `.iris/sandbox.json` round-trip; missing file
  → `nil`; `clear` removes the override.
- **Routing + warn-dedup:** verified by build and the manual pass (the notice appears once per
  conversation; subagents route to a sandbox when the runtime is present; the main agent honors
  the cascade).

## Rollout

Additive and backward-compatible. Master switch off (the default) is exactly today's host
behavior. The migration preserves current sandboxed-main users. Piece 1's mechanism, the
guardrails, and the host path are unchanged. Subagents become isolated by default whenever the
feature is on and a runtime is present — the core safety win.
