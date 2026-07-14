import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @Bindable private var config = ConfigManager.shared
    @State private var isInstallingContainer = false
    @State private var installError: String?
    @State private var downloader = ModelDownloader.shared
    @State private var showingDownloadError = false
    
    var body: some View {
        TabView {
            // MARK: - General Tab
            Form {
                Section(header: Text("Global Shortcuts").font(.headline)) {
                    KeyboardShortcuts.Recorder("Toggle Iris:", name: .toggleIris)
                }
                .padding(.bottom)
                
                Section(header: Text("Preferences").font(.headline)) {
                    Toggle("Copy chats as Markdown (default)", isOn: $config.copyChatsAsMarkdown)
                        .help("If disabled, copies will default to plain text without markdown formatting.")
                }
                .padding(.bottom)
            }
            .formStyle(.grouped)
            .padding(20)
            .tabItem {
                Label("General", systemImage: "gearshape")
            }
            
            // MARK: - Models Tab
            Form {
                Section(header: Text("LLM Providers").font(.headline)) {
                    Picker("Primary Provider", selection: $config.primaryProvider) {
                        ForEach(LLMProvider.allCases) { provider in
                            Text(provider.rawValue).tag(provider.rawValue)
                        }
                    }
                    .padding(.bottom)
                    
                    if config.primaryProvider == LLMProvider.gemini.rawValue {
                        Picker("Authentication Method", selection: $config.geminiAuthMode) {
                            ForEach(GeminiAuthMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode.rawValue)
                            }
                        }
                        
                        if config.geminiAuthMode == GeminiAuthMode.adc.rawValue {
                            Text("Using Application Default Credentials (ADC). Authenticate locally via:\n`gcloud auth application-default login --scopes=\"https://www.googleapis.com/auth/cloud-platform,https://www.googleapis.com/auth/generative-language\"`")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            SecureField("Gemini API Key", text: $config.geminiAPIKey)
                                .help("Required for Gemini models to function.")
                        }
                        
                        TextField("Gemini Base URL (Optional)", text: $config.geminiBaseURL)
                            .help("Leave blank for default endpoint")
                        TextField("Easy Subagent Model", text: $config.geminiModelEasy)
                            .help("Used for simple and repetitive tasks.")
                        TextField("Primary / Medium Model", text: $config.geminiModelMedium)
                            .help("Used for standard generation and reasoning.")
                        TextField("Hard Subagent Model", text: $config.geminiModelHard)
                            .help("Used for complex reasoning and evaluation.")
                    } else if config.primaryProvider == LLMProvider.anthropic.rawValue {
                        SecureField("Anthropic API Key", text: $config.anthropicAPIKey)
                            .help("Required for Anthropic Claude models to function.")
                        TextField("Anthropic Base URL (Optional)", text: $config.anthropicBaseURL)
                            .help("Leave blank for default endpoint")
                        TextField("Easy Subagent Model", text: $config.anthropicModelEasy)
                            .help("Used for simple and repetitive tasks.")
                        TextField("Primary / Medium Model", text: $config.anthropicModelMedium)
                            .help("Used for standard generation and reasoning.")
                        TextField("Hard Subagent Model", text: $config.anthropicModelHard)
                            .help("Used for complex reasoning and evaluation.")
                    } else if config.primaryProvider == LLMProvider.openai.rawValue {
                        SecureField("OpenAI API Key", text: $config.openAIAPIKey)
                            .help("Required for OpenAI GPT/o1 models to function.")
                        TextField("OpenAI Base URL (Optional)", text: $config.openAIBaseURL)
                            .help("Overrides the default openai endpoint. Useful for deepseek or local compatible servers.")
                        TextField("Easy Subagent Model", text: $config.openaiModelEasy)
                            .help("Used for simple and repetitive tasks.")
                        TextField("Primary / Medium Model", text: $config.openaiModelMedium)
                            .help("Used for standard generation and reasoning.")
                        TextField("Hard Subagent Model", text: $config.openaiModelHard)
                            .help("Used for complex reasoning and evaluation.")
                    }
                }
                .padding(.bottom)
                
                Section(header: Text("Vibecop Guardian").font(.headline)) {
                    Toggle("Enable Vibecop", isOn: $config.enableVibecop)
                    
                    if config.enableVibecop {
                        Picker("Engine", selection: $config.vibecopEngine) {
                            Text("Llama.cpp (Embedded)").tag("llama_cpp")
                            Text("Ollama (Local Daemon)").tag("ollama")
                            Text("MLX (Apple Silicon)").tag("mlx")
                            Text("Cloud (Primary Provider)").tag("cloud")
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
                
                Section(header: Text("Advanced Prompt Injection Protection").font(.headline)) {
                    Toggle("Enable Protection (Tier 2 & 3)", isOn: $config.enableAdvancedPromptInjectionProtection)
                    
                    if config.enableAdvancedPromptInjectionProtection {
                        Picker("Engine", selection: $config.promptGuardEngine) {
                            Text("Llama.cpp (Embedded)").tag("llama_cpp")
                            Text("Ollama (Local Daemon)").tag("ollama")
                            Text("MLX (Apple Silicon)").tag("mlx")
                            Text("Cloud (Primary Provider)").tag("cloud")
                        }
                        
                        if config.promptGuardEngine == "llama_cpp" {
                            TextField("GGUF Model", text: $config.promptGuardModel)
                                .help("The GGUF model file name for the Tier 3 Canary (must be in ~/.iris/models/)")
                            
                            let isDownloaded = downloader.isModelDownloaded(name: config.promptGuardModel)
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
                                            await downloader.downloadModel(name: config.promptGuardModel)
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
                            TextField("Model Name", text: $config.promptGuardModel)
                                .help("The model to use for the Tier 3 Canary evaluation")
                        }
                        
                        Text("This model is used as a sacrificial canary to test untrusted payloads for malicious instructions.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom)
            }
            .formStyle(.grouped)
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
            .formStyle(.grouped)
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
            .formStyle(.grouped)
            .padding(20)
            .tabItem {
                Label("Advanced", systemImage: "lock.shield")
            }
        }
        .frame(minWidth: 600, minHeight: 600)
        .onChange(of: downloader.error) { _, newValue in
            if newValue != nil {
                showingDownloadError = true
            }
        }
        .alert("Download Error", isPresented: $showingDownloadError) {
            Button("OK", role: .cancel) { downloader.error = nil }
        } message: {
            Text(downloader.error ?? "An unknown error occurred.")
        }
    }
    
}
