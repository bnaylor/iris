import Foundation

actor OllamaEngine: AuxiliaryInferenceEngine {
    private var modelName: String = ""
    
    private static let baseURL = "http://localhost:11434"

    func loadModel(config: AuxiliaryModelConfig) async throws {
        self.modelName = config.modelPathOrName
        // Warm the model on init so the first Vibecop call doesn't hit a cold-start timeout
        preloadModel()
    }
    
    func unloadModel() async {
        let url = URL(string: "\(Self.baseURL)/api/generate")!
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
              let url = URL(string: "\(Self.baseURL)/api/ps") else { return false }
        
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
    
    // MARK: - Static helpers for model discovery & pull
    
    /// Quick check whether the Ollama daemon is reachable at localhost:11434.
    /// Uses a short timeout so the UI doesn't hang.
    static func isDaemonReachable() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    /// Probes the local Ollama daemon for installed models via GET /api/tags.
    /// Returns an array of model name strings (e.g. ["gemma4:12b", "qwen3.5:latest"]),
    /// or an empty array if the daemon is unreachable or returns an error.
    static func listInstalledModels() async -> [String] {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 5
        
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return [] }
            
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                return models.compactMap { $0["name"] as? String }.sorted()
            }
        } catch {
            return []
        }
        return []
    }
    
    /// Pulls a model from Ollama's registry. Reports progress via the callback.
    /// The callback receives a human-readable status string (e.g. "pulling manifest",
    /// "downloading 45%", "verifying sha256 digest", "done").
    static func pullModel(name: String, onProgress: @escaping @Sendable (String) -> Void) async throws {
        guard let url = URL(string: "\(baseURL)/api/pull") else {
            throw NSError(domain: "OllamaEngine", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid base URL"])
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["name": name, "stream": false]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 600
        
        onProgress("Starting pull of \(name)…")
        
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "OllamaEngine", code: 4, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        
        if httpResponse.statusCode == 200 {
            // If stream:false, the response is a single JSON object with "status": "success"
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String {
                if status == "success" {
                    onProgress("done")
                    return
                }
                onProgress(status)
                return
            }
            onProgress("done")
            return
        }
        
        let errBody = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: "OllamaEngine", code: 5, userInfo: [NSLocalizedDescriptionKey: "Pull failed (HTTP \(httpResponse.statusCode)): \(errBody)"])
    }
    
    /// Fires a non-blocking warmup request to keep the model alive.
    /// Ollama's default keep_alive is ~5m, so this extends the window.
    private func preloadModel() {
        Task {
            guard !modelName.isEmpty,
                  let url = URL(string: "\(Self.baseURL)/api/generate") else { return }
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
    func generate(prompt: String, jsonSchema: String?) async throws -> String {
        try await generate(prompt: prompt, jsonSchema: jsonSchema, images: nil)
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
