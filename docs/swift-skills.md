## SwiftUI Agent Skill for Google Antigravity
This skill teaches the AI agent how to build, refactor, and maintain SwiftUI code according to iOS design standards and team-specific architectural patterns. It is designed to be loaded dynamically by the IDE to provide precise UI assistance without causing tool bloat.
## 🛠️ Installation Paths
To activate this skill, place this folder into one of the designated Antigravity paths.
## 1. Workspace Scope (Project-Specific)
Use this path if you only want the coding agent to apply these SwiftUI patterns inside this specific project.

* Path: <project-root>/.agents/skills/swiftui-expert-skill/
* Note: Some project setups may use .agent/skills/ instead.

## 2. Global Scope (System-Wide)
Use this path if you want these SwiftUI agent instructions available across every project you open on your machine.

* Path: ~/.gemini/config/skills/swiftui-expert-skill/

------------------------------
## 📋 Core SwiftUI Capabilities & Rules## 1. UI Components & Layouts

* Use clean, composable structures for views, lists, grids, and stacks.
* Implement reusable view modifiers to keep layout code organized.
* Support design guidelines derived from standard iOS design repositories.

## 2. State & Data Flow

* Keep data flow highly structured using appropriate property wrappers (@State, @Binding, or modern observation macros).
* Enforce clear separation between view logic and business logic.

## 3. Progressive Disclosure

* Do not load complex, project-wide rules all at once.
* Only apply advanced iOS syntax or layout rules when a task explicitly demands a SwiftUI view or refactor.

------------------------------
## 🚀 How to Trigger This Skill

   1. Verify Layout: Ensure a file named SKILL.md exists at the root of the skill folder.
   2. Open Antigravity: Start your Antigravity IDE or CLI in the target project workspace.
   3. Prompt the Agent: Ask the agent to perform a specific SwiftUI task. [1] 

Example Prompts:

* "Refactor my chip UI into a structured List view using our SwiftUI skill."
* "Build a profile screen with a clean grid layout using standard SwiftUI practices."

------------------------------
## 🔧 Management Tools
If you prefer a graphical user interface over manual file placements, you can manage your local and global agent skills using native macOS tools designed for AI agent workflows.

[1] [https://document360.com](https://document360.com/blog/create-skills-md-for-technical-writing/)

