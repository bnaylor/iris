import Foundation

struct HookConfig: Codable {
    let hooks: [String: [HookEvent]]
}

struct HookEvent: Codable {
    let matcher: String
    let hooks: [HookDefinition]
}

struct HookDefinition: Codable {
    let name: String?
    let type: String
    let command: String
    let timeout: Int?
    let description: String?
}

enum HookDecision {
    case proceed(modifiedData: Data?)
    case block(reason: String)
    case warning(message: String)
}

struct HookManager {
    static let shared = HookManager()
    
    var configPathOverride: String?
    
    private var configPath: String {
        configPathOverride ?? ("~/.iris/settings.json" as NSString).expandingTildeInPath
    }
    
    private var config: HookConfig? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)) else { return nil }
        return try? JSONDecoder().decode(HookConfig.self, from: data)
    }
    
    func fireBeforeTool(toolName: String, args: [String: JSONValue]) async -> HookDecision {
        return await fireEvent(eventName: "BeforeTool", targetMatcher: toolName, payload: try? JSONEncoder().encode(args))
    }
    
    func fireAfterTool(toolName: String, result: String) async -> HookDecision {
        let payload = ["result": result]
        return await fireEvent(eventName: "AfterTool", targetMatcher: toolName, payload: try? JSONSerialization.data(withJSONObject: payload))
    }
    
    func fireBeforeAgent(input: String) async -> HookDecision {
        let payload = ["input": input]
        return await fireEvent(eventName: "BeforeAgent", targetMatcher: "BeforeAgent", payload: try? JSONSerialization.data(withJSONObject: payload))
    }
    
    func fireBeforeModel(request: GeminiRequest) async -> HookDecision {
        return await fireEvent(eventName: "BeforeModel", targetMatcher: "BeforeModel", payload: try? JSONEncoder().encode(request))
    }
    
    func fireAfterModel(response: GeminiResponse) async -> HookDecision {
        return await fireEvent(eventName: "AfterModel", targetMatcher: "AfterModel", payload: try? JSONEncoder().encode(response))
    }
    
    func fireBeforeToolSelection(tools: [FunctionDeclaration]) async -> HookDecision {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        return await fireEvent(eventName: "BeforeToolSelection", targetMatcher: "BeforeToolSelection", payload: try? encoder.encode(tools))
    }
    
    func firePreCompress(history: [Content]) async -> HookDecision {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        return await fireEvent(eventName: "PreCompress", targetMatcher: "PreCompress", payload: try? encoder.encode(history))
    }
    
    func fireNotification(title: String, body: String) async {
        let payload = ["title": title, "body": body]
        _ = await fireEvent(eventName: "Notification", targetMatcher: "Notification", payload: try? JSONSerialization.data(withJSONObject: payload))
    }
    
    func fireSessionStart(conversationId: UUID) async -> HookDecision {
        let payload = ["conversationId": conversationId.uuidString]
        return await fireEvent(eventName: "SessionStart", targetMatcher: "SessionStart", payload: try? JSONSerialization.data(withJSONObject: payload))
    }
    
    func fireAfterAgent(output: String) async -> HookDecision {
        let payload = ["output": output]
        return await fireEvent(eventName: "AfterAgent", targetMatcher: "AfterAgent", payload: try? JSONSerialization.data(withJSONObject: payload))
    }
    
    private func fireEvent(eventName: String, targetMatcher: String, payload: Data?) async -> HookDecision {
        guard let config = config, let eventHooks = config.hooks[eventName] else {
            return .proceed(modifiedData: nil) // No hooks registered
        }
        
        var currentData = payload
        
        for eventConfig in eventHooks {
            // Check regex matcher
            guard let regex = try? NSRegularExpression(pattern: eventConfig.matcher),
                  regex.firstMatch(in: targetMatcher, range: NSRange(targetMatcher.startIndex..., in: targetMatcher)) != nil else {
                continue
            }
            
            for hook in eventConfig.hooks {
                if hook.type != "command" { continue }
                
                let decision = await executeCommandHook(hook: hook, payload: currentData)
                switch decision {
                case .block:
                    return decision // Immediate hard block
                case .proceed(let modifiedData):
                    if let new = modifiedData {
                        currentData = new // Pass modified data to next hook
                    }
                case .warning:
                    // Treat as proceed, could log warning
                    break
                }
            }
        }
        
        return .proceed(modifiedData: currentData)
    }
    
    private func executeCommandHook(hook: HookDefinition, payload: Data?) async -> HookDecision {
        return await withCheckedContinuation { continuation in
            let process = Process()
            let inputPipe = Pipe()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            
            if ConfigManager.shared.enableSandboxing {
                guard SandboxingManager.shared.isContainerInstalled else {
                    continuation.resume(returning: .block(reason: "Sandboxing enabled but container missing for hook execution."))
                    return
                }
                process.executableURL = URL(fileURLWithPath: "/usr/local/bin/container")
                process.arguments = ["run", "--rm", ConfigManager.shared.sandboxImage, "bash", "-c", hook.command]
            } else {
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", hook.command]
            }
            
            process.standardInput = inputPipe
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            var env = ProcessInfo.processInfo.environment
            env.removeValue(forKey: "ANTHROPIC_API_KEY")
            env.removeValue(forKey: "OPENAI_API_KEY")
            env.removeValue(forKey: "GEMINI_API_KEY")
            env["GEMINI_CWD"] = FileManager.default.currentDirectoryPath
            process.environment = env
            
            if let data = payload {
                inputPipe.fileHandleForWriting.write(data)
                try? inputPipe.fileHandleForWriting.close()
            }
            
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(hook.timeout ?? 60) * 1_000_000_000)
                if process.isRunning {
                    process.terminate()
                }
            }
            
            process.terminationHandler = { proc in
                timeoutTask.cancel()
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                if proc.terminationStatus == 2 {
                    let reason = String(data: errorData, encoding: .utf8) ?? "Unknown hook error"
                    continuation.resume(returning: .block(reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)))
                } else if proc.terminationStatus == 0 {
                    // Try parsing output as JSON to enforce the rule
                    if outputData.isEmpty {
                        continuation.resume(returning: .proceed(modifiedData: nil))
                    } else if (try? JSONSerialization.jsonObject(with: outputData)) != nil {
                        continuation.resume(returning: .proceed(modifiedData: outputData))
                    } else {
                        // Pollution = Warning/Failure, treated as proceed for now
                        continuation.resume(returning: .warning(message: "Hook output was not valid JSON"))
                    }
                } else {
                    continuation.resume(returning: .warning(message: "Hook exited with status \(proc.terminationStatus)"))
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(returning: .warning(message: "Failed to spawn hook: \(error.localizedDescription)"))
            }
        }
    }
}
