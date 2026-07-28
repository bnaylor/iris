import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @Bindable private var config = ConfigManager.shared
    @State private var isInstallingContainer = false
    @State private var installError: String?
    @State private var downloader = ModelDownloader.shared
    @State private var showingDownloadError = false
    
    @State private var availableUpdate: ReleaseInfo?
    @State private var isCheckingForUpdates = false
    @State private var updateCheckStatusMessage: String?
    
    @State private var vibecopTestStatus: String?
    @State private var tier2TestStatus: String?
    @State private var tier3TestStatus: String?
    
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
                    Picker("Default emoji skin tone", selection: $config.defaultEmojiSkinTone) {
                        Text("Default 👋").tag(SkinTone.none.rawValue)
                        Text("Light 👋🏻").tag(SkinTone.light.rawValue)
                        Text("Medium-Light 👋🏼").tag(SkinTone.mediumLight.rawValue)
                        Text("Medium 👋🏽").tag(SkinTone.medium.rawValue)
                        Text("Medium-Dark 👋🏾").tag(SkinTone.mediumDark.rawValue)
                        Text("Dark 👋🏿").tag(SkinTone.dark.rawValue)
                    }
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

                Section(header: Text("Auxiliary Vision Engine").font(.headline)) {
                    Picker("Engine", selection: $config.auxiliaryVisionEngine) {
                        Text("None").tag("")
                        Text("Ollama (Local Daemon)").tag("ollama")
                        Text("Cloud (Primary Provider)").tag("cloud")
                    }
                    
                    if !config.auxiliaryVisionEngine.isEmpty {
                        TextField("Vision Model Name", text: $config.auxiliaryVisionModel)
                            .help("The model to use for vision processing when primary model is non-vision (e.g. llama3.2-vision, gemma4:12b)")
                    }
                    
                    Text("When your active primary model does not support vision, Iris routes image attachments through this auxiliary vision engine to generate descriptive text.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom)
            }
            .formStyle(.grouped)
            .padding(20)
            .tabItem {
                Label("Models", systemImage: "cpu")
            }
            
            // MARK: - Vibecop Tab
            Form {
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
                                            await downloader.downloadModel(name: config.vibecopModel, assignResolvedNameTo: \.vibecopModel)
                                        }
                                    }
                                    Text("This will download approx. \(downloader.approximateSize(for: config.vibecopModel)) of weights to your disk.")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                
                                if let error = downloader.error {
                                    Text("Error: \(error)").foregroundColor(.red).font(.caption)
                                }
                            } else {
                                HStack {
                                    Text("✅ Model is downloaded and ready.")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                    
                                    Button("Test Model") {
                                        Task {
                                            do {
                                                let engineType = AuxiliaryEngineType(rawValue: config.vibecopEngine) ?? .llamaCPP
                                                let auxConfig = AuxiliaryModelConfig(role: "vibecop", engineType: engineType, modelPathOrName: config.vibecopModel)
                                                let engine = try await AuxiliaryModelManager.shared.getEngine(for: "vibecop", config: auxConfig)
                                                _ = try await engine.generate(prompt: "Hello", jsonSchema: nil)
                                                vibecopTestStatus = "✅ Success"
                                            } catch {
                                                vibecopTestStatus = "❌ Failed: \(error.localizedDescription)"
                                            }
                                        }
                                    }
                                    .buttonStyle(.link)
                                    .font(.caption)
                                    
                                    if let status = vibecopTestStatus {
                                        Text(status).font(.caption).foregroundColor(status.starts(with: "✅") ? .green : .red)
                                    }
                                }
                            }
                        } else {
                            TextField("Ollama/Cloud Model", text: $config.vibecopModel)
                                .help("The external model to use for Vibecop background evaluation (e.g. qwen3.5, gemma4:12b)")
                            
                            HStack {
                                Text("✅ Assuming model is ready via external daemon.")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                    
                                Button("Test Model") {
                                    Task {
                                        do {
                                            let engineType = AuxiliaryEngineType(rawValue: config.vibecopEngine) ?? .llamaCPP
                                            let auxConfig = AuxiliaryModelConfig(role: "vibecop", engineType: engineType, modelPathOrName: config.vibecopModel)
                                            let engine = try await AuxiliaryModelManager.shared.getEngine(for: "vibecop", config: auxConfig)
                                            _ = try await engine.generate(prompt: "Hello", jsonSchema: nil)
                                            vibecopTestStatus = "✅ Success"
                                        } catch {
                                            vibecopTestStatus = "❌ Failed: \(error.localizedDescription)"
                                        }
                                    }
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                                
                                if let status = vibecopTestStatus {
                                    Text(status).font(.caption).foregroundColor(status.starts(with: "✅") ? .green : .red)
                                }
                            }
                        }
                        
                        Text("Vibecop runs periodically in the background to evaluate the conversation state.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom)
            }
            .formStyle(.grouped)
            .padding(20)
            .tabItem {
                Label("Vibecop", systemImage: "eye.circle")
            }
                       // MARK: - Security Tab
            Form {
                Section(header: Text("General Protection").font(.headline)) {
                    Toggle("Enable Protection (Tier 2 & 3)", isOn: $config.enableAdvancedPromptInjectionProtection)
                    if config.enableAdvancedPromptInjectionProtection {
                        Text("Iris will intercept untrusted data from the web before your main LLM reads it, protecting you from adversarial attacks and hidden instructions.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if config.enableAdvancedPromptInjectionProtection {
                    Section(header: Text("Tier 2: Fast Local Classifier").font(.headline)) {
                        Text("Rapidly classifies text as safe or malicious on-device — CoreML (Apple Neural Engine) or ONNX Runtime (CPU).")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Model .zip URL or Path", text: $config.promptGuardCoreMLModel)
                            .help("Provide a URL to a .mlmodelc.zip (CoreML) or .onnx.zip (ONNX Runtime) to download and enable the Tier 2 classifier.")
                        
                        if !config.promptGuardCoreMLModel.isEmpty {
                            let coreMLFilename = config.promptGuardCoreMLModel.starts(with: "http") ? (URL(string: config.promptGuardCoreMLModel)?.lastPathComponent ?? config.promptGuardCoreMLModel) : config.promptGuardCoreMLModel
                            let coreMLNameNoZip = coreMLFilename.hasSuffix(".zip") ? String(coreMLFilename.dropLast(4)) : coreMLFilename
                            let isCoreMLDownloaded = downloader.isModelDownloaded(name: coreMLNameNoZip)
                            
                            if !isCoreMLDownloaded {
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
                                            await downloader.downloadModel(name: config.promptGuardCoreMLModel)
                                        }
                                    }
                                    Text("Downloads and unzips the model to enable Tier 2 locally (~650 MB for the default DeBERTa model).")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            } else {
                                HStack {
                                    Text("✅ Tier 2 model is present.")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                        
                                    Button("Test Model") {
                                        Task {
                                            do {
                                                try await CoreMLEvaluator.shared.loadModelIfNeeded()
                                                if CoreMLEvaluator.shared.hasModelLoaded {
                                                    _ = try await CoreMLEvaluator.shared.evaluate(text: "Hello")
                                                    tier2TestStatus = "✅ Success"
                                                } else {
                                                    tier2TestStatus = "❌ Failed: Model not loaded"
                                                }
                                            } catch {
                                                tier2TestStatus = "❌ Failed: \(error.localizedDescription)"
                                            }
                                        }
                                    }
                                    .buttonStyle(.link)
                                    .font(.caption)
                                    
                                    if let status = tier2TestStatus {
                                        Text(status).font(.caption).foregroundColor(status.starts(with: "✅") ? .green : .red)
                                    }
                                }
                            }
                        }
                    }
                    
                    Section(header: Text("Tier 3: Canary Probe").font(.headline)) {
                        Text("This model is used as a sacrificial canary to test untrusted payloads for malicious instructions.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            
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
                                            await downloader.downloadModel(name: config.promptGuardModel, assignResolvedNameTo: \.promptGuardModel)
                                        }
                                    }
                                    Text("This will download approx. \(downloader.approximateSize(for: config.promptGuardModel)) of weights to your disk.")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                
                                if let error = downloader.error {
                                    Text("Error: \(error)").foregroundColor(.red).font(.caption)
                                }
                            } else {
                                HStack {
                                    Text("✅ Model is downloaded and ready.")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                        
                                    Button("Test Model") {
                                        Task {
                                            do {
                                                let engineType = AuxiliaryEngineType(rawValue: config.promptGuardEngine) ?? .llamaCPP
                                                let auxConfig = AuxiliaryModelConfig(role: "promptGuard", engineType: engineType, modelPathOrName: config.promptGuardModel)
                                                let engine = try await AuxiliaryModelManager.shared.getEngine(for: "promptGuard", config: auxConfig)
                                                _ = try await engine.generate(prompt: "Hello", jsonSchema: nil)
                                                tier3TestStatus = "✅ Success"
                                            } catch {
                                                tier3TestStatus = "❌ Failed: \(error.localizedDescription)"
                                            }
                                        }
                                    }
                                    .buttonStyle(.link)
                                    .font(.caption)
                                    
                                    if let status = tier3TestStatus {
                                        Text(status).font(.caption).foregroundColor(status.starts(with: "✅") ? .green : .red)
                                    }
                                }
                            }
                        } else {
                            TextField("Model Name", text: $config.promptGuardModel)
                                .help("The model to use for the Tier 3 Canary evaluation")
                                
                            HStack {
                                Text("✅ Assuming model is ready via external daemon.")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                    
                                Button("Test Model") {
                                    Task {
                                        do {
                                            let engineType = AuxiliaryEngineType(rawValue: config.promptGuardEngine) ?? .llamaCPP
                                            let auxConfig = AuxiliaryModelConfig(role: "promptGuard", engineType: engineType, modelPathOrName: config.promptGuardModel)
                                            let engine = try await AuxiliaryModelManager.shared.getEngine(for: "promptGuard", config: auxConfig)
                                            _ = try await engine.generate(prompt: "Hello", jsonSchema: nil)
                                            tier3TestStatus = "✅ Success"
                                        } catch {
                                            tier3TestStatus = "❌ Failed: \(error.localizedDescription)"
                                        }
                                    }
                                }
                                .buttonStyle(.link)
                                .font(.caption)
                                
                                if let status = tier3TestStatus {
                                    Text(status).font(.caption).foregroundColor(status.starts(with: "✅") ? .green : .red)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.bottom)
            .formStyle(.grouped)
            .padding(20)
            .tabItem {
                Label("Security", systemImage: "lock.shield")
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
                    Toggle("Enable sandboxing", isOn: $config.enableSandboxing)
                        .onChange(of: config.enableSandboxing) { _, newValue in
                            if newValue {
                                if !SandboxingManager.shared.isContainerInstalled {
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
                                } else {
                                    // Container runtime is installed; ensure background services and kernel image are ready
                                    isInstallingContainer = true
                                    installError = nil
                                    Task {
                                        let result = await SandboxingManager.shared.startContainerSystem()
                                        await MainActor.run {
                                            isInstallingContainer = false
                                            if !result.success {
                                                installError = result.message
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    
                    if config.enableSandboxing {
                        Picker("Main agent (default)", selection: $config.mainAgentSandboxDefault) {
                            Text("Host").tag(SandboxPref.host)
                            Text("Sandboxed").tag(SandboxPref.sandboxed)
                        }
                        .help("Where the main agent runs by default. Subagents are always sandboxed. Override per workspace via /sandbox, or per conversation via the sidebar right-click menu.")
                        TextField("Sandbox Image", text: $config.sandboxImage)
                            .help("The Docker/OCI image to use for sandboxed commands (e.g., ubuntu:latest)")
                        Stepper("Sandbox idle timeout: \(config.sandboxIdleTimeoutMinutes) min",
                                value: Binding(
                                    get: { config.sandboxIdleTimeoutMinutes },
                                    set: { config.sandboxIdleTimeoutMinutes = max(1, $0) }),
                                in: 1...240)
                            .help("How long a sandbox container can sit idle before being reclaimed (1–240 minutes).")
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

                Section(header: Text("Agent Limits").font(.headline)) {
                    Stepper("Max goal iterations: \(config.maxGoalIterations)",
                            value: Binding(get: { config.maxGoalIterations },
                                           set: { config.maxGoalIterations = max(1, $0) }), in: 1...500)
                        .help("Hard cap on autonomous goal-loop turns before the agent summarizes and stops.")
                    Stepper("Loop-detection threshold: \(config.loopDetectionThreshold)",
                            value: Binding(get: { config.loopDetectionThreshold },
                                           set: { config.loopDetectionThreshold = max(2, $0) }), in: 2...20)
                        .help("Stop early if the agent repeats the exact same tool call this many times in a row.")
                    Stepper("Vibecop timeout: \(config.vibecopTimeoutSeconds)s",
                            value: Binding(get: { config.vibecopTimeoutSeconds },
                                           set: { config.vibecopTimeoutSeconds = max(1, $0) }), in: 1...30)
                        .help("How long to wait for the Vibecop guard before falling back to a manual approval prompt.")
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .tabItem {
                Label("Advanced", systemImage: "lock.shield")
            }
            
            // MARK: - Updates Tab
            Form {
                Section(header: Text("Application Updates").font(.headline)) {
                    HStack {
                        Text("Installed Version:")
                        Spacer()
                        Text("v\(Constants.appVersion)")
                            .foregroundColor(.secondary)
                    }
                    
                    if let update = availableUpdate {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                                    .foregroundColor(.irisIndigo)
                                Text("New Version Available: \(update.tagName)")
                                    .font(.headline)
                            }
                            
                            if !update.body.isEmpty {
                                Text(update.body)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(4)
                            }
                            
                            Button("Download Update (\(update.tagName))") {
                                UpdateManager.shared.openReleasePage(url: update.htmlUrl)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    HStack {
                        Button(action: { checkForUpdates() }) {
                            if isCheckingForUpdates {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Check for Updates")
                            }
                        }
                        .disabled(isCheckingForUpdates)
                        
                        if let msg = updateCheckStatusMessage {
                            Spacer()
                            Text(msg)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(20)
            .tabItem {
                Label("Updates", systemImage: "arrow.triangle.2.circlepath")
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
    
    private func checkForUpdates() {
        isCheckingForUpdates = true
        updateCheckStatusMessage = "Checking for updates..."
        Task {
            let result = await UpdateManager.shared.checkForUpdates()
            await MainActor.run {
                self.isCheckingForUpdates = false
                switch result {
                case .updateAvailable(let release):
                    self.availableUpdate = release
                    self.updateCheckStatusMessage = "Update available: \(release.tagName)"
                case .upToDate:
                    self.availableUpdate = nil
                    self.updateCheckStatusMessage = "Iris is up to date (v\(Constants.appVersion))."
                case .error(let msg):
                    self.updateCheckStatusMessage = "Failed to check for updates: \(msg)"
                }
            }
        }
    }
}
