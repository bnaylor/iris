import Foundation

struct AnthropicClient {
    static func generateContent(request: GeminiRequest, model: String, apiKey: String) async throws -> GeminiResponse {
        guard !apiKey.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }
        
        var anthropicMessages: [[String: Any]] = []
        var systemPrompt = ""
        
        if let sysInst = request.systemInstruction, let text = sysInst.parts.first?.text {
            systemPrompt = text
        }
        
        var callIdCounter = 0
        var nameToLastId: [String: String] = [:]
        
        for content in request.contents {
            let role = content.role == "model" ? "assistant" : "user"
            var partsArray: [[String: Any]] = []
            
            for part in content.parts {
                if let text = part.text {
                    partsArray.append(["type": "text", "text": text])
                } else if let fc = part.functionCall {
                    let id = "call_\(fc.name)_\(callIdCounter)"
                    callIdCounter += 1
                    nameToLastId[fc.name] = id
                    
                    partsArray.append([
                        "type": "tool_use",
                        "id": id,
                        "name": fc.name,
                        "input": fc.args
                    ])
                } else if let fr = part.functionResponse {
                    let id = nameToLastId[fr.name] ?? "call_\(fr.name)_0"
                    let respData = try? JSONSerialization.data(withJSONObject: fr.response)
                    let respString = String(data: respData ?? Data(), encoding: .utf8) ?? "{}"
                    
                    partsArray.append([
                        "type": "tool_result",
                        "tool_use_id": id,
                        "content": respString
                    ])
                }
            }
            
            if !partsArray.isEmpty {
                anthropicMessages.append([
                    "role": role,
                    "content": partsArray
                ])
            }
        }
        
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": anthropicMessages
        ]
        
        if !systemPrompt.isEmpty {
            body["system"] = systemPrompt
        }
        
        if let tools = request.tools, let fds = tools.first?.functionDeclarations {
            var anthropicTools = [[String: Any]]()
            for fd in fds {
                var inputSchema: [String: Any] = ["type": "object", "properties": [:] as [String: Any]]
                if let schema = fd.parameters {
                    let schemaData = try? JSONEncoder().encode(schema)
                    if let dict = try? JSONSerialization.jsonObject(with: schemaData ?? Data()) as? [String: Any] {
                        inputSchema = dict
                    }
                }
                anthropicTools.append([
                    "name": fd.name,
                    "description": fd.description,
                    "input_schema": inputSchema
                ])
            }
            if !anthropicTools.isEmpty {
                body["tools"] = anthropicTools
            }
        }
        
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError(message: "Anthropic HTTP \(httpResponse.statusCode): \(errorString)")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var geminiResponse = GeminiResponse()
        geminiResponse.candidates = []
        
        if let contentArray = json["content"] as? [[String: Any]] {
            var content = Content(role: "model", parts: [])
            
            for part in contentArray {
                if let type = part["type"] as? String {
                    if type == "text", let text = part["text"] as? String {
                        content.parts.append(Part(text: text, functionCall: nil, functionResponse: nil, thought_signature: nil, thoughtSignature: nil))
                    } else if type == "tool_use", let name = part["name"] as? String, let input = part["input"] as? [String: Any] {
                        // Convert [String: Any] back to [String: String] since Iris FunctionCall args are [String: String]
                        var stringArgs: [String: String] = [:]
                        for (k, v) in input {
                            stringArgs[k] = "\(v)"
                        }
                        content.parts.append(Part(text: nil, functionCall: FunctionCall(name: name, args: stringArgs, thought_signature: nil, thoughtSignature: nil), functionResponse: nil, thought_signature: nil, thoughtSignature: nil))
                    }
                }
            }
            
            if !content.parts.isEmpty {
                geminiResponse.candidates?.append(Candidate(content: content))
            }
        }
        
        if let usage = json["usage"] as? [String: Any] {
            geminiResponse.usageMetadata = UsageMetadata(
                promptTokenCount: usage["input_tokens"] as? Int,
                candidatesTokenCount: usage["output_tokens"] as? Int,
                totalTokenCount: nil
            )
        }
        
        return geminiResponse
    }
}
