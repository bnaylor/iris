import Foundation

class MemoryManager: @unchecked Sendable {
    static let shared = MemoryManager()

    /// Settable so tests can point the manager at a temp root. Production uses `.default`.
    var paths: IrisPaths = .default

    private var memoryPath: String { paths.memoryMd.path }
    private var userProfilePath: String { paths.userMd.path }

    private init() {
        try? paths.ensureDirectories()
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
