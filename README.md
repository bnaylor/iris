# 🌈 Iris: The Native macOS Agent Harness

Iris is a lightweight, compiled, native macOS agent harness designed to run autonomous AI workflows locally without heavy runtime dependencies (like Node/npm) that might be blocked by enterprise endpoint management.

## 🚀 Architecture

At its core, Iris is a Swift-based execution chassis that bridges your local environment and cloud LLMs.
*   **Zero-Bloat Foundation:** Built entirely using native Apple frameworks (`Foundation`, `URLSession`, `FSEventStream`).
*   **Concurrency:** Built on modern Swift 6 Concurrency (`async/await`, `actor`), providing a high-performance, non-blocking event loop.
*   **LLM Engine:** Natively integrates with Google's Gemini REST API, relying heavily on native JSON Function Calling.
*   **Event-Driven:** Uses an `AsyncStream` wrapper around `FSEventStream` to instantly wake up the agent when files change (e.g., saving a note in Obsidian) and concurrent CLI input handling.

## 🧠 The Portable Skill System

Iris uses **Markdown-based skills**, matching standard AI agent patterns. Skills are not hardcoded into the Swift binary. Instead, Iris reads from `~/.config/iris/skills/`.

A skill is simply a directory containing a `SKILL.md` file. Iris dynamically loads the YAML frontmatter to learn what the skill does, and then passes the markdown instructions to the LLM when the skill is needed. The LLM executes the skill using Iris's built-in native tools.

### Core Native Tools
Iris provides three highly privileged native primitives to the LLM:
1.  `run_command`: Sandboxed execution of shell commands.
2.  `read_file`: Reads arbitrary local text files.
3.  `write_file`: Writes/modifies local files.

## 🛠️ Usage

Iris requires a Gemini API key exported in your environment.

```bash
export GEMINI_API_KEY="your_api_key_here"
swift run
```

When started, Iris scans `~/.config/iris/skills/`, compiles its system prompt, begins listening for CLI input, and spawns the FSEvents watcher to monitor your target directories.

## 📦 Project Setup

Iris is managed via Swift Package Manager (SPM).
To build:
```bash
swift build
```
