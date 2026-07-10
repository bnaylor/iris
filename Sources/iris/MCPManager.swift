import Foundation
import System
import MCP

struct MCPServerConfig: Codable {
    let command: String
    let args: [String]
    let env: [String: String]?
}

actor MCPManager {
    static let shared = MCPManager()
    
    struct ActiveServer {
        let client: Client
        let transport: StdioTransport
        let process: Process
        var availableTools: [MCP.Tool] = []
    }
    
    private var servers: [String: ActiveServer] = [:]
    private var configPath: String {
        return ("~/.config/iris/mcp_servers.json" as NSString).expandingTildeInPath
    }
    
    init() {}
    
    func startServers() async {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let configs = try? JSONDecoder().decode([String: MCPServerConfig].self, from: data) else {
            return
        }
        
        for (name, config) in configs {
            do {
                try await startServer(name: name, config: config)
            } catch {
                print("Failed to start MCP server \(name): \(error)")
            }
        }
    }
    
    private func startServer(name: String, config: MCPServerConfig) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: (config.command as NSString).expandingTildeInPath)
        process.arguments = config.args
        if let env = config.env {
            var fullEnv = ProcessInfo.processInfo.environment
            for (k, v) in env { fullEnv[k] = v }
            process.environment = fullEnv
        }
        
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        
        try process.run()
        
        let inputFD = FileDescriptor(rawValue: stdoutPipe.fileHandleForReading.fileDescriptor)
        let outputFD = FileDescriptor(rawValue: stdinPipe.fileHandleForWriting.fileDescriptor)
        
        let transport = StdioTransport(input: inputFD, output: outputFD)
        let client = Client(name: "Iris", version: "1.0.0")
        
        try await client.connect(transport: transport)
        let toolsResult = try await client.listTools()
        
        servers[name] = ActiveServer(
            client: client,
            transport: transport,
            process: process,
            availableTools: toolsResult.tools
        )
        print("MCP Server \(name) connected. Found \(toolsResult.tools.count) tools.")
    }
    
    func getGeminiTools() -> [FunctionDeclaration] {
        var declarations: [FunctionDeclaration] = []
        for (serverName, server) in servers {
            for tool in server.availableTools {
                // Prepend server name to tool name to avoid collisions
                let uniqueName = "\(serverName)___\(tool.name)"
                
                // Convert MCP JSONSchema to Gemini Schema
                // Since they are very similar JSON objects, we just need to adapt the structure.
                // We will rely on simple JSON parsing for now, or use our Schema type.
                var properties: [String: Schema] = [:]
                var required: [String] = []
                
                if case .object(let schemaDict) = tool.inputSchema,
                   let propsValue = schemaDict["properties"],
                   case .object(let props) = propsValue {
                    for (k, v) in props {
                        if case .object(let vDict) = v,
                           let typeVal = vDict["type"],
                           case .string(let typeStr) = typeVal {
                            var desc: String? = nil
                            if let descVal = vDict["description"], case .string(let d) = descVal {
                                desc = d
                            }
                            properties[k] = Schema(
                                type: typeStr.uppercased(),
                                properties: nil,
                                required: nil,
                                description: desc
                            )
                        }
                    }
                    if let reqValue = schemaDict["required"], case .array(let reqArray) = reqValue {
                        for reqVal in reqArray {
                            if case .string(let s) = reqVal {
                                required.append(s)
                            }
                        }
                    }
                }
                
                let geminiSchema = Schema(
                    type: "OBJECT",
                    properties: properties.isEmpty ? nil : properties,
                    required: required.isEmpty ? nil : required,
                    description: nil
                )
                
                declarations.append(FunctionDeclaration(
                    name: uniqueName,
                    description: tool.description ?? "MCP Tool from \(serverName)",
                    parameters: geminiSchema
                ))
            }
        }
        return declarations
    }
    
    func callTool(name: String, args: [String: String]) async -> String {
        let parts = name.components(separatedBy: "___")
        guard parts.count == 2, let serverName = parts.first, let toolName = parts.last else {
            return "Error: Invalid MCP tool name format."
        }
        
        guard let server = servers[serverName] else {
            return "Error: MCP Server \(serverName) not found."
        }
        
        var mcpArgs: [String: Value] = [:]
        for (k, v) in args {
            mcpArgs[k] = .string(v) // Naive mapping
        }
        
        do {
            let result = try await server.client.callTool(name: toolName, arguments: mcpArgs)
            if let firstContent = result.content.first {
                switch firstContent {
                case .text(let text, _, _):
                    return text
                default:
                    return "Tool executed successfully but returned non-text content."
                }
            }
            return "Tool executed successfully with no content returned."
        } catch {
            return "Error calling MCP tool: \(error)"
        }
    }
}
