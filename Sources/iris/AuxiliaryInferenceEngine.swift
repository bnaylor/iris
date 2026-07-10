import Foundation

enum AuxiliaryEngineType: String, Codable {
    case llamaCPP = "llama_cpp"
    case ollama = "ollama"
    case mlx = "mlx"
}

struct AuxiliaryModelConfig: Codable {
    var role: String
    var engineType: AuxiliaryEngineType
    var modelPathOrName: String
}

protocol AuxiliaryInferenceEngine: Sendable {
    /// Loads a model into memory
    func loadModel(config: AuxiliaryModelConfig) async throws
    
    /// Unloads the model from memory to free up resources
    func unloadModel() async
    
    /// Generates a response based on the prompt. Can optionally constrain the output via JSON schema or grammar.
    func generate(prompt: String, jsonSchema: String?) async throws -> String
}
