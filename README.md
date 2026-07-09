# 🌈 Iris: The Native macOS Agent Harness

Iris is a lightweight, compiled, native macOS agent harness designed to run autonomous AI workflows locally without heavy runtime dependencies (like Node/npm) that might be blocked by enterprise endpoint management.

## 🚀 Architecture

At its core, Iris is a Swift-based execution chassis that bridges your local environment and cloud LLMs.
*   **Native GUI & Zero-Bloat Foundation:** Built entirely using native Apple frameworks (`SwiftUI`, `Foundation`, `URLSession`, `Network`, `FSEventStream`).
*   **Concurrency:** Built on modern Swift 6 Concurrency (`async/await`, `actor`), providing a high-performance, non-blocking event loop.
*   **LLM Engine:** Natively integrates with Google's Gemini REST API (defaulting dynamically to available models like `gemini-3.5-flash`), relying heavily on native JSON Function Calling.
*   **Event-Driven:** Uses an `AsyncStream` wrapper around `FSEventStream` to instantly wake up the agent when files change (e.g., saving a note in Obsidian).
*   **Built-in OAuth:** Includes a dependency-free TCP loopback listener for Google Workspace OAuth, enabling safe integrations with Calendar, Docs, and Sheets.

## 🧠 The Portable Skill System

Iris uses **Markdown-based skills**, matching standard AI agent patterns. Skills are not hardcoded into the Swift binary. Instead, Iris reads from `~/.config/iris/skills/`.

A skill is simply a directory containing a `SKILL.md` file. Iris dynamically loads the YAML frontmatter to learn what the skill does, and then passes the markdown instructions to the LLM when the skill is needed. The LLM executes the skill using Iris's built-in native tools.

### Core Native Tools
Iris provides three highly privileged native primitives to the LLM:
1.  `run_command`: Sandboxed execution of shell commands.
2.  `read_file`: Reads arbitrary local text files.
3.  `write_file`: Writes/modifies local files.

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

## 📦 Project Setup

Iris is managed via Swift Package Manager (SPM).
To build:
```bash
swift build
```
