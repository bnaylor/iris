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
                    throw URLError(.userAuthenticationRequired)
                }
                
                var cleanRequest = request
                var cleanContents: [Content] = []
                for content in cleanRequest.contents {
                    var cleanParts: [Part] = []
                    for part in content.parts {
                        var cleanPart = part
                        cleanPart.thought_signature = nil
                        cleanPart.thoughtSignature = nil
                        if var fnCall = cleanPart.functionCall {
                            fnCall.thought_signature = nil
                            fnCall.thoughtSignature = nil
                            cleanPart.functionCall = fnCall
                        }
                        cleanParts.append(cleanPart)
                    }
                    var cleanContent = content
                    cleanContent.parts = cleanParts
                    cleanContents.append(cleanContent)
                }
                cleanRequest.contents = cleanContents
                
                if let sysInst = cleanRequest.systemInstruction {
                    var cleanSysParts: [Part] = []
                    for part in sysInst.parts {
                        var cleanPart = part
                        cleanPart.thought_signature = nil
                        cleanPart.thoughtSignature = nil
                        if var fnCall = cleanPart.functionCall {
                            fnCall.thought_signature = nil
                            fnCall.thoughtSignature = nil
                            cleanPart.functionCall = fnCall
                        }
                        cleanSysParts.append(cleanPart)
                    }
                    cleanRequest.systemInstruction?.parts = cleanSysParts
                }
                
                let baseURLString = config.geminiBaseURL.isEmpty ? "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent" : config.geminiBaseURL
                
                var urlComponents = URLComponents(string: baseURLString)!
                urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]
                
                var urlRequest = URLRequest(url: urlComponents.url!)
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
