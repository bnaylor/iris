import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { return message }
}

struct LLMClient {
    func endpoint(for tier: ModelTier) -> String {
        let config = ConfigManager.shared
        let modelName: String
        switch tier {
        case .easy: modelName = config.modelEasy
        case .medium: modelName = config.modelMedium
        case .hard: modelName = config.modelHard
        }
        return "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent"
    }
    
    func generateContent(request: GeminiRequest, tier: ModelTier = .medium) async throws -> GeminiResponse {
        let config = ConfigManager.shared
        let provider = config.primaryProvider
        
        let metricOp: MetricOperationType
        switch tier {
        case .easy: metricOp = .easy
        case .medium: metricOp = .medium
        case .hard: metricOp = .hard
        }
        
        let modelName = {
            switch tier {
            case .easy: return config.modelEasy
            case .medium: return config.modelMedium
            case .hard: return config.modelHard
            }
        }()
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let response: GeminiResponse
            if provider == LLMProvider.anthropic.rawValue {
                response = try await AnthropicClient.generateContent(request: request, model: modelName, apiKey: config.anthropicAPIKey)
            } else if provider == LLMProvider.openai.rawValue {
                response = try await OpenAIClient.generateContent(request: request, model: modelName, apiKey: config.openAIAPIKey)
            } else {
                // Fallback to Gemini
                let apiKey = config.geminiAPIKey
                guard !apiKey.isEmpty else {
                    throw URLError(.userAuthenticationRequired)
                }
                
                var urlComponents = URLComponents(string: endpoint(for: tier))!
                urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]
                
                var urlRequest = URLRequest(url: urlComponents.url!)
                urlRequest.httpMethod = "POST"
                urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .useDefaultKeys
                let requestData = try encoder.encode(request)
                urlRequest.httpBody = requestData
                
                let (data, urlResponse) = try await URLSession.shared.data(for: urlRequest)
                
                guard let httpResponse = urlResponse as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                
                if httpResponse.statusCode != 200 {
                    let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("API Error (\(httpResponse.statusCode)): \(errorString)")
                    throw APIError(message: "HTTP \(httpResponse.statusCode): \(errorString)")
                }
                
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .useDefaultKeys
                response = try decoder.decode(GeminiResponse.self, from: data)
            }
            
            let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            await MetricsManager.shared.trackLatency(operation: metricOp, modelName: modelName, durationMs: durationMs, success: true)
            return response
            
        } catch {
            let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
            await MetricsManager.shared.trackLatency(operation: metricOp, modelName: modelName, durationMs: durationMs, success: false)
            throw error
        }
    }
}
