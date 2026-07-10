import Foundation

struct SecurityGuard {
    static let dangerousCommands = [
        "rm", "mv", "chmod", "chown", "sudo", "su", 
        "curl", "wget", "nc", "ssh", 
        "python", "python3", "node", "ruby", "pip", "npm"
    ]
    
    static func isCommandDangerous(_ command: String) -> Bool {
        // Simple heuristic: split by spaces and check if any token matches
        // In a real app, this would need to handle pipes, semicolons, etc.
        let tokens = command.components(separatedBy: .whitespacesAndNewlines)
        for token in tokens {
            let cleanToken = token.trimmingCharacters(in: .punctuationCharacters)
            if dangerousCommands.contains(cleanToken) {
                return true
            }
        }
        return false
    }
    
    static func isFileAccessDangerous(path: String, workspace: String?) -> Bool {
        let expandedPath = (path as NSString).expandingTildeInPath
        let restrictedPrefixes = [
            ("~/.ssh" as NSString).expandingTildeInPath,
            ("~/.aws" as NSString).expandingTildeInPath,
            "/etc"
        ]
        
        for restricted in restrictedPrefixes {
            if expandedPath.hasPrefix(restricted) {
                return true
            }
        }
        
        return false
    }
}
