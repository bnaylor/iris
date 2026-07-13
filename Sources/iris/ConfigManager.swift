import Foundation
import SwiftUI

@Observable
class ConfigManager: @unchecked Sendable {
    @ObservationIgnored nonisolated(unsafe) static let shared = ConfigManager()
    
    var geminiAPIKey: String {
        didSet { UserDefaults.standard.set(geminiAPIKey, forKey: "GEMINI_API_KEY") }
    }
    
    var modelEasy: String {
        didSet { UserDefaults.standard.set(modelEasy, forKey: "MODEL_EASY") }
    }
    
    var modelMedium: String {
        didSet { UserDefaults.standard.set(modelMedium, forKey: "MODEL_MEDIUM") }
    }
    
    var modelHard: String {
        didSet { UserDefaults.standard.set(modelHard, forKey: "MODEL_HARD") }
    }
    
    var googleClientID: String {
        didSet { UserDefaults.standard.set(googleClientID, forKey: "GOOGLE_CLIENT_ID") }
    }
    
    var googleClientSecret: String {
        didSet { UserDefaults.standard.set(googleClientSecret, forKey: "GOOGLE_CLIENT_SECRET") }
    }
    
    var googleAccessToken: String {
        didSet { UserDefaults.standard.set(googleAccessToken, forKey: "GOOGLE_ACCESS_TOKEN") }
    }
    
    var googleRefreshToken: String {
        didSet { UserDefaults.standard.set(googleRefreshToken, forKey: "GOOGLE_REFRESH_TOKEN") }
    }
    
    var googleTokenExpiry: Double {
        didSet { UserDefaults.standard.set(googleTokenExpiry, forKey: "GOOGLE_TOKEN_EXPIRY") }
    }
    
    var enableSandboxing: Bool {
        didSet { UserDefaults.standard.set(enableSandboxing, forKey: "ENABLE_SANDBOXING") }
    }
    
    var sandboxImage: String {
        didSet { UserDefaults.standard.set(sandboxImage, forKey: "SANDBOX_IMAGE") }
    }
    
    var enableVibecop: Bool {
        didSet { UserDefaults.standard.set(enableVibecop, forKey: "ENABLE_VIBECOP") }
    }
    
    var vibecopEngine: String {
        didSet { UserDefaults.standard.set(vibecopEngine, forKey: "VIBECOP_ENGINE") }
    }
    
    var vibecopModel: String {
        didSet { UserDefaults.standard.set(vibecopModel, forKey: "VIBECOP_MODEL") }
    }
    
    init() {
        self.geminiAPIKey = UserDefaults.standard.string(forKey: "GEMINI_API_KEY") ?? ""
        self.modelEasy = UserDefaults.standard.string(forKey: "MODEL_EASY") ?? "gemini-3.1-flash-lite"
        self.modelMedium = UserDefaults.standard.string(forKey: "MODEL_MEDIUM") ?? "gemini-3.5-flash"
        self.modelHard = UserDefaults.standard.string(forKey: "MODEL_HARD") ?? "gemini-3.1-pro-preview"
        self.googleClientID = UserDefaults.standard.string(forKey: "GOOGLE_CLIENT_ID") ?? ""
        self.googleClientSecret = UserDefaults.standard.string(forKey: "GOOGLE_CLIENT_SECRET") ?? ""
        self.googleAccessToken = UserDefaults.standard.string(forKey: "GOOGLE_ACCESS_TOKEN") ?? ""
        self.googleRefreshToken = UserDefaults.standard.string(forKey: "GOOGLE_REFRESH_TOKEN") ?? ""
        self.googleTokenExpiry = UserDefaults.standard.double(forKey: "GOOGLE_TOKEN_EXPIRY")
        self.enableSandboxing = UserDefaults.standard.bool(forKey: "ENABLE_SANDBOXING")
        self.sandboxImage = UserDefaults.standard.string(forKey: "SANDBOX_IMAGE") ?? "ubuntu:latest"
        
        self.enableVibecop = UserDefaults.standard.bool(forKey: "ENABLE_VIBECOP")
        let savedEngine = UserDefaults.standard.string(forKey: "VIBECOP_ENGINE") ?? ""
        self.vibecopEngine = savedEngine.isEmpty ? "llama_cpp" : savedEngine
        
        let savedVibecop = UserDefaults.standard.string(forKey: "VIBECOP_MODEL") ?? ""
        self.vibecopModel = savedVibecop.isEmpty ? "Llama-3.2-1B-Instruct-Q4_K_M.gguf" : savedVibecop
    }
    
    var isConfigured: Bool {
        return !geminiAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
