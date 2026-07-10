import Foundation

class MemoryManager: @unchecked Sendable {
    static let shared = MemoryManager()
    
    private let configDir = ("~/.iris" as NSString).expandingTildeInPath
    
    private var memoryPath: String {
        return "\(configDir)/memory.md"
    }
    
    private var userProfilePath: String {
        return "\(configDir)/USER.md"
    }
    
    private init() {
        if !FileManager.default.fileExists(atPath: configDir) {
            try? FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
        }
        if !FileManager.default.fileExists(atPath: memoryPath) {
            try? "Memory is currently empty.".write(toFile: memoryPath, atomically: true, encoding: .utf8)
        }
        if !FileManager.default.fileExists(atPath: userProfilePath) {
            try? "User profile is currently empty.".write(toFile: userProfilePath, atomically: true, encoding: .utf8)
        }
    }
    
    func getMemory() -> String {
        if let content = try? String(contentsOfFile: memoryPath, encoding: .utf8) {
            return content
        }
        return "Memory is currently empty."
    }
    
    func updateMemory(content: String) {
        try? content.write(toFile: memoryPath, atomically: true, encoding: .utf8)
    }
    
    func getUserProfile() -> String {
        if let content = try? String(contentsOfFile: userProfilePath, encoding: .utf8) {
            return content
        }
        return "User profile is currently empty."
    }
    
    func updateUserProfile(content: String) {
        try? content.write(toFile: userProfilePath, atomically: true, encoding: .utf8)
    }
}
