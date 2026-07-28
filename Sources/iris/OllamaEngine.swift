import Foundation

actor OllamaEngine: AuxiliaryInferenceEngine {
    private var modelName: String = ""

    func loadModel(config: AuxiliaryModelConfig) async throws {
        self.modelName = config.modelPathOrName
        // Warm the model on init so the first Vibecop call doesn't hit a cold-start timeout
        preloadModel()
    }
    
    func unloadModel() async {
        let url = URL(string: "http://localhost:11434/api/generate")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": modelName,
            "keep_alive": 0
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        _ = try? await URLSession.shared.data(for: req)
    }
    
    /// Checks whether the model is currently loaded in Ollama's VRAM/RAM
    /// by querying the /api/ps endpoint.
    func isModelLoaded() async -> Bool {
        guard !modelName.isEmpty,
              let url = URL(string: "http://localhost:11434/api/ps") else { return false }
        
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return false }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                return models.contains { model in
                    guard let name = model["name"] as? String else { return false }
                    return name == modelName || name.hasPrefix(modelName + ":")
                }
            }
        } catch {
            return false
        }
        return false
    }
    
    /// Fires a non-blocking warmup request to keep the model alive.
    /// Ollama's default keep_alive is ~5m, so this extends the window.
    private func preloadModel() {
        Task {
            guard !modelName.isEmpty,
                  let url = URL(string: "http://localhost:11434/api/generate") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": modelName,
                "prompt": "",
                "keep_alive": "5m"
            ]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            _ = try? await URLSession.shared.data(for: req)
        }
    }
    
    func generate(prompt: String, jsonSchema: String?, images: [String]? = nil) async throws -> String {
        let url = URL(string: "http://localhost:11434/api/generate")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var body: [String: Any] = [
            "model": modelName,
            "prompt": prompt,
            "stream": false
        ]
        
        if jsonSchema != nil {
            body["format"] = "json"
        }
        
        if let images, !images.isEmpty {
            body["images"] = images
        }
        
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: req)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errString = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NSError(domain: "OllamaEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Ollama Error: \(errString)"])
        }
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let responseText = json["response"] as? String {
            return responseText
        }
        
        throw NSError(domain: "OllamaEngine", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid Ollama JSON response"])
    }
}
