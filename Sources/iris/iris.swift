import Foundation

actor IrisEngine {
    let client = LLMClient()
    let executor = ToolExecutor.shared
    let manager = SkillManager.shared
    
    var history: [Content] = []
    var systemPrompt: Content!
    
    init() {
        let soul = manager.loadSOUL()
        let skills = manager.discoverSkills()
        systemPrompt = Content(role: "system", parts: [Part(text: "\(soul)\n\n\(skills)", functionCall: nil, functionResponse: nil)])
    }
    
    func processInput(_ input: String, source: String) async {
        let text = (source == "CLI") ? input : "System Event [\(source)]: \(input)\nAnalyze this event. If it requires action based on your directives/skills, take it. Otherwise, briefly acknowledge it."
        history.append(Content(role: "user", parts: [Part(text: text, functionCall: nil, functionResponse: nil)]))
        
        var request = GeminiRequest(contents: history, systemInstruction: systemPrompt, tools: [Tool(functionDeclarations: executor.nativeTools)])
        
        var turnFinished = false
        while !turnFinished {
            do {
                let response = try await client.generateContent(request: request)
                guard let candidate = response.candidates?.first, let responseContent = candidate.content else {
                    print("Error: No candidate returned.")
                    break
                }
                
                let modelContent = Content(role: "model", parts: responseContent.parts)
                history.append(modelContent)
                
                if let part = responseContent.parts.first {
                    if let functionCall = part.functionCall {
                        print("\nIris -> Running \(functionCall.name)...")
                        let result = await executor.execute(name: functionCall.name, args: functionCall.args)
                        print("Result -> \(result.prefix(200))\(result.count > 200 ? "..." : "")")
                        
                        let functionResponse = Content(
                            role: "function", 
                            parts: [Part(text: nil, functionCall: nil, functionResponse: FunctionResponse(name: functionCall.name, response: ["result": result]))]
                        )
                        history.append(functionResponse)
                        request.contents = history
                    } else if let text = part.text {
                        print("\nIris: \(text)")
                        print("\n> ", terminator: "")
                        fflush(stdout)
                        turnFinished = true
                    } else {
                        turnFinished = true
                    }
                } else {
                    turnFinished = true
                }
            } catch {
                print("\nError calling LLM: \(error)")
                turnFinished = true
            }
        }
    }
}

@main
struct iris {
    static func main() async {
        print("Starting Iris chassis...")
        let engine = IrisEngine()
        
        let watchPaths = [("~/.config/iris/skills" as NSString).expandingTildeInPath]
        
        let watcher = FileWatcher()
        let fileEvents = watcher.watch(paths: watchPaths)
        
        print("Watching directories: \(watchPaths)")
        print("Ready. Type 'exit' to quit.\n> ", terminator: "")
        fflush(stdout)
        
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await paths in fileEvents {
                    let eventString = "File(s) modified: \(paths.joined(separator: ", "))"
                    await engine.processInput(eventString, source: "FileWatcher")
                }
            }
            
            group.addTask {
                do {
                    for try await line in FileHandle.standardInput.bytes.lines {
                        if line.trimmingCharacters(in: .whitespacesAndNewlines) == "exit" {
                            exit(0)
                        }
                        await engine.processInput(line, source: "CLI")
                    }
                } catch {
                    print("Error reading CLI input: \(error)")
                }
            }
        }
    }
}
