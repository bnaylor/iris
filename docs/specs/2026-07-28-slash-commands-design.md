# Design Spec: Deterministic Slash Commands

* **Issue**: [#7](https://github.com/bnaylor/iris/issues/7) - Implement additional slash commands
* **Date**: 2026-07-28
* **Status**: Approved

---

## 1. Overview & Goals

Iris currently routes user inputs starting with `/` either through an LLM prompt (e.g. `/goal`, `/reflect`, `/vibecop init`, `/rename`) or through deterministic local handlers (`/skills`, `/sandbox`, `/stop`).

To maximize responsiveness, reduce token burn, and give developers fine-grained harness control, we will expand Iris's deterministic slash commands to cover:
1. **`/skills` suite:** `/skills` (list), `/skills reload [name]` (refresh disk cache & invalidate system prompt), `/skills show <name>` (dump SKILL.md body).
2. **`/rules` suite:** `/rules` (dump `~/.iris/rules/*.md` and workspace `AGENTS.md`), `/rules reload` (refresh rules & invalidate prompt cache).
3. **`/model` suite:** `/model` (show active model tiers), `/model <tier|name>` (switch active model).
4. **`/mcp` suite:** `/mcp` (list connected servers & tools), `/mcp reload` (reconnect servers).
5. **`/facts` suite:** `/facts` (show recent facts), `/facts probe <entity>` (entity recall), `/facts search <query>` (FTS5 lookup).
6. **`/tokens` / `/stats`:** Display token usage breakdown and context window status.
7. **`/new` / `/clear`:** `/new` (start fresh conversation), `/clear` (clear current messages).
8. **`/update`:** Fix stubbed command by connecting directly to `UpdateManager.shared.checkForUpdates()`.

---

## 2. Component Architecture

### A. Command Dispatcher (`AppState.swift`)
Command handling occurs inside `AppState.sendMessage(_:)`. All deterministic commands execute in-app without invoking `IrisEngine.processInput(...)`, avoiding LLM token roundtrips.

### B. Auto-Complete Registry (`SlashCommandItem.swift`)
All new commands and subcommands are registered in `SlashCommandItem.allCommands` so they render in the `SlashCommandAutoCompleteView` popup menu during typing.

### C. System Prompt Cache Invalidation
Commands modifying harness state (`/skills reload`, `/rules reload`, `/model <name>`) trigger `engine.invalidateSystemPrompt()` so the next LLM turn reflects updated configuration immediately.

---

## 3. Detailed Command Specs

| Command | Usage | Description | Action / Output |
|---|---|---|---|
| `/skills` | `/skills` | List all registered skills | Markdown list of skills & descriptions |
| `/skills reload` | `/skills reload [name]` | Reload skill definitions | Flushes skill cache, invalidates prompt cache, reports status |
| `/skills show` | `/skills show <name>` | Display full SKILL.md body | Output SKILL.md body deterministically |
| `/rules` | `/rules` | List loaded custom rules | Outputs contents of `~/.iris/rules/` & workspace `AGENTS.md` |
| `/rules reload` | `/rules reload` | Reload custom rules | Invalidates system prompt cache |
| `/model` | `/model [name]` | Inspect or switch model | Displays or changes model for active conversation |
| `/mcp` | `/mcp [reload]` | Inspect/reload MCP servers | Lists connected MCP tools or forces transport reload |
| `/facts` | `/facts [search\|probe <query>]` | Inspect SQLite FactStore | Queries `FactStoreManager` deterministically |
| `/tokens` | `/tokens` | Token usage breakdown | Displays prompt/candidate count & context breakdown |
| `/new` | `/new` | Create fresh conversation | Spawns new conversation tab |
| `/update` | `/update` | Check for updates | Calls `UpdateManager.shared.checkForUpdates()` |

---

## 4. Testing & Verification

1. Unit tests in `SlashCommandTests.swift` verifying command routing in `AppState`.
2. Unit tests for `SkillManager` reload and view methods.
3. Verification that non-LLM commands emit output to the chat buffer via `emitCommandOutput`.
