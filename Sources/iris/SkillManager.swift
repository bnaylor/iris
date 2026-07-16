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

    func discoverSkills(paths: IrisPaths = .default) async -> String {
        let skillsDir = paths.skillsDir.path
        let fileManager = FileManager.default
        var skillsSummary = "# Available Skills\n\n"

        guard let items = try? fileManager.contentsOfDirectory(atPath: skillsDir) else {
            return skillsSummary + "No skills found."
        }

        for item in items {
            let skillPath = "\(skillsDir)/\(item)/SKILL.md"
            if fileManager.fileExists(atPath: skillPath) {
                if let content = try? String(contentsOfFile: skillPath, encoding: .utf8) {
                    // Only the frontmatter (name/description/path) is surfaced here — never the
                    // skill body — and it is parsed from the raw file.
                    skillsSummary += parseFrontmatter(from: content, folderName: item) + "\n"
                }
            }
        }

        return skillsSummary
    }
    
    private func parseFrontmatter(from content: String, folderName: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        var isFrontmatter = false
        var name = folderName
        var description = "No description provided."
        
        for line in lines {
            if line == "---" {
                if isFrontmatter { break }
                isFrontmatter = true
                continue
            }
            if isFrontmatter {
                if line.starts(with: "name:") {
                    name = line.replacingOccurrences(of: "name:", with: "").trimmingCharacters(in: .whitespaces)
                } else if line.starts(with: "description:") {
                    description = line.replacingOccurrences(of: "description:", with: "").trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        return "## Skill: \(name)\n**Description:** \(description)\n**Path:** ~/.iris/memory/skills/\(folderName)/SKILL.md\n"
    }
}
