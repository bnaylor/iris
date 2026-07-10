import Foundation
import SwiftUI
import KeyboardShortcuts

actor IrisEngine {
    let client = LLMClient()
    let executor = ToolExecutor.shared
    let manager = SkillManager.shared
    
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
        let activeId = await MainActor.run { localState?.selectedConversationId }
        guard let conversationId = activeId else { return }
        
        await MainActor.run {
            localState?.appendMessage(role: .system, content: message, to: conversationId)
            localState?.isThinking = true
        }
        await processInput(message, source: source, conversationId: conversationId)
        await MainActor.run { localState?.isThinking = false }
    }
    
    func start() async {
        await MCPManager.shared.startServers()
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
    
    func processInput(_ input: String, source: String, conversationId: UUID) async {
        let text = (source == "UI") ? input : "System Event [\(source)]: \(input)\nAnalyze this event. If it requires action based on your directives/skills, take it. Otherwise, briefly acknowledge it."
        
        let localState = state
        var history = await MainActor.run { localState?.conversations.first(where: { $0.id == conversationId })?.history ?? [] }
        let workspacePath = await MainActor.run { localState?.conversations.first(where: { $0.id == conversationId })?.workspacePath }
        
        history.append(Content(role: "user", parts: [Part(text: text, functionCall: nil, functionResponse: nil)]))
        await MainActor.run { localState?.updateHistory(for: conversationId, history: history) }
        
        var currentSystemPrompt = systemPrompt!
        if let wp = workspacePath {
            let agentsMdPath = (wp as NSString).expandingTildeInPath
            let fullPath = (agentsMdPath as NSString).appendingPathComponent("AGENTS.md")
            if let agentsMdContent = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                if let textPart = currentSystemPrompt.parts.first?.text {
                    currentSystemPrompt.parts[0].text = textPart + "\n\n# Project Workspace Rules (AGENTS.md)\n" + agentsMdContent
                }
            }
        }
        
        var toolsList = await executor.getTools()
        // Add set_workspace tool dynamically
        toolsList.append(FunctionDeclaration(
            name: "set_workspace",
            description: "Bind this conversation to a local project workspace. Do this when the user says they are working in a specific project or directory.",
            parameters: Schema(
                type: "OBJECT",
                properties: [
                    "path": Schema(type: "STRING", description: "Absolute or tilde-expanded path to the workspace directory")
                ],
                required: ["path"]
            )
        ))
        
        var request = GeminiRequest(contents: history, systemInstruction: currentSystemPrompt, tools: [Tool(functionDeclarations: toolsList)])
        
        var turnFinished = false
        while !turnFinished {
            do {
                let response = try await client.generateContent(request: request)
                guard let candidate = response.candidates?.first, let responseContent = candidate.content else {
                    await pushToUI(role: .agent, text: "Error: No candidate returned.", conversationId: conversationId)
                    break
                }
                
                let modelContent = Content(role: "model", parts: responseContent.parts)
                history.append(modelContent)
                await MainActor.run { localState?.updateHistory(for: conversationId, history: history) }
                
                if let part = responseContent.parts.first {
                    if let functionCall = part.functionCall {
                        await pushToUI(role: .system, text: "Running tool: \(functionCall.name)...", conversationId: conversationId)
                        
                        var result = ""
                        if functionCall.name == "set_workspace", let path = functionCall.args["path"] {
                            await MainActor.run { localState?.setWorkspace(for: conversationId, path: path) }
                            result = "Workspace successfully set to \(path). You will now load AGENTS.md from this directory."
                        } else {
                            result = await executor.execute(name: functionCall.name, args: functionCall.args, cwd: workspacePath)
                        }
                        
                        let functionResponse = Content(
                            role: "function", 
                            parts: [Part(text: nil, functionCall: nil, functionResponse: FunctionResponse(name: functionCall.name, response: ["result": result]))]
                        )
                        history.append(functionResponse)
                        await MainActor.run { localState?.updateHistory(for: conversationId, history: history) }
                        request.contents = history
                    } else if let responseText = part.text {
                        await pushToUI(role: .agent, text: responseText, conversationId: conversationId)
                        turnFinished = true
                    } else {
                        turnFinished = true
                    }
                } else {
                    turnFinished = true
                }
            } catch {
                await pushToUI(role: .agent, text: "Error calling LLM: \(error.localizedDescription)", conversationId: conversationId)
                turnFinished = true
            }
        }
    }
    
    private func pushToUI(role: ChatRole, text: String, conversationId: UUID) async {
        let localState = state
        await MainActor.run {
            localState?.appendMessage(role: role, content: text, to: conversationId)
        }
    }
}

@main
struct IrisApp: App {
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        KeyboardShortcuts.onKeyUp(for: .toggleIris) {
            if let window = NSApp.windows.first(where: { $0.title == "Iris" }) {
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
        WindowGroup("Iris") {
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
