# iris Code Review

> Multi-agent review covering correctness, security, concurrency, and test coverage.
> Generated 2026-07-13.

---

## Ship-blockers (broken in production today)

**`[String: String]` for tool args — root cause of the most bugs** (`Models.swift:30`, `Models.swift:39`)
`FunctionCall.args` and `FunctionResponse.response` are typed `[String: String]`. Tool schemas use `BOOLEAN`, `INTEGER`, and nested objects. Anthropic stringifies them as `"\(v)"` producing `"Optional(...)"` garbage; OpenAI's `as? [String: String]` cast silently returns `[:]`. Any tool with a non-string parameter (e.g. `background: Bool`, `intervalSeconds: Int`) receives corrupted or empty args. This needs to become `[String: JSONValue]` or similar. Everything downstream inherits this bug.

**Tool result IDs break on repeated same-tool calls** (`AnthropicClient.swift:26-38`, `iris.swift:383`)
`FunctionResponse` matching falls back to `call_<name>_0` (hardcoded) when the tool name isn't in `nameToLastId`. If the same tool is called twice with the same args, both match the same result entry; the second result is dropped and Anthropic returns a 400 for the unmatched `tool_use` block.

**Only the first `tool_use` block is processed** (`AnthropicClient.swift:150`)
The `!foundToolUse` guard discards every tool call after the first in a multi-tool response. If this is intentional (iris serializes multi-tool into sequential turns), it needs a comment and a corresponding guarantee that the LLM is never asked for parallel tools.

**Goal reprompt is unbounded recursion** (`iris.swift:408-416`)
The goal loop spawns a detached `Task` that sleeps 1.5s and calls `processInput` recursively. If `goal_complete` is never emitted and the model keeps returning text (not tools), `hasFunctionCall` is false, the turn ends, and `processInput` is re-entered from the detached task — forever, with no iteration cap and a growing history.

**SubagentManager hangs indefinitely with no timeout** (`SubagentManager.swift:66-74`)
`runSubagent` busy-polls every 100ms. If the subagent misbehaves or `goal_complete` is never called, it never exits. The parent agent's tool-call slot is blocked permanently.

**Force-unwrap on user-supplied URLs** (`AnthropicClient.swift:137`, `OpenAIClient.swift:149`)
`URL(string: endpointUrl)!` crashes the process if the user configures a malformed `baseURL`.

**AppState silently destroys conversation history on decode failure** (`AppState.swift:391-397`)
`try? JSONDecoder().decode(...)` swallows all errors, leaves `conversations` empty, and `saveConversations()` then overwrites whatever was on disk with an empty array.

**`HolographicMemoryManager.shared` uses `try!`** (`HolographicMemoryManager.swift:156`)
Any SQLite failure at startup (permissions, disk full, schema mismatch) crashes the app with no recovery path.

---

## Security

### Critical

**Shell injection in `searchWeb`** (`ToolExecutor.swift:241`)
Only `'` is escaped before embedding the LLM-supplied query in `/bin/zsh -c`. `$`, backticks, and newlines are unescaped; a crafted query executes arbitrary shell commands. Fix: use `Process` with an args array instead of a shell string.

**`run_command` is unsandboxed by default** (`ToolExecutor.swift:108-128`)
Sandboxing only activates if `enableSandboxing` is true *and* `container` is installed; the default is unrestricted shell exec.

**`AGENTS.md` injected into system prompt without sanitization** (`iris.swift:120-126`)
A malicious file in any workspace directory can take over the system prompt. Run through `PromptInjectionGuard` before injecting.

**`SOUL.md` / `SKILL.md` injected without sanitization** (`SkillManager.swift`)
Same vector: write access to `~/.iris/` means full system prompt control on next session.

**Hook commands are arbitrary shell with no sandboxing** (`HookManager.swift:131-133`)
`~/.iris/settings.json` is user-writable; a prompt-injected `write_file` call can install an exfiltration hook that fires on every `AfterTool` event. Hook processes also inherit the full parent environment including all API keys (`HookManager.swift:138-140`).

**Unsigned PKG fetched and installed as root** (`SandboxingManager.swift:38-44`)
No hash or signature check before `installer -pkg ... -target /`. A DNS hijack or MITM yields RCE as root.

### Major

**Tier 3 canary embeds untrusted input in its probe** (`InjectionGuard.swift:88-95`)
The canary prompt is `"Text to summarize: \(input)"`. A payload that survives Tier 1 can instruct the canary model to emit the secret UUID, defeating Tier 3 entirely.

**Tier 2 CoreML classifier fails open** (`InjectionGuard.swift:74-76`)
Any inference error returns `true` (safe). This is the wrong failure mode for a security gate; it should fail closed.

**OAuth has no CSRF state parameter** (`OAuthManager.swift:54-62`, `84-88`)
No `state` in the authorization URL; the callback extracts the code via naive string search with no validation. An attacker can force a token exchange with an attacker-controlled code.

**OAuth listener binds to all interfaces** (`OAuthManager.swift:43`)
Binds to `.any` instead of `127.0.0.1`; on a local network another host can race to steal the authorization code.

**MCP tool descriptions injected verbatim into LLM context** (`MCPManager.swift:127`)
Tool results go through `PromptInjectionGuard` but tool definitions fetched from MCP servers at startup do not. A rogue MCP server embeds injection content in its tool descriptions.

