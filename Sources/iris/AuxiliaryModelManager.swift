import Foundation

final class AuxiliaryModelManager: @unchecked Sendable {
    static let shared = AuxiliaryModelManager()
    
    // In-memory engines mapped by role
    private var engines: [String: AuxiliaryInferenceEngine] = [:]
    
    private let modelsDir: String
    private let registryPath: String
    
    init() {
        let configDir = ("~/.iris" as NSString).expandingTildeInPath
        self.modelsDir = "\(configDir)/models"
        self.registryPath = "\(modelsDir)/models.json"
        
        if !FileManager.default.fileExists(atPath: modelsDir) {
            try? FileManager.default.createDirectory(atPath: modelsDir, withIntermediateDirectories: true)
        }
    }
    
    func getEngine(for role: String, config: AuxiliaryModelConfig) async throws -> AuxiliaryInferenceEngine {
        if let existing = engines[role] {
            return existing
        }
        
        let engine: AuxiliaryInferenceEngine
        switch config.engineType {
        case .llamaCPP:
            engine = try await LlamaCPPEngine()
        case .ollama:
            engine = OllamaEngine()
        case .mlx:
            throw NSError(domain: "AuxiliaryModelManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "MLX engine not implemented yet"])
        }
        
        try await engine.loadModel(config: config)
        engines[role] = engine
        return engine
    }
    
    func unloadEngine(for role: String) async {
        if let engine = engines[role] {
            await engine.unloadModel()
            engines.removeValue(forKey: role)
        }
    }
}
