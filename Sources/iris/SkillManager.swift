import Foundation

struct SkillManager {
    static let shared = SkillManager()
    
    // SOUL and skill files are FIRST-PARTY content (Iris's own identity and learned behaviors),
    // not untrusted external data — so they are loaded raw and are NOT run through the injection
    // guard. Guarding them was actively harmful: Tier 1 strips the `---` OKF frontmatter
    // delimiters (so `description:` never parsed → "No description provided"), and the guard
    // wraps the content in <untrusted_context> — the exact tag SYSTEM.md tells the model to
    // treat as passive data and ignore, which self-neutralized the persona. Untrusted sources
    // (tool outputs, workspace AGENTS.md, web results) remain guarded at their own call sites.
    func loadSOUL(paths: IrisPaths = .default) async -> String {
        if let content = try? String(contentsOfFile: paths.soulMd.path, encoding: .utf8) {
            return content
        }
        return "You are Iris, a native macOS agent running on the local machine."
    }

    /// Auto-loads any custom, user-defined rules from `~/.iris/rules/` and returns them
    /// as a combined Markdown block to be appended directly to the system prompt.
    func loadCustomRules(paths: IrisPaths = .default) async -> String {
        let rulesDir = paths.rulesDir.path
        let fileManager = FileManager.default

        guard let items = try? fileManager.contentsOfDirectory(atPath: rulesDir) else {
            return ""
        }

        var rulesContent = ""
        for item in items.sorted() {
            let fileURL = paths.rulesDir.appendingPathComponent(item)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue {
                if let content = try? String(contentsOfFile: fileURL.path, encoding: .utf8) {
                    rulesContent += "\n\n# Rule: \(item)\n\(content)\n"
                }
            }
        }
        return rulesContent
    }

    /// A registered skill, parsed from its SKILL.md frontmatter. The body is never read.
    struct SkillInfo: Sendable {
        let name: String
        let description: String
        let folderName: String
    }

    /// Deterministic list of registered skills (sorted by display name). Shared by the system
    /// prompt (`discoverSkills`) and the `/skills` command so both see the same source of truth.
    func listSkills(paths: IrisPaths = .default) async -> [SkillInfo] {
        let skillsDir = paths.skillsDir.path
        let fileManager = FileManager.default

        guard let items = try? fileManager.contentsOfDirectory(atPath: skillsDir) else {
            return []
        }

        var skills: [SkillInfo] = []
        for item in items {
            let skillPath = "\(skillsDir)/\(item)/SKILL.md"
            guard fileManager.fileExists(atPath: skillPath),
                  let content = try? String(contentsOfFile: skillPath, encoding: .utf8) else {
                continue
            }
            // Only the frontmatter (name/description) is surfaced here — never the skill body.
            skills.append(parseFrontmatter(from: content, folderName: item))
        }

        return skills.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func discoverSkills(paths: IrisPaths = .default) async -> String {
        let skills = await listSkills(paths: paths)
        guard !skills.isEmpty else {
            return "# Available Skills\n\nNo skills found."
        }

        var skillsSummary = "# Available Skills\n\n"
        for skill in skills {
            skillsSummary += "## Skill: \(skill.name)\n**Description:** \(skill.description)\n"
            skillsSummary += "**Path:** ~/.iris/memory/skills/\(skill.folderName)/SKILL.md\n\n"
        }
        return skillsSummary
    }

    private func parseFrontmatter(from content: String, folderName: String) -> SkillInfo {
        let lines = content.components(separatedBy: .newlines)
        var isFrontmatter = false
        // Display-name precedence: explicit `name:` > OKF `title:` > folder name.
        var explicitName: String?
        var title: String?
        var description = "No description provided."

        func value(_ line: String, _ key: String) -> String {
            String(line.dropFirst(key.count)).trimmingCharacters(in: .whitespaces)
        }

        for line in lines {
            if line == "---" {
                if isFrontmatter { break }
                isFrontmatter = true
                continue
            }
            if isFrontmatter {
                if line.starts(with: "name:") {
                    explicitName = value(line, "name:")
                } else if line.starts(with: "title:") {
                    title = value(line, "title:")
                } else if line.starts(with: "description:") {
                    description = value(line, "description:")
                }
            }
        }

        let name = explicitName ?? title ?? folderName
        return SkillInfo(name: name, description: description, folderName: folderName)
    }
}
