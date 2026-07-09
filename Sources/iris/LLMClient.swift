import Foundation

struct LLMClient {
    var endpoint: String {
        "https://generativelanguage.googleapis.com/v1beta/models/\(ConfigManager.shared.geminiModel):generateContent"
    }
    
    func generateContent(request: GeminiRequest) async throws -> GeminiResponse {
        let apiKey = ConfigManager.shared.geminiAPIKey
        guard !apiKey.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }
        
        var urlComponents = URLComponents(string: endpoint)!
        urlComponents.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        var urlRequest = URLRequest(url: urlComponents.url!)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        let requestData = try encoder.encode(request)
        urlRequest.httpBody = requestData
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("API Error (\(httpResponse.statusCode)): \(errorString)")
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        let geminiResponse = try decoder.decode(GeminiResponse.self, from: data)
        return geminiResponse
    }
    
    func fetchAvailableModels() async throws -> [String] {
        let apiKey = ConfigManager.shared.geminiAPIKey
        guard !apiKey.isEmpty else { return [] }
        
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let models = json["models"] as? [[String: Any]] {
            return models.compactMap { $0["name"] as? String }.map { $0.replacingOccurrences(of: "models/", with: "") }
        }
        return []
    }
}
