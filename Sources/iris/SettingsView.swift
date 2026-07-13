import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @Bindable private var config = ConfigManager.shared
    @State private var availableModels: [String] = []
    @State private var isInstallingContainer = false
    @State private var installError: String?
    @State private var downloader = ModelDownloader.shared
    
    var body: some View {
        TabView {
            // MARK: - General Tab
            Form {
                Section(header: Text("Global Shortcuts").font(.headline)) {
                    KeyboardShortcuts.Recorder("Toggle Iris:", name: .toggleIris)
                }
                .padding(.bottom)
            }
            .padding(20)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            
            // MARK: - Models Tab
            Form {
                Section(header: Text("LLM Providers").font(.headline)) {
                    SecureField("Gemini API Key", text: $config.geminiAPIKey)
                        .help("Required for Iris to function.")
                        .onChange(of: config.geminiAPIKey) { _, _ in
                            fetchModels()
                        }
                    
                    Picker("Easy Subagent Model", selection: $config.modelEasy) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    Picker("Primary / Medium Model", selection: $config.modelMedium) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    Picker("Hard Subagent Model", selection: $config.modelHard) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .onAppear {
                        if availableModels.isEmpty {
                            availableModels = [
                                "gemini-3.1-flash-lite", 
                                "gemini-3.5-flash", 
                                "gemini-3.1-pro-preview", 
                                "gemini-2.5-flash"
                            ]
                            if !availableModels.contains(config.modelEasy) { availableModels.append(config.modelEasy) }
                            if !availableModels.contains(config.modelMedium) { availableModels.append(config.modelMedium) }
                            if !availableModels.contains(config.modelHard) { availableModels.append(config.modelHard) }
                        }
                        fetchModels()
                    }
                }
                .padding(.bottom)
                
                Section(header: Text("Vibecop (Local Evaluation)").font(.headline)) {
                    Toggle("Enable Vibecop", isOn: $config.enableVibecop)
                    
                    if config.enableVibecop {
                        Picker("Engine", selection: $config.vibecopEngine) {
                            Text("Llama.cpp (Embedded)").tag("llama_cpp")
                            Text("Ollama (Local Daemon)").tag("ollama")
                            Text("MLX (Apple Silicon)").tag("mlx")
                        }
                        
                        if config.vibecopEngine == "llama_cpp" {
                            TextField("GGUF Model", text: $config.vibecopModel)
                                .help("The GGUF model file name (must be in ~/.iris/models/)")
                            
                            let isDownloaded = downloader.isModelDownloaded(name: config.vibecopModel)
                            if !isDownloaded {
                                if downloader.isDownloading {
                                    HStack {
                                        ProgressView(value: downloader.progress)
                                            .progressViewStyle(.linear)
                                        Text("\(Int(downloader.progress * 100))%")
                                            .font(.caption)
                                    }
                                } else {
                                    Button("Download Model") {
                                        Task {
                                            await downloader.downloadModel(name: config.vibecopModel)
                                        }
                                    }
                                    Text("This will download approx. 1-2GB of weights to your disk.")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                
                                if let error = downloader.error {
                                    Text("Error: \(error)").foregroundColor(.red).font(.caption)
                                }
                            } else {
                                Text("✅ Model is downloaded and ready.")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        } else {
                            TextField("Ollama Model", text: $config.vibecopModel)
                                .help("The Ollama model to use for Vibecop background evaluation (e.g. llama3.2, gemma2:9b)")
                        }
                        
                        Text("Vibecop runs periodically in the background to evaluate the conversation state.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom)
            }
            .padding(20)
            .tabItem {
                Label("Models", systemImage: "cpu")
            }
            
            // MARK: - Integrations Tab
            Form {
                Section(header: Text("Google Workspace (OAuth)").font(.headline)) {
                    TextField("Client ID", text: $config.googleClientID)
                    SecureField("Client Secret", text: $config.googleClientSecret)
                    
                    Text("These credentials enable external tools for Google Calendar, Docs, Drive, Sheets, Gmail, and Tasks.")
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
                .padding(.bottom)
            }
            .padding(20)
            .tabItem {
                Label("Integrations", systemImage: "link")
            }
            
            // MARK: - Advanced Tab
            Form {
                Section(header: Text("Sandboxing").font(.headline)) {
                    Toggle("Enable sandboxing for subagents", isOn: $config.enableSandboxing)
                        .onChange(of: config.enableSandboxing) { _, newValue in
                            if newValue && !SandboxingManager.shared.isContainerInstalled {
                                // Turn it back off until installed
                                config.enableSandboxing = false
                                isInstallingContainer = true
                                installError = nil
                                
                                SandboxingManager.shared.installContainer { success, error in
                                    isInstallingContainer = false
                                    if success {
                                        config.enableSandboxing = true
                                    } else {
                                        installError = error
                                    }
                                }
                            }
                        }
                    
                    if config.enableSandboxing {
                        TextField("Sandbox Image", text: $config.sandboxImage)
                            .help("The Docker/OCI image to use for sandboxed commands (e.g., ubuntu:latest)")
                    }
                    
                    if isInstallingContainer {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.5)
                            Text("Downloading and installing Apple container...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let error = installError {
                        Text("Error: \(error)")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                    
                    Text("Runs dangerous commands like web searches in lightweight Linux virtual machines on your Mac.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(20)
            .tabItem {
                Label("Advanced", systemImage: "lock.shield")
            }
        }
        .frame(minWidth: 600, minHeight: 600)
    }
    
    private func fetchModels() {
        Task {
            do {
                let models = try await LLMClient().fetchAvailableModels()
                if !models.isEmpty {
                    await MainActor.run {
                        if !models.contains(config.modelEasy) { config.modelEasy = models.first! }
                        if !models.contains(config.modelMedium) { config.modelMedium = models.first! }
                        if !models.contains(config.modelHard) { config.modelHard = models.first! }
                        
                        self.availableModels = models
                    }
                }
            } catch {
                print("Failed to fetch models: \(error)")
            }
        }
    }
}
