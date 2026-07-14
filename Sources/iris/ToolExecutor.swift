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
        ),
        FunctionDeclaration(
            name: "search_web",
            description: "Search the web using DuckDuckGo. Returns a JSON array of results with title, url, and snippet.",
            parameters: Schema(
                type: "OBJECT",
                properties: [
                    "query": Schema(type: "STRING", description: "The search query")
                ],
                required: ["query"]
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
        case "search_web":
            guard let query = args["query"] else { return "Error: Missing query" }
            return await searchWeb(query: query)
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
            if ConfigManager.shared.enableSandboxing {
                guard SandboxingManager.shared.isContainerInstalled else {
                    continuation.resume(returning: "Error: Sandboxing is enabled but the container runtime is not installed. Run the /sandbox command to install it, or disable sandboxing in settings.")
                    return
                }
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
    
    private func searchWeb(query: String) async -> String {
        let script = """
import urllib.request
import urllib.parse
from html.parser import HTMLParser
import sys
import json

class DDGParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.results = []
        self.current_title = ""
        self.current_url = ""
        self.current_snippet = ""
        self.capture_type = None

    def handle_starttag(self, tag, attrs):
        attr_dict = dict(attrs)
        if tag == "a" and "result-link" in attr_dict.get("class", ""):
            self.current_url = attr_dict.get("href", "")
            self.capture_type = "title"
        if tag == "td" and "result-snippet" in attr_dict.get("class", ""):
            self.capture_type = "snippet"

    def handle_data(self, data):
        if self.capture_type == "title":
            self.current_title += data
        elif self.capture_type == "snippet":
            self.current_snippet += data

    def handle_endtag(self, tag):
        if tag == "a" and self.capture_type == "title":
            self.capture_type = None
        elif tag == "td" and self.capture_type == "snippet":
            self.capture_type = None
            if self.current_title and self.current_url and self.current_snippet:
                self.results.append({
                    "title": self.current_title.strip(),
                    "url": self.current_url.strip(),
                    "snippet": self.current_snippet.strip()
                })
            self.current_title = ""
            self.current_url = ""
            self.current_snippet = ""

query = sys.argv[1]
data = urllib.parse.urlencode({"q": query}).encode("utf-8")
req = urllib.request.Request("https://lite.duckduckgo.com/lite/", data=data, headers={"User-Agent": "Mozilla/5.0"})
try:
    html = urllib.request.urlopen(req).read().decode("utf-8")
    parser = DDGParser()
    parser.feed(html)
    print(json.dumps(parser.results[:10], indent=2))
except Exception as e:
    print(json.dumps({"error": str(e)}))
"""
        let home = FileManager.default.homeDirectoryForCurrentUser
        let irisDir = home.appendingPathComponent(".iris")
        try? FileManager.default.createDirectory(at: irisDir, withIntermediateDirectories: true)
        let scriptURL = irisDir.appendingPathComponent("search_web.py")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", scriptURL.path, query]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? "Error decoding output"
        } catch {
            return "Error executing search script: \(error)"
        }
    }
}
