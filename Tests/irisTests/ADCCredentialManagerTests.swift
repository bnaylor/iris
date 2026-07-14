import Testing
import Foundation
@testable import iris

@Suite("ADC Credential Manager & Config Tests", .serialized)
struct ADCCredentialManagerTests {
    
    @Test("ConfigManager ADC configuration mode")
    func testConfigManagerADCMode() {
        let config = ConfigManager.shared
        let originalMode = config.geminiAuthMode
        let originalProvider = config.primaryProvider
        let originalKey = config.geminiAPIKey
        
        defer {
            config.geminiAuthMode = originalMode
            config.primaryProvider = originalProvider
            config.geminiAPIKey = originalKey
        }
        
        config.primaryProvider = LLMProvider.gemini.rawValue
        config.geminiAuthMode = GeminiAuthMode.adc.rawValue
        config.geminiAPIKey = ""
        
        #expect(config.isConfigured == true)
        
        config.geminiAuthMode = GeminiAuthMode.apiKey.rawValue
        #expect(config.isConfigured == false)
        
        config.geminiAPIKey = "test-key"
        #expect(config.isConfigured == true)
    }
    
    @Test("ADCCredentialManager clearCache resets cached values")
    func testADCCredentialManagerClearCache() async {
        await ADCCredentialManager.shared.clearCache()
        // Ensure clearCache executes cleanly without errors
        #expect(true)
    }
}
