import Foundation

struct LLMClient {
    let apiKey: String
    let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro:generateContent"
    
    init() {
        guard let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] else {
            fatalError("GEMINI_API_KEY environment variable not set")
        }
        self.apiKey = key
    }
    
    func generateContent(request: GeminiRequest) async throws -> GeminiResponse {
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
}
