import Foundation

struct CloudAuxiliaryEngine: AuxiliaryInferenceEngine {
    func loadModel(config: AuxiliaryModelConfig) async throws {
        // Cloud models don't require explicit loading into memory.
    }
    
    func unloadModel() async {
        // No-op
    }
    
    func generate(prompt: String, jsonSchema: String?) async throws -> String {
        let client = LLMClient()
        
        let requestContent = Content(
            role: "user", 
            parts: [Part(text: prompt, functionCall: nil, functionResponse: nil, thought_signature: nil, thoughtSignature: nil)]
        )
        
        let request = GeminiRequest(contents: [requestContent], systemInstruction: nil, tools: nil)
        
        // We use the "easy" tier for Vibecop queries to prioritize speed and reduce cost.
        let response = try await client.generateContent(request: request, tier: .easy)
        
        guard let candidate = response.candidates?.first, 
              let content = candidate.content,
              let part = content.parts.first, 
              let text = part.text else {
            throw APIError(message: "No text returned from cloud provider for Vibecop.")
        }
        
        return text
    }
}
