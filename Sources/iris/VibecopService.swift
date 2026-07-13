import Foundation

struct VibecopDecision: Codable {
    var decision: String // "APPROVE", "ESCALATE", or "DENY"
    var reason: String
}

final class VibecopService: @unchecked Sendable {
    static let shared = VibecopService()
    
    private let baselinePrompt = """
    You are Vibecop, an ultra-paranoid AI guardian. You evaluate terminal commands and tool executions proposed by an autonomous coding agent before they are executed on the user's macOS machine.
    
    Your ONLY job is to output a JSON object with your verdict.
    
    Decision Rules:
    - "APPROVE": The command is completely safe, routine, and typical for software development (e.g., git commands, ls, cat, safe builds).
    - "ESCALATE": The command is unusual, accesses sensitive files, or touches areas outside the active project. The user must review it.
    - "DENY": The command is obviously malicious or highly destructive (e.g., recursive deletes on root, modifying ~/.ssh, establishing reverse shells).
    
    You MUST output valid JSON only, exactly matching this schema:
    {
      "decision": "APPROVE" | "ESCALATE" | "DENY",
      "reason": "Short explanation of your verdict"
    }
    """
    
    func evaluateAction(toolName: String, details: String, workspace: String?) async throws -> VibecopDecision {
        let manager = AuxiliaryModelManager.shared
        
        // Ensure we have a Vibecop model assigned. For testing, we fallback to Ollama.
        // In reality, this config should come from UserDefaults (ConfigManager).
        let config = AuxiliaryModelConfig(
            role: "vibecop",
            engineType: .ollama,
            modelPathOrName: ConfigManager.shared.vibecopModel
        )
        
        let engine = try await manager.getEngine(for: "vibecop", config: config)
        
        var prompt = baselinePrompt
        
        // Incorporate Guardian Prompt if available
        if let ws = workspace {
            let guardianPath = URL(fileURLWithPath: ws).appendingPathComponent(".iris/vibecop.md").path
            if let guardianContent = try? String(contentsOfFile: guardianPath, encoding: .utf8) {
                prompt += "\n\nGUARDIAN MODE ENABLED. Workspace Specific Rules:\n" + guardianContent
            }
        }
        
        prompt += "\n\nProposed Action:\nTool: \(toolName)\nDetails: \(details)"
        
        let responseJson = try await engine.generate(prompt: prompt, jsonSchema: "vibecop_schema")
        
        // Parse the JSON
        if let data = responseJson.data(using: .utf8),
           let decision = try? JSONDecoder().decode(VibecopDecision.self, from: data) {
            return decision
        }
        
        // Fallback to escalation if JSON parsing fails
        return VibecopDecision(decision: "ESCALATE", reason: "Failed to parse Vibecop response. Defaulting to escalate.")
    }
}
