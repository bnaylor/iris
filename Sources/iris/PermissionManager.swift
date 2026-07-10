import Foundation

struct PermissionRule: Codable, Equatable {
    let toolName: String
    let details: String
}

class PermissionManager {
    static let shared = PermissionManager()
    
    private let globalPermissionsURL: URL
    
    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let configDir = home.appendingPathComponent(".iris")
        if !FileManager.default.fileExists(atPath: configDir.path) {
            try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        }
        globalPermissionsURL = configDir.appendingPathComponent("permissions.json")
    }
    
    private func projectPermissionsURL(for workspace: String) -> URL {
        return URL(fileURLWithPath: workspace).appendingPathComponent(".iris").appendingPathComponent("permissions.json")
    }
    
    func isAllowed(toolName: String, details: String, workspace: String?) -> Bool {
        let rule = PermissionRule(toolName: toolName, details: details)
        
        // Check global
        if let globalRules = loadRules(from: globalPermissionsURL), globalRules.contains(rule) {
            return true
        }
        
        // Check project
        if let workspace = workspace {
            let projectURL = projectPermissionsURL(for: workspace)
            if let projectRules = loadRules(from: projectURL), projectRules.contains(rule) {
                return true
            }
        }
        
        return false
    }
    
    func allowGlobally(toolName: String, details: String) {
        let rule = PermissionRule(toolName: toolName, details: details)
        var rules = loadRules(from: globalPermissionsURL) ?? []
        if !rules.contains(rule) {
            rules.append(rule)
            saveRules(rules, to: globalPermissionsURL)
        }
    }
    
    func allowInProject(toolName: String, details: String, workspace: String) {
        let projectURL = projectPermissionsURL(for: workspace)
        let projectDir = projectURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: projectDir.path) {
            try? FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        }
        
        let rule = PermissionRule(toolName: toolName, details: details)
        var rules = loadRules(from: projectURL) ?? []
        if !rules.contains(rule) {
            rules.append(rule)
            saveRules(rules, to: projectURL)
        }
    }
    
    private func loadRules(from url: URL) -> [PermissionRule]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([PermissionRule].self, from: data)
    }
    
    private func saveRules(_ rules: [PermissionRule], to url: URL) {
        if let data = try? JSONEncoder().encode(rules) {
            try? data.write(to: url)
        }
    }
}
