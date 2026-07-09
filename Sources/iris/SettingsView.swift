import SwiftUI

struct SettingsView: View {
    @Bindable private var config = ConfigManager.shared
    
    var body: some View {
        Form {
            Section(header: Text("LLM Providers").font(.headline)) {
                SecureField("Gemini API Key", text: $config.geminiAPIKey)
                    .help("Required for Iris to function.")
            }
            .padding(.bottom)
            
            Section(header: Text("Google Workspace (OAuth)").font(.headline)) {
                TextField("Client ID", text: $config.googleClientID)
                SecureField("Client Secret", text: $config.googleClientSecret)
                
                Text("These credentials enable external tools for Google Calendar, Docs, and Sheets.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(20)
        .frame(width: 450, height: 250)
    }
}
