import Foundation
import SwiftUI

public enum LLMProvider: String, CaseIterable, Identifiable, Sendable {
    case gemini = "Gemini"
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    
    public var id: String { rawValue }
}

public enum GeminiAuthMode: String, CaseIterable, Identifiable, Sendable {
    case apiKey = "API Key"
    case adc = "Application Default Credentials (ADC)"
    
    public var id: String { rawValue }
}

@Observable
class ConfigManager: @unchecked Sendable {
    @ObservationIgnored static let shared = ConfigManager()
    
    var appearanceTheme: String {
        didSet { UserDefaults.standard.set(appearanceTheme, forKey: "APPEARANCE_THEME") }
    }
    
    var copyChatsAsMarkdown: Bool {
        didSet { UserDefaults.standard.set(copyChatsAsMarkdown, forKey: "COPY_CHATS_AS_MARKDOWN") }
    }
    
    var primaryProvider: String {
        didSet { UserDefaults.standard.set(primaryProvider, forKey: "PRIMARY_PROVIDER") }
    }
    
    var geminiAuthMode: String {
        didSet { UserDefaults.standard.set(geminiAuthMode, forKey: "GEMINI_AUTH_MODE") }
    }
    
    var geminiAPIKey: String {
        didSet { updateSecret(key: "GEMINI_API_KEY", value: geminiAPIKey) }
    }
    
    var geminiBaseURL: String {
        didSet { UserDefaults.standard.set(geminiBaseURL, forKey: "GEMINI_BASE_URL") }
    }
    
    var anthropicAPIKey: String {
        didSet { updateSecret(key: "ANTHROPIC_API_KEY", value: anthropicAPIKey) }
    }
    
    var anthropicBaseURL: String {
        didSet { UserDefaults.standard.set(anthropicBaseURL, forKey: "ANTHROPIC_BASE_URL") }
    }
    
    var openAIAPIKey: String {
        didSet { updateSecret(key: "OPENAI_API_KEY", value: openAIAPIKey) }
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
        didSet { updateSecret(key: "GOOGLE_CLIENT_ID", value: googleClientID) }
    }
    
    var googleClientSecret: String {
        didSet { updateSecret(key: "GOOGLE_CLIENT_SECRET", value: googleClientSecret) }
    }
    
    var googleAccessToken: String {
        didSet { updateSecret(key: "GOOGLE_ACCESS_TOKEN", value: googleAccessToken) }
    }
    
