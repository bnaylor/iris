import Foundation
import SwiftUI

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
    
    func startWatchers(paths: [String]) async {
        let watcher = FileWatcher()
        let fileEvents = watcher.watch(paths: paths)
        
        for await eventPaths in fileEvents {
            let eventString = "File(s) modified: \(eventPaths.joined(separator: ", "))"
            let localState = state
            await MainActor.run {
                localState?.appendMessage(role: .system, content: eventString)
                localState?.isThinking = true
            }
            await processInput(eventString, source: "FileWatcher")
            await MainActor.run { localState?.isThinking = false }
        }
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
