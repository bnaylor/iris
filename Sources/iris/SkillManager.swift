import Foundation

struct SkillManager {
    static let shared = SkillManager()
    
    let configDir = ("~/.iris" as NSString).expandingTildeInPath
    
    func loadSOUL() -> String {
        let path = "\(configDir)/prompts/SOUL.md"
        if let content = try? String(contentsOfFile: path, encoding: .utf8) {
            return content
        }
        return "You are Iris, a native macOS agent running on the local machine."
    }
    
    func discoverSkills() -> String {
        let skillsDir = "\(configDir)/skills"
        let fileManager = FileManager.default
        var skillsSummary = "# Available Skills\n\n"
        
        guard let items = try? fileManager.contentsOfDirectory(atPath: skillsDir) else {
            return skillsSummary + "No skills found."
        }
        
        for item in items {
            let skillPath = "\(skillsDir)/\(item)/SKILL.md"
            if fileManager.fileExists(atPath: skillPath) {
                if let content = try? String(contentsOfFile: skillPath, encoding: .utf8) {
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
        
        return "## Skill: \(name)\n**Description:** \(description)\n**Path:** ~/.iris/skills/\(folderName)/SKILL.md\n"
    }
}