    var googleRefreshToken: String {
        didSet { updateSecret(key: "GOOGLE_REFRESH_TOKEN", value: googleRefreshToken) }
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
    
    var enableAdvancedPromptInjectionProtection: Bool {
        didSet { UserDefaults.standard.set(enableAdvancedPromptInjectionProtection, forKey: "ENABLE_PROMPT_INJECTION_PROTECTION") }
    }
    
    var promptGuardEngine: String {
        didSet { UserDefaults.standard.set(promptGuardEngine, forKey: "PROMPT_GUARD_ENGINE") }
    }
    
    var promptGuardModel: String {
        didSet { UserDefaults.standard.set(promptGuardModel, forKey: "PROMPT_GUARD_MODEL") }
    }
    
    var promptGuardCoreMLModel: String {
        didSet { UserDefaults.standard.set(promptGuardCoreMLModel, forKey: "PROMPT_GUARD_COREML_MODEL") }
    }
    
    init() {
        let savedProvider = UserDefaults.standard.string(forKey: "PRIMARY_PROVIDER") ?? "Gemini"
        self.primaryProvider = savedProvider
        self.geminiAuthMode = UserDefaults.standard.string(forKey: "GEMINI_AUTH_MODE") ?? GeminiAuthMode.apiKey.rawValue
        
        self.appearanceTheme = UserDefaults.standard.string(forKey: "APPEARANCE_THEME") ?? "system"
        
        if UserDefaults.standard.object(forKey: "COPY_CHATS_AS_MARKDOWN") != nil {
            self.copyChatsAsMarkdown = UserDefaults.standard.bool(forKey: "COPY_CHATS_AS_MARKDOWN")
        } else {
            self.copyChatsAsMarkdown = true
        }
        
        var keychainSecrets = KeychainManager.shared.loadSecrets()
        var secretsMigrated = false
        
        func migrate(key: String, dest: inout String) {
            if let keychainValue = keychainSecrets[key] {
                dest = keychainValue
            } else if let udValue = UserDefaults.standard.string(forKey: key), !udValue.isEmpty {
                dest = udValue
                keychainSecrets[key] = udValue
                UserDefaults.standard.removeObject(forKey: key)
                secretsMigrated = true
            } else {
                dest = ""
            }
        }
        
        var geminiKey = ""
        migrate(key: "GEMINI_API_KEY", dest: &geminiKey)
        self.geminiAPIKey = geminiKey
        
        var anthropicKey = ""
        migrate(key: "ANTHROPIC_API_KEY", dest: &anthropicKey)
        self.anthropicAPIKey = anthropicKey
        
        var openaiKey = ""
        migrate(key: "OPENAI_API_KEY", dest: &openaiKey)
        self.openAIAPIKey = openaiKey
        
        geminiBaseURL = UserDefaults.standard.string(forKey: "GEMINI_BASE_URL") ?? ""
        anthropicBaseURL = UserDefaults.standard.string(forKey: "ANTHROPIC_BASE_URL") ?? ""
        openAIBaseURL = UserDefaults.standard.string(forKey: "OPENAI_BASE_URL") ?? ""

        // Try reading old global models first for migration, else fallback to defaults.
        // The old global keys only migrate onto whichever provider was active at the time.
        let oldEasy = UserDefaults.standard.string(forKey: "MODEL_EASY")
        let oldMedium = UserDefaults.standard.string(forKey: "MODEL_MEDIUM")
        let oldHard = UserDefaults.standard.string(forKey: "MODEL_HARD")

        func resolveModel(key: String, provider: String, migrated: String?, fallback: String) -> String {
            if let saved = UserDefaults.standard.string(forKey: key) {
                return saved
            }
            if savedProvider == provider, let migrated {
                return migrated
            }
            return fallback
        }

        self.geminiModelEasy = resolveModel(key: "GEMINI_MODEL_EASY", provider: "Gemini", migrated: oldEasy, fallback: "gemini-3.1-flash-lite")
        self.geminiModelMedium = resolveModel(key: "GEMINI_MODEL_MEDIUM", provider: "Gemini", migrated: oldMedium, fallback: "gemini-3.5-flash")
        self.geminiModelHard = resolveModel(key: "GEMINI_MODEL_HARD", provider: "Gemini", migrated: oldHard, fallback: "gemini-3.1-pro-preview")

        self.anthropicModelEasy = resolveModel(key: "ANTHROPIC_MODEL_EASY", provider: "Anthropic", migrated: oldEasy, fallback: "claude-haiku-4-5-20251001")
        self.anthropicModelMedium = resolveModel(key: "ANTHROPIC_MODEL_MEDIUM", provider: "Anthropic", migrated: oldMedium, fallback: "claude-sonnet-5")
        self.anthropicModelHard = resolveModel(key: "ANTHROPIC_MODEL_HARD", provider: "Anthropic", migrated: oldHard, fallback: "claude-fable-5")

        self.openaiModelEasy = resolveModel(key: "OPENAI_MODEL_EASY", provider: "OpenAI", migrated: oldEasy, fallback: "gpt-5.6-luna")
        self.openaiModelMedium = resolveModel(key: "OPENAI_MODEL_MEDIUM", provider: "OpenAI", migrated: oldMedium, fallback: "gpt-5.6-terra")
        self.openaiModelHard = resolveModel(key: "OPENAI_MODEL_HARD", provider: "OpenAI", migrated: oldHard, fallback: "gpt-5.6-sol")
        
        var gClientId = ""
        migrate(key: "GOOGLE_CLIENT_ID", dest: &gClientId)
        self.googleClientID = gClientId
        
        var gClientSecret = ""
        migrate(key: "GOOGLE_CLIENT_SECRET", dest: &gClientSecret)
        self.googleClientSecret = gClientSecret
        
        var gAccessToken = ""
        migrate(key: "GOOGLE_ACCESS_TOKEN", dest: &gAccessToken)
        self.googleAccessToken = gAccessToken
        
        var gRefreshToken = ""
        migrate(key: "GOOGLE_REFRESH_TOKEN", dest: &gRefreshToken)
        self.googleRefreshToken = gRefreshToken
        
        if secretsMigrated {
            KeychainManager.shared.saveSecrets(keychainSecrets)
        }
        self.googleTokenExpiry = UserDefaults.standard.double(forKey: "GOOGLE_TOKEN_EXPIRY")
        self.enableSandboxing = UserDefaults.standard.bool(forKey: "ENABLE_SANDBOXING")
        self.sandboxImage = UserDefaults.standard.string(forKey: "SANDBOX_IMAGE") ?? "ubuntu:latest"
        
        self.enableVibecop = UserDefaults.standard.bool(forKey: "ENABLE_VIBECOP")
        let savedEngine = UserDefaults.standard.string(forKey: "VIBECOP_ENGINE") ?? ""
        self.vibecopEngine = savedEngine.isEmpty ? "llama_cpp" : savedEngine
        
        let savedVibecop = UserDefaults.standard.string(forKey: "VIBECOP_MODEL") ?? ""
        self.vibecopModel = savedVibecop.isEmpty ? "Llama-3.2-1B-Instruct-Q4_K_M.gguf" : savedVibecop
        
        if UserDefaults.standard.object(forKey: "ENABLE_PROMPT_INJECTION_PROTECTION") != nil {
            self.enableAdvancedPromptInjectionProtection = UserDefaults.standard.bool(forKey: "ENABLE_PROMPT_INJECTION_PROTECTION")
        } else {
            self.enableAdvancedPromptInjectionProtection = true // Default to true
        }
        
        let savedPromptEngine = UserDefaults.standard.string(forKey: "PROMPT_GUARD_ENGINE") ?? ""
        self.promptGuardEngine = savedPromptEngine.isEmpty ? "llama_cpp" : savedPromptEngine
        
        let savedPromptModel = UserDefaults.standard.string(forKey: "PROMPT_GUARD_MODEL") ?? ""
        self.promptGuardModel = savedPromptModel.isEmpty ? "Qwen-1.5B-Q4_K_M.gguf" : savedPromptModel
        
        let savedCoreMLModel = UserDefaults.standard.string(forKey: "PROMPT_GUARD_COREML_MODEL") ?? ""
        self.promptGuardCoreMLModel = savedCoreMLModel.isEmpty ? "https://luthen.scromp.net/iris/distilbert-prompt-injection.mlmodelc.zip" : savedCoreMLModel
    }
    
    var isConfigured: Bool {
        switch primaryProvider {
        case LLMProvider.anthropic.rawValue:
            return !anthropicAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
        case LLMProvider.openai.rawValue:
            return !openAIAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
        default:
            if geminiAuthMode == GeminiAuthMode.adc.rawValue {
                return true
            }
            return !geminiAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }
    
    private func updateSecret(key: String, value: String) {
        var secrets = KeychainManager.shared.loadSecrets()
        secrets[key] = value
        KeychainManager.shared.saveSecrets(secrets)
    }
}
