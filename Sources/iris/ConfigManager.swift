import Foundation
import SwiftUI

@Observable
class ConfigManager: @unchecked Sendable {
    @ObservationIgnored nonisolated(unsafe) static let shared = ConfigManager()
    
    var geminiAPIKey: String {
        didSet { UserDefaults.standard.set(geminiAPIKey, forKey: "GEMINI_API_KEY") }
    }
    
    var googleClientID: String {
        didSet { UserDefaults.standard.set(googleClientID, forKey: "GOOGLE_CLIENT_ID") }
    }
    
    var googleClientSecret: String {
        didSet { UserDefaults.standard.set(googleClientSecret, forKey: "GOOGLE_CLIENT_SECRET") }
    }
    
    init() {
        self.geminiAPIKey = UserDefaults.standard.string(forKey: "GEMINI_API_KEY") ?? ""
        self.googleClientID = UserDefaults.standard.string(forKey: "GOOGLE_CLIENT_ID") ?? ""
        self.googleClientSecret = UserDefaults.standard.string(forKey: "GOOGLE_CLIENT_SECRET") ?? ""
    }
    
    var isConfigured: Bool {
        return !geminiAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
