import Foundation

struct SkillManager {
    static let shared = SkillManager()
    
    func loadSOUL() async -> String {
        let path = IrisPaths.default.soulMd.path
        if let content = try? String(contentsOfFile: path, encoding: .utf8) {
            let structuralSafe = PromptInjectionGuard.sanitizeUntrustedInput(content)
            return await InjectionGuard.sanitize(structuralSafe, contextTag: "soul_prompt", maxTier: .tier3_canary)
        }
        return "You are Iris, a native macOS agent running on the local machine."
    }
    
    func discoverSkills() async -> String {
        let skillsDir = IrisPaths.default.skillsDir.path
        let fileManager = FileManager.default
        var skillsSummary = "# Available Skills\n\n"
        
        guard let items = try? fileManager.contentsOfDirectory(atPath: skillsDir) else {
            return skillsSummary + "No skills found."
        }
        
        for item in items {
            let skillPath = "\(skillsDir)/\(item)/SKILL.md"
            if fileManager.fileExists(atPath: skillPath) {
                if let content = try? String(contentsOfFile: skillPath, encoding: .utf8) {
                    let structuralSafe = PromptInjectionGuard.sanitizeUntrustedInput(content)
                    let safeContent = await InjectionGuard.sanitize(structuralSafe, contextTag: "skill_\(item)", maxTier: .tier3_canary)
                    skillsSummary += parseFrontmatter(from: safeContent, folderName: item) + "\n"
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
