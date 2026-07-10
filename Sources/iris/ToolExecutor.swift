import Foundation

struct ToolExecutor {
    static let shared = ToolExecutor()
    
    func getTools() async -> [FunctionDeclaration] {
        var tools = [
            FunctionDeclaration(
            name: "run_command",
            description: "Executes a shell command. Use this for standard operations.",
            parameters: Schema(
                type: "OBJECT",
                properties: [
                    "command": Schema(type: "STRING", description: "The command to run in bash/zsh")
                ],
                required: ["command"]
            )
        ),
        FunctionDeclaration(
            name: "read_file",
            description: "Reads the contents of a file.",
            parameters: Schema(
                type: "OBJECT",
                properties: [
                    "path": Schema(type: "STRING", description: "Absolute or tilde-expanded path to the file")
                ],
                required: ["path"]
            )
        ),
        FunctionDeclaration(
            name: "write_file",
            description: "Writes content to a file, overwriting existing content.",
            parameters: Schema(
                type: "OBJECT",
                properties: [
                    "path": Schema(type: "STRING", description: "Absolute or tilde-expanded path to the file"),
                    "content": Schema(type: "STRING", description: "The content to write")
                ],
                required: ["path", "content"]
            )
        ),
        FunctionDeclaration(
            name: "register_directory_watcher",
            description: "Watch a directory for file changes and execute instructions when files are modified. Use this when the user asks you to monitor a folder.",
            parameters: Schema(
                type: "OBJECT",
                properties: [
                    "path": Schema(type: "STRING", description: "Absolute or tilde-expanded path to watch"),
                    "instructions": Schema(type: "STRING", description: "The instructions to execute when a file is modified")
                ],
                required: ["path", "instructions"]
            )
        )
        ]
        
        let tasksTools = await GoogleTasksManager.shared.getTools()
        tools.append(contentsOf: tasksTools)
        
        let workspaceTools = await GoogleWorkspaceManager.shared.getTools()
        tools.append(contentsOf: workspaceTools)
        
        let mcpTools = await MCPManager.shared.getGeminiTools()
        tools.append(contentsOf: mcpTools)
        return tools
    }
    
    func execute(name: String, args: [String: String], cwd: String? = nil) async -> String {
        switch name {
        case "run_command":
            guard let command = args["command"] else { return "Error: Missing command" }
            return await runCommand(command, cwd: cwd)
        case "read_file":
            guard let path = args["path"] else { return "Error: Missing path" }
            return await readFile(path)
        case "write_file":
            guard let path = args["path"], let content = args["content"] else { return "Error: Missing path or content" }
            return await writeFile(path, content: content)
        case "register_directory_watcher":
            guard let path = args["path"], let instructions = args["instructions"] else { return "Error: Missing path or instructions" }
            await WatcherManager.shared.addRule(path: path, instructions: instructions)
            return "Successfully registered watcher for \(path). You will be notified automatically when files change."
        case let n where n.hasPrefix("google_tasks_"):
            return await GoogleTasksManager.shared.execute(name: name, args: args)
        case let n where n.hasPrefix("google_calendar_") || n.hasPrefix("google_docs_") || n.hasPrefix("google_drive_") || n.hasPrefix("google_sheets_") || n.hasPrefix("gmail_"):
            return await GoogleWorkspaceManager.shared.execute(name: name, args: args)
        default:
            if name.contains("___") {
                return await MCPManager.shared.callTool(name: name, args: args)
            }
            return "Error: Unknown tool \(name)"
        }
    }
    
    private func runCommand(_ command: String, cwd: String?) async -> String {
        return await withCheckedContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            if ConfigManager.shared.enableSandboxing && SandboxingManager.shared.isContainerInstalled {
                // If container exists but not at /usr/local/bin, which might find it, but we assume default for now
                process.executableURL = URL(fileURLWithPath: "/usr/local/bin/container")
                var containerArgs = ["run", "--rm", ConfigManager.shared.sandboxImage, "bash", "-c", command]
                if let cwd = cwd {
                    let expandedPath = (cwd as NSString).expandingTildeInPath
                    containerArgs.insert(contentsOf: ["-v", "\(expandedPath):\(expandedPath)", "--workdir", expandedPath], at: 2)
                }
                process.arguments = containerArgs
            } else {
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-c", command]
                if let cwd = cwd {
                    process.currentDirectoryURL = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath)
                }
            }
            
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            process.terminationHandler = { proc in
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                
                var result = ""
                if let outputStr = String(data: outputData, encoding: .utf8), !outputStr.isEmpty {
                    result += outputStr
                }
                if let errorStr = String(data: errorData, encoding: .utf8), !errorStr.isEmpty {
                    result += "\nStderr: " + errorStr
                }
                continuation.resume(returning: result.isEmpty ? "Success" : result)
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(returning: "Error executing command: \(error.localizedDescription)")
            }
        }
    }
    
    private func readFile(_ path: String) async -> String {
        let expandedPath = (path as NSString).expandingTildeInPath
        return await Task.detached {
            do {
                return try String(contentsOfFile: expandedPath, encoding: .utf8)
            } catch {
                return "Error reading file: \(error.localizedDescription)"
            }
        }.value
    }
    
    private func writeFile(_ path: String, content: String) async -> String {
        let expandedPath = (path as NSString).expandingTildeInPath
        return await Task.detached {
            do {
                try content.write(toFile: expandedPath, atomically: true, encoding: .utf8)
                return "Successfully wrote to \(expandedPath)"
            } catch {
                return "Error writing file: \(error.localizedDescription)"
            }
        }.value
    }
}
