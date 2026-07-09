import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @Bindable private var config = ConfigManager.shared
    @State private var availableModels: [String] = []
    
    var body: some View {
        Form {
            Section(header: Text("Global Shortcuts").font(.headline)) {
                KeyboardShortcuts.Recorder("Toggle Iris:", name: .toggleIris)
            }
            .padding(.bottom)
            
            Section(header: Text("LLM Providers").font(.headline)) {
                SecureField("Gemini API Key", text: $config.geminiAPIKey)
                    .help("Required for Iris to function.")
                    .onChange(of: config.geminiAPIKey) { _, _ in
                        fetchModels()
                    }
                
                Picker("Model", selection: $config.geminiModel) {
                    ForEach(availableModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .onAppear {
                    if availableModels.isEmpty {
                        availableModels = [config.geminiModel]
                    }
                    fetchModels()
                }
            }
            .padding(.bottom)
            
            Section(header: Text("Google Workspace (OAuth)").font(.headline)) {
                TextField("Client ID", text: $config.googleClientID)
                SecureField("Client Secret", text: $config.googleClientSecret)
                
                Text("These credentials enable external tools for Google Calendar, Docs, and Sheets.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !config.googleAccessToken.isEmpty {
                    Text("✅ Connected to Google Workspace")
                        .foregroundColor(.green)
                        .font(.caption)
                }
                
                Button("Connect to Google") {
                    Task {
                        do {
                            try await OAuthManager.shared.startOAuthFlow()
                        } catch {
                            print("OAuth Error: \(error)")
                        }
                    }
                }
                .disabled(config.googleClientID.isEmpty || config.googleClientSecret.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 450, minHeight: 350)
    }
    
    private func fetchModels() {
        Task {
            do {
                let models = try await LLMClient().fetchAvailableModels()
                if !models.isEmpty {
                    await MainActor.run {
                        if !models.contains(config.geminiModel) {
                            config.geminiModel = models.first!
                        }
                        self.availableModels = models
                    }
                }
            } catch {
                print("Failed to fetch models: \(error)")
            }
        }
    }
}
