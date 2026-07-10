# 🌈 Iris: The Native macOS Agent Harness

Iris is a lightweight, compiled, native macOS agent harness designed to run autonomous AI workflows locally without heavy runtime dependencies (like Node/npm) that might be blocked by enterprise endpoint management.

It features **native Model Context Protocol (MCP) support** for limitless tool expansion and **built-in zero-dependency Google Workspace integrations** (Calendar, Docs, Drive, Sheets, Gmail, and Tasks).

## 🚀 Architecture

At its core, Iris is a Swift-based execution chassis that bridges your local environment and cloud LLMs.
*   **Native GUI & Zero-Bloat Foundation:** Built entirely using native Apple frameworks (`SwiftUI`, `Foundation`, `URLSession`, `Network`, `FSEventStream`).
*   **Concurrency:** Built on modern Swift 6 Concurrency (`async/await`, `actor`), providing a high-performance, non-blocking event loop.
*   **LLM Engine:** Natively integrates with Google's Gemini REST API (defaulting dynamically to available models like `gemini-3.5-flash`), relying heavily on native JSON Function Calling.
*   **Event-Driven:** Uses an `AsyncStream` wrapper around `FSEventStream` to instantly wake up the agent when files change (e.g., saving a note in Obsidian).
*   **Built-in OAuth:** Includes a dependency-free TCP loopback listener for Google Workspace OAuth, enabling safe, native integrations with **Google Calendar, Docs, Drive, Sheets, Gmail, and Tasks**.
*   **Model Context Protocol (MCP):** Natively acts as an MCP client, dynamically loading external tool servers (like Postgres or SQLite) straight into the agent's brain.
*   **Subagent Sandboxing:** Transparently routes terminal execution through `apple/container` lightweight Linux VMs, allowing Iris to safely execute potentially dangerous autonomous behavior.
*   **Workspace Binding:** Link chat sessions to local filesystem directories. Iris will automatically load the project's `AGENTS.md` instructions and execute terminal commands from within that project context.
*   **Autonomous Scheduling & Wake Recovery:** Register cron-like recurring schedules or one-off interval timers that persist to disk. Features built-in macOS `NSWorkspace.didWakeNotification` observation to guarantee jobs missed during sleep will instantly catch-up when the computer wakes.
*   **Rich Native UI:** Beautiful macOS `NavigationSplitView` with multi-conversation support, `.regularMaterial` frosted glass input bars, and native markdown chat rendering powered by `swift-markdown-ui`.

## 🧠 The Portable Skill System

Iris uses **Markdown-based skills**, matching standard AI agent patterns. Skills are not hardcoded into the Swift binary. Instead, Iris reads from `~/.iris/skills/`.

A skill is simply a directory containing a `SKILL.md` file. Iris dynamically loads the YAML frontmatter to learn what the skill does, and then passes the markdown instructions to the LLM when the skill is needed. The LLM executes the skill using Iris's built-in native tools.

### Core Native Tools
Iris provides three highly privileged native primitives to the LLM:
1.  `run_command`: Sandboxed execution of shell commands (runs in a lightweight Linux VM via `apple/container` if sandboxing is enabled).
2.  `read_file`: Reads arbitrary local text files.
3.  `write_file`: Writes/modifies local files.
4.  `schedule_job`: Native API to register cron-like schedules (`minute`, `hour`, `weekday`) or `intervalSeconds`.
5.  `set_workspace`: Automatically binds the active conversation to a project path.

## 🛠️ Usage

When started, Iris launches as a native macOS App. If you haven't configured your API keys, the **Settings Window** will automatically pop up. 
All keys are saved securely to your local `UserDefaults`.

```bash
swift run
```

### Global Hotkey ⌨️
Iris runs in the background and can be summoned instantly over any other app by pressing **`Cmd + Shift + Space`** (configurable in Settings).

### Google Workspace Integration 🔐
In the settings window, you can enter your Google OAuth Client ID and Secret, and click **Connect to Google**. Iris will spin up a local listener, redirect you to Google for consent, and seamlessly exchange your authorization code for valid access and refresh tokens.

Once connected, Iris has native API access to the following Workspace tools directly from Swift:
*   **Google Calendar**: `google_calendar_list_events`, `google_calendar_create_event`
*   **Google Docs**: `google_docs_get`
*   **Google Drive**: `google_drive_search`
*   **Google Sheets**: `google_sheets_get`
*   **Google Tasks**: `google_tasks_list_tasklists`, `google_tasks_list_tasks`, `google_tasks_create_task`
*   **Gmail**: `gmail_list_unread`, `gmail_send_email`

## 📦 Project Setup

Iris is managed via Swift Package Manager (SPM).
To build:
```bash
swift build
```

### Model Context Protocol (MCP)

Iris natively supports the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/). It dynamically loads external MCP servers to inject new tools straight into Iris's brain!

To configure MCP servers, create a JSON file at `~/.iris/mcp_servers.json` with your server configurations:

```json
{
  "postgres": {
    "command": "npx",
    "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://localhost/mydatabase"]
  },
  "sqlite": {
    "command": "uvx",
    "args": ["mcp-server-sqlite", "--db-path", "~/mydatabase.db"]
  }
}
```

Once configured, Iris will automatically boot these servers in the background and their tools will be available for Iris to use!
