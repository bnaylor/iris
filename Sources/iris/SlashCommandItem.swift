import Foundation

struct SlashCommandItem: Identifiable, Sendable, Equatable {
    let id: String
    let command: String
    let usage: String
    let description: String
    
    static let allCommands: [SlashCommandItem] = [
        SlashCommandItem(id: "goal", command: "/goal", usage: "/goal <description>", description: "Start an autonomous goal-driven loop"),
        SlashCommandItem(id: "stop", command: "/stop", usage: "/stop", description: "Cancel active goal mode or subagent tasks"),
        SlashCommandItem(id: "skills", command: "/skills", usage: "/skills", description: "List all registered skills and memory tools"),
        SlashCommandItem(id: "reflect", command: "/reflect", usage: "/reflect", description: "Trigger manual memory reflection and grooming"),
        SlashCommandItem(id: "vibecop", command: "/vibecop init", usage: "/vibecop init", description: "Initialize Vibecop Guardian rules for the workspace"),
        SlashCommandItem(id: "rename", command: "/rename", usage: "/rename", description: "Automatically rename current conversation"),
        SlashCommandItem(id: "update", command: "/update", usage: "/update", description: "Check for GitHub release updates"),
        SlashCommandItem(id: "sandbox", command: "/sandbox", usage: "/sandbox", description: "Check or configure subagent VM container runtime")
    ]
    
    /// Returns matching slash commands for `input`.
    static func matches(for input: String) -> [SlashCommandItem] {
        guard let slashIndex = input.firstIndex(of: "/"), input[..<slashIndex].allSatisfy(\.isWhitespace) else {
            return []
        }
        let commandPart = String(input[slashIndex...])
        guard !commandPart.contains(" ") else { return [] }
        if commandPart == "/" {
            return allCommands
        }
        let query = commandPart.lowercased()
        return allCommands.filter { $0.command.lowercased().hasPrefix(query) }
    }
}
