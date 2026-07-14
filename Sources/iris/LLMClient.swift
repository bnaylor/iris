import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { return message }
}

struct LLMClient {
    func endpoint(for tier: ModelTier) -> String {
        let config = ConfigManager.shared
        let modelName = config.getModel(for: tier)
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
        
        let modelName = config.getModel(for: tier)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let response: GeminiResponse
            if provider == LLMProvider.anthropic.rawValue {
                response = try await AnthropicClient.generateContent(request: request, model: modelName, apiKey: config.anthropicAPIKey, baseURL: config.anthropicBaseURL)
            } else if provider == LLMProvider.openai.rawValue {
                response = try await OpenAIClient.generateContent(request: request, model: modelName, apiKey: config.openAIAPIKey, baseURL: config.openAIBaseURL)
            } else {
                // Fallback to Gemini
                let apiKey = config.geminiAPIKey
                guard !apiKey.isEmpty else {
                    throw APIError.init(message: "GEMINI_FALLBACK_AUTH_ERROR_1013")
                }
                
                let cleanRequest = request
                // We no longer strip thought_signature because Gemini requires it to be echoed back
                
                let baseURLString = config.geminiBaseURL.isEmpty ? "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent" : config.geminiBaseURL
                
                guard var urlComponents = URLComponents(string: baseURLString) else {
                    throw APIError(message: "Invalid Gemini base URL configuration: \(baseURLString)")
                }
                urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]

                guard let requestURL = urlComponents.url else {
                    throw APIError(message: "Failed to construct Gemini request URL.")
                }
                var urlRequest = URLRequest(url: requestURL)
                urlRequest.httpMethod = "POST"
                urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let encoder = JSONEncoder()
                encoder.keyEncodingStrategy = .useDefaultKeys
                let requestData = try encoder.encode(cleanRequest)
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
