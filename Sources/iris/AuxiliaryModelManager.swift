import Foundation

final class AuxiliaryModelManager: @unchecked Sendable {
    static let shared = AuxiliaryModelManager()
    
    // In-memory engines mapped by role
    private var engines: [String: AuxiliaryInferenceEngine] = [:]
    private let lock = NSLock()
    
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
        let existing = lock.withLock { engines[role] }
        if let existing = existing {
            return existing
        }
        
        let engine: AuxiliaryInferenceEngine
        switch config.engineType {
        case .llamaCPP:
            engine = try await LlamaCPPEngine()
        case .ollama:
            engine = OllamaEngine()
        case .mlx:
            engine = MLXEngine.shared
        }
        
        try await engine.loadModel(config: config)
        
        lock.withLock { engines[role] = engine }
        return engine
    }
    
    func unloadEngine(for role: String) async {
        let engine = lock.withLock { engines.removeValue(forKey: role) }
        
        if let engine = engine {
            await engine.unloadModel()
        }
    }
    
    func setMockEngine(_ engine: AuxiliaryInferenceEngine, for role: String) {
        lock.withLock { engines[role] = engine }
    }
}
