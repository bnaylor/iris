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
    
    func handleSystemEvent(_ message: String, source: String, conversationId: UUID? = nil) async {
        let localState = state
        let targetId = await MainActor.run { conversationId ?? localState?.selectedConversationId }
        guard let activeId = targetId else { return }
        
        await MainActor.run {
            localState?.appendMessage(role: .system, content: message, to: activeId)
            localState?.isThinking = true
        }
        await processInput(message, source: source, conversationId: activeId)
        await MainActor.run { localState?.isThinking = false }
    }
    
    func start() async {
        ScheduleManager.shared.onJobFired = { [weak self] prompt, convId in
            await self?.handleSystemEvent("Scheduled Job Triggered: \(prompt)", source: "Scheduler", conversationId: convId)
        }
        ScheduleManager.shared.start()
        
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
        
        toolsList.append(FunctionDeclaration(
            name: "schedule_job",
            description: "Schedule a recurring cron-like job or interval timer. The job will persist across app restarts and catch up if the computer wakes from sleep. Provide a clear prompt describing what Iris should do when it fires. You MUST provide EITHER intervalSeconds OR one or more cron fields (minute, hour, day, month, weekday), but not both.",
            parameters: Schema(
                type: "OBJECT",
                properties: [
                    "prompt": Schema(type: "STRING", description: "What Iris should do when the job fires"),
                    "minute": Schema(type: "INTEGER", description: "Cron minute (0-59)"),
                    "hour": Schema(type: "INTEGER", description: "Cron hour (0-23)"),
                    "day": Schema(type: "INTEGER", description: "Cron day of month (1-31)"),
                    "month": Schema(type: "INTEGER", description: "Cron month (1-12)"),
                    "weekday": Schema(type: "INTEGER", description: "Cron weekday (1=Sunday, 2=Monday, ..., 7=Saturday)"),
                    "intervalSeconds": Schema(type: "INTEGER", description: "Simple recurring interval in seconds (e.g. 3600 for every hour)")
                ],
                required: ["prompt"]
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
                        if functionCall.name == "set_workspace", let path = functionCall.args["path"] as? String {
                            await MainActor.run { localState?.setWorkspace(for: conversationId, path: path) }
                            result = "Workspace successfully set to \(path). You will now load AGENTS.md from this directory."
                        } else if functionCall.name == "schedule_job", let prompt = functionCall.args["prompt"] as? String {
                            let minute = (functionCall.args["minute"] as? NSNumber)?.intValue ?? Int("\(functionCall.args["minute"] ?? "")")
                            let hour = (functionCall.args["hour"] as? NSNumber)?.intValue ?? Int("\(functionCall.args["hour"] ?? "")")
                            let day = (functionCall.args["day"] as? NSNumber)?.intValue ?? Int("\(functionCall.args["day"] ?? "")")
                            let month = (functionCall.args["month"] as? NSNumber)?.intValue ?? Int("\(functionCall.args["month"] ?? "")")
                            let weekday = (functionCall.args["weekday"] as? NSNumber)?.intValue ?? Int("\(functionCall.args["weekday"] ?? "")")
                            let intervalSeconds = (functionCall.args["intervalSeconds"] as? NSNumber)?.intValue ?? Int("\(functionCall.args["intervalSeconds"] ?? "")")
                            
                            ScheduleManager.shared.schedule(
                                conversationId: conversationId,
                                prompt: prompt,
                                minute: minute,
                                hour: hour,
                                day: day,
                                month: month,
                                weekday: weekday,
                                intervalSeconds: intervalSeconds
                            )
                            result = "Job scheduled successfully. It will fire in the background."
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
        
        if let imagePath = Bundle.module.path(forResource: "iris-icon", ofType: "png"),
           let image = NSImage(contentsOfFile: imagePath) {
            NSApplication.shared.applicationIconImage = image
        }
        
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