**Watcher on `~/.iris/skills` creates a self-reinforcing attack loop** (`iris.swift:75-78`)
A prompt injection that calls `write_file` on the skills directory triggers the watcher, which re-runs the agent with the now-malicious skill in the system prompt.

**`USER.md` injected without sanitization** (`iris.swift:114-116`)
The LLM can write to `USER.md` via `update_user_profile`; a prompt injection can persist itself across sessions via this file.

---

## Correctness & Concurrency

**`cache_control` applied to `tool_result` blocks** (`AnthropicClient.swift:68-75`)
The cache-marking code runs on all messages including those whose last block is a `tool_result`. Anthropic rejects `cache_control` on `tool_result` content blocks in some API versions; the marker should be skipped for those blocks.

**OpenAI mixed text+tool response drops the text part** (`OpenAIClient.swift:83-87`)
When a `Content` has both text and function response parts, the enclosing text message is silently discarded.

**OpenAI null candidates triggers premature loop exit** (`OpenAIClient.swift:177-178`)
A `content: null` response results in a zero-part candidate; `hasFunctionCall` is false and the agentic loop exits prematurely.

**Concurrent subagent tool calls can corrupt history** (`iris.swift:354-378`)
`withTaskGroup` runs all tool calls in parallel including `invoke_subagent`, which mutates `AppState` via `MainActor.run`. No guard prevents concurrent history mutations.

**`AuxiliaryModelManager` TOCTOU race** (`AuxiliaryModelManager.swift:23-43`)
Two concurrent callers for the same role both see a nil engine, both call `loadModel`, and the first loaded engine is silently abandoned without `unloadModel`.

**`ScheduleManager` multiple data races** (`ScheduleManager.swift:39`, `60-69`, `117-119`)
`onJobFired` is a bare `var` read/written without synchronization; `start()` is not idempotent and leaks run loop spins on repeated calls.

**`SubagentManager` `@unchecked Sendable` data race** (`SubagentManager.swift:3`)
`self.state` is written from `setGlobalState` (any context) and read in `runSubagent` with no actor isolation or lock.

**`AppState` thrashes `UserDefaults` on main thread** (`AppState.swift:378-382`)
`saveConversations()` is called synchronously on main for every message append with no debouncing. Should coalesce writes.

**`HolographicMemory` eviction never fires for reinforced facts** (`HolographicMemoryManager.swift:290-301`)
Facts with `trustScore >= 1.2` (one `reinforceFacts` call) are exempt from eviction regardless of age. The table grows without bound over time.

**`CloudAuxiliaryEngine` ignores `jsonSchema` parameter** (`CloudAuxiliaryEngine.swift:13`)
The structured output schema is accepted by the protocol but never sent to the API; callers expecting JSON silently receive prose.

**`FileWatcher` resource leak on `FSEventStreamCreate` failure** (`FileWatcher.swift:25`)
`Unmanaged.passRetained` with no release path on the failure branch leaks the continuation wrapper.

**`HookManager` `timeout` field is dead code** (`HookManager.swift`)
`HookDefinition` declares `timeout` but `executeCommandHook` never uses it; hooks can block forever.

---

## Test Coverage

### Highest-value missing test

**Multi-turn tool call round-trip** (`AnthropicClient.swift:18-75`)
Build a `GeminiRequest` with three turns: user message → assistant with `functionCall` → user with `functionResponse`. In a `MockURLProtocol` handler, assert: (1) the third message has `"role": "user"` with a `"tool_result"` block whose `"tool_use_id"` matches the synthesized call ID; (2) the second message's last block carries `"cache_control": {"type": "ephemeral"}`; (3) the third message's last block also carries the ephemeral marker. This is the critical path for every agentic loop and is currently completely untested.

### Other significant gaps

- `AnthropicClient` / `OpenAIClient` — `baseURL` override routing (both clients, no coverage)
- `HookManager` — `AfterTool`, `BeforeModel`, `AfterModel`, `SessionStart`, `AfterAgent` event types (five of eleven have zero tests)
- `HookManager` — hook chaining (modified data flowing from hook N to hook N+1)
- `HolographicMemoryManager` — `reinforceFacts`, `evictOldFacts`, time-decay ranking
- `ToolExecutor` — sandbox branch (the entire containerized code path)
- `PromptInjectionGuard` — zero tests on this class
- `InjectionGuard` — Tier 3 fail-closed path (error during canary should block, not pass)
- `SubagentManager` — nil `state` error path; invalid effort string fallback

### Existing tests to fix or delete

- `SandboxTests.testSandboxingManagerCheck` — makes no assertions; delete or replace
- `irisTests.example()` — generated placeholder with no assertions; delete
- `HookManagerTests.testHookManagerWarning` — asserts `modifiedData != nil` but accepts any non-nil value; tighten assertion
- `HookManagerTests.testHookManagerNotification` — uses a 500ms `Task.sleep` to wait for a subprocess; flaky on CI

---

## Suggested Prioritization

1. **`[String: String]` → `[String: JSONValue]`** — fixes the most bugs with one type change; everything else in the correctness column gets easier after this
2. **Shell injection in `searchWeb`** — switch to `Process` with an args array, no shell involved
3. **Goal loop recursion cap** — add a `maxIterations` guard before sessions become a memory leak
4. **AGENTS.md / SOUL.md / USER.md sanitization** — run all files injected into the system prompt through `PromptInjectionGuard`
5. **OAuth state parameter + loopback binding**
6. **Cache breakpoint skip for `tool_result` blocks** — small targeted fix
7. **Multi-turn tool round-trip test** — highest-value test to write next
