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
    
    var googleAccessToken: String {
        didSet { UserDefaults.standard.set(googleAccessToken, forKey: "GOOGLE_ACCESS_TOKEN") }
    }
    
    var googleRefreshToken: String {
        didSet { UserDefaults.standard.set(googleRefreshToken, forKey: "GOOGLE_REFRESH_TOKEN") }
    }
    
    var googleTokenExpiry: Double {
        didSet { UserDefaults.standard.set(googleTokenExpiry, forKey: "GOOGLE_TOKEN_EXPIRY") }
    }
    
    init() {
        self.geminiAPIKey = UserDefaults.standard.string(forKey: "GEMINI_API_KEY") ?? ""
        self.googleClientID = UserDefaults.standard.string(forKey: "GOOGLE_CLIENT_ID") ?? ""
        self.googleClientSecret = UserDefaults.standard.string(forKey: "GOOGLE_CLIENT_SECRET") ?? ""
        self.googleAccessToken = UserDefaults.standard.string(forKey: "GOOGLE_ACCESS_TOKEN") ?? ""
        self.googleRefreshToken = UserDefaults.standard.string(forKey: "GOOGLE_REFRESH_TOKEN") ?? ""
        self.googleTokenExpiry = UserDefaults.standard.double(forKey: "GOOGLE_TOKEN_EXPIRY")
    }
    
    var isConfigured: Bool {
        return !geminiAPIKey.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
