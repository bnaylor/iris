import Foundation
import SwiftUI

public enum LLMProvider: String, CaseIterable, Identifiable, Sendable {
    case gemini = "Gemini"
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    
    public var id: String { rawValue }
}

@Observable
class ConfigManager: @unchecked Sendable {
    @ObservationIgnored static let shared = ConfigManager()
    
    var primaryProvider: String {
        didSet { UserDefaults.standard.set(primaryProvider, forKey: "PRIMARY_PROVIDER") }
    }
    
    var geminiAPIKey: String {
        didSet { UserDefaults.standard.set(geminiAPIKey, forKey: "GEMINI_API_KEY") }
    }
    
    var geminiBaseURL: String {
        didSet { UserDefaults.standard.set(geminiBaseURL, forKey: "GEMINI_BASE_URL") }
    }
    
    var anthropicAPIKey: String {
        didSet { UserDefaults.standard.set(anthropicAPIKey, forKey: "ANTHROPIC_API_KEY") }
    }
    
    var anthropicBaseURL: String {
        didSet { UserDefaults.standard.set(anthropicBaseURL, forKey: "ANTHROPIC_BASE_URL") }
    }
    
    var openAIAPIKey: String {
        didSet { UserDefaults.standard.set(openAIAPIKey, forKey: "OPENAI_API_KEY") }
    }
    
    var openAIBaseURL: String {
        didSet { UserDefaults.standard.set(openAIBaseURL, forKey: "OPENAI_BASE_URL") }
    }
    
    var geminiModelEasy: String {
        didSet { UserDefaults.standard.set(geminiModelEasy, forKey: "GEMINI_MODEL_EASY") }
    }
    var geminiModelMedium: String {
        didSet { UserDefaults.standard.set(geminiModelMedium, forKey: "GEMINI_MODEL_MEDIUM") }
    }
    var geminiModelHard: String {
        didSet { UserDefaults.standard.set(geminiModelHard, forKey: "GEMINI_MODEL_HARD") }
    }
    
    var anthropicModelEasy: String {
        didSet { UserDefaults.standard.set(anthropicModelEasy, forKey: "ANTHROPIC_MODEL_EASY") }
    }
    var anthropicModelMedium: String {
        didSet { UserDefaults.standard.set(anthropicModelMedium, forKey: "ANTHROPIC_MODEL_MEDIUM") }
    }
    var anthropicModelHard: String {
        didSet { UserDefaults.standard.set(anthropicModelHard, forKey: "ANTHROPIC_MODEL_HARD") }
    }
    
    var openaiModelEasy: String {
        didSet { UserDefaults.standard.set(openaiModelEasy, forKey: "OPENAI_MODEL_EASY") }
    }
    var openaiModelMedium: String {
        didSet { UserDefaults.standard.set(openaiModelMedium, forKey: "OPENAI_MODEL_MEDIUM") }
    }
    var openaiModelHard: String {
        didSet { UserDefaults.standard.set(openaiModelHard, forKey: "OPENAI_MODEL_HARD") }
    }
    
    func getModel(for tier: ModelTier) -> String {
        switch primaryProvider {
        case LLMProvider.anthropic.rawValue:
            switch tier {
            case .easy: return anthropicModelEasy
            case .medium: return anthropicModelMedium
            case .hard: return anthropicModelHard
            }
        case LLMProvider.openai.rawValue:
            switch tier {
            case .easy: return openaiModelEasy
            case .medium: return openaiModelMedium
            case .hard: return openaiModelHard
            }
        default:
            switch tier {
            case .easy: return geminiModelEasy
            case .medium: return geminiModelMedium
            case .hard: return geminiModelHard
            }
        }
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
        let savedProvider = UserDefaults.standard.string(forKey: "PRIMARY_PROVIDER") ?? "Gemini"
        self.primaryProvider = savedProvider
        
        geminiAPIKey = UserDefaults.standard.string(forKey: "GEMINI_API_KEY") ?? ""
        geminiBaseURL = UserDefaults.standard.string(forKey: "GEMINI_BASE_URL") ?? ""
        anthropicAPIKey = UserDefaults.standard.string(forKey: "ANTHROPIC_API_KEY") ?? ""
        anthropicBaseURL = UserDefaults.standard.string(forKey: "ANTHROPIC_BASE_URL") ?? ""
        openAIAPIKey = UserDefaults.standard.string(forKey: "OPENAI_API_KEY") ?? ""
        openAIBaseURL = UserDefaults.standard.string(forKey: "OPENAI_BASE_URL") ?? ""

        // Try reading old global models first for migration, else fallback to defaults
        let oldEasy = UserDefaults.standard.string(forKey: "MODEL_EASY")
        let oldMedium = UserDefaults.standard.string(forKey: "MODEL_MEDIUM")
        let oldHard = UserDefaults.standard.string(forKey: "MODEL_HARD")

        self.geminiModelEasy = UserDefaults.standard.string(forKey: "GEMINI_MODEL_EASY") ?? (savedProvider == "Gemini" && oldEasy != nil ? oldEasy! : "gemini-3.1-flash-lite")
        self.geminiModelMedium = UserDefaults.standard.string(forKey: "GEMINI_MODEL_MEDIUM") ?? (savedProvider == "Gemini" && oldMedium != nil ? oldMedium! : "gemini-3.5-flash")
        self.geminiModelHard = UserDefaults.standard.string(forKey: "GEMINI_MODEL_HARD") ?? (savedProvider == "Gemini" && oldHard != nil ? oldHard! : "gemini-3.1-pro-preview")
        
        self.anthropicModelEasy = UserDefaults.standard.string(forKey: "ANTHROPIC_MODEL_EASY") ?? (savedProvider == "Anthropic" && oldEasy != nil ? oldEasy! : "claude-haiku-4-5-20251001")
        self.anthropicModelMedium = UserDefaults.standard.string(forKey: "ANTHROPIC_MODEL_MEDIUM") ?? (savedProvider == "Anthropic" && oldMedium != nil ? oldMedium! : "claude-sonnet-5")
        self.anthropicModelHard = UserDefaults.standard.string(forKey: "ANTHROPIC_MODEL_HARD") ?? (savedProvider == "Anthropic" && oldHard != nil ? oldHard! : "claude-fable-5")
        
        self.openaiModelEasy = UserDefaults.standard.string(forKey: "OPENAI_MODEL_EASY") ?? (savedProvider == "OpenAI" && oldEasy != nil ? oldEasy! : "gpt-5.6-luna")
        self.openaiModelMedium = UserDefaults.standard.string(forKey: "OPENAI_MODEL_MEDIUM") ?? (savedProvider == "OpenAI" && oldMedium != nil ? oldMedium! : "gpt-5.6-terra")
        self.openaiModelHard = UserDefaults.standard.string(forKey: "OPENAI_MODEL_HARD") ?? (savedProvider == "OpenAI" && oldHard != nil ? oldHard! : "gpt-5.6-sol")
        
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
        switch primaryProvider {
        case LLMProvider.anthropic.rawValue:
            return !anthropicAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
        case LLMProvider.openai.rawValue:
            return !openAIAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            return !geminiAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
}
