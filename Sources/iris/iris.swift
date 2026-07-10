import Foundation
import SwiftUI
import KeyboardShortcuts

actor IrisEngine {
    let client = LLMClient()
    let executor = ToolExecutor.shared
    let manager = SkillManager.shared
    
    var history: [Content] = []
    var systemPrompt: Content!
    
    // We need to keep a weak reference to the state or pass it in. 
    // Since AppState owns IrisEngine, we can pass it when we start or process.
    private weak var state: AppState?
    
    init(state: AppState) {
        self.state = state
        let soul = manager.loadSOUL()
        let skills = manager.discoverSkills()
        systemPrompt = Content(role: "system", parts: [Part(text: "\(soul)\n\n\(skills)", functionCall: nil, functionResponse: nil)])
    }
    
    func handleSystemEvent(_ message: String, source: String) async {
        let localState = state
        await MainActor.run {
            localState?.appendMessage(role: .system, content: message)
            localState?.isThinking = true
        }
        await processInput(message, source: source)
        await MainActor.run { localState?.isThinking = false }
    }
    
    func start() async {
        await WatcherManager.shared.setCallback { [weak self] message, source in
            guard let self = self else { return }
            await self.handleSystemEvent(message, source: source)
        }
        
        await WatcherManager.shared.startAll()
        
        // Ensure the core skills folder is always watched dynamically
        await WatcherManager.shared.addRule(
            path: "~/.config/iris/skills",
            instructions: "The user has modified their skills directory. Reload your skills and acknowledge the change."
        )
    }
    
    func processInput(_ input: String, source: String) async {
        let text = (source == "UI") ? input : "System Event [\(source)]: \(input)\nAnalyze this event. If it requires action based on your directives/skills, take it. Otherwise, briefly acknowledge it."
        history.append(Content(role: "user", parts: [Part(text: text, functionCall: nil, functionResponse: nil)]))
        
        var request = GeminiRequest(contents: history, systemInstruction: systemPrompt, tools: [Tool(functionDeclarations: executor.nativeTools)])
        
        var turnFinished = false
        while !turnFinished {
            do {
                let response = try await client.generateContent(request: request)
                guard let candidate = response.candidates?.first, let responseContent = candidate.content else {
                    await pushToUI(role: .agent, text: "Error: No candidate returned.")
                    break
                }
                
                let modelContent = Content(role: "model", parts: responseContent.parts)
                history.append(modelContent)
                
                if let part = responseContent.parts.first {
                    if let functionCall = part.functionCall {
                        await pushToUI(role: .system, text: "Running tool: \(functionCall.name)...")
                        
                        let result = await executor.execute(name: functionCall.name, args: functionCall.args)
                        
                        let functionResponse = Content(
                            role: "function", 
                            parts: [Part(text: nil, functionCall: nil, functionResponse: FunctionResponse(name: functionCall.name, response: ["result": result]))]
                        )
                        history.append(functionResponse)
                        request.contents = history
                    } else if let responseText = part.text {
                        await pushToUI(role: .agent, text: responseText)
                        turnFinished = true
                    } else {
                        turnFinished = true
                    }
                } else {
                    turnFinished = true
                }
            } catch {
                await pushToUI(role: .agent, text: "Error calling LLM: \(error.localizedDescription)")
                turnFinished = true
            }
        }
    }
    
    private func pushToUI(role: ChatRole, text: String) async {
        let localState = state
        await MainActor.run {
            localState?.appendMessage(role: role, content: text)
        }
    }
}

@main
struct IrisApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        KeyboardShortcuts.onKeyUp(for: .toggleIris) {
            if let window = NSApp.windows.first(where: { $0.title == "Iris Chat" }) {
                if window.isVisible && NSApp.isActive {
                    window.orderOut(nil)
                } else {
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                }
            } else {
                // If it's closed but a SwiftUI window still exists (sometimes hidden)
                if let window = NSApp.windows.first(where: { $0.className.contains("SwiftUI") }) {
                    NSApp.activate(ignoringOtherApps: true)
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
    }
    
    var body: some Scene {
        WindowGroup("Iris Chat") {
            ChatView()
        }
        
        // This is a minimal MenuBarExtra, we can expand it later.
        MenuBarExtra("Iris", systemImage: "sparkles") {
            Button("Show Chat") {
                // If the window is closed, this doesn't automatically reopen it in SwiftUI 
                // without URL routing or openWindow. But it serves as a placeholder.
                // In macOS 13+, we'd use openWindow(id:)
            }
            Divider()
            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        
        Settings {
            SettingsView()
        }
    }
}
