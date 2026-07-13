import Foundation

struct OpenAIClient {
    static func generateContent(request: GeminiRequest, model: String, apiKey: String) async throws -> GeminiResponse {
        guard !apiKey.isEmpty else {
            throw URLError(.userAuthenticationRequired)
        }
        
        var openAIMessages: [[String: Any]] = []
        
        if let sysInst = request.systemInstruction, let text = sysInst.parts.first?.text {
            openAIMessages.append([
                "role": "system",
                "content": text
            ])
        }
        
        var callIdCounter = 0
        var currentToolCalls: [[String: Any]] = []
        
        for content in request.contents {
            let role = content.role == "model" ? "assistant" : "user"
            var message: [String: Any] = ["role": role]
            var textParts = [String]()
            var toolCalls = [[String: Any]]()
            var toolResponses = [[String: Any]]()
            
            for part in content.parts {
                if let text = part.text {
                    textParts.append(text)
                } else if let fc = part.functionCall {
                    let id = "call_\(fc.name)_\(callIdCounter)"
                    callIdCounter += 1
                    let argsData = try? JSONSerialization.data(withJSONObject: fc.args)
                    let argsString = String(data: argsData ?? Data(), encoding: .utf8) ?? "{}"
                    
                    toolCalls.append([
                        "id": id,
                        "type": "function",
                        "function": [
                            "name": fc.name,
                            "arguments": argsString
                        ]
                    ])
                } else if let fr = part.functionResponse {
                    let id = "call_\(fr.name)_0" // Best effort match
                    let respData = try? JSONSerialization.data(withJSONObject: fr.response)
                    let respString = String(data: respData ?? Data(), encoding: .utf8) ?? "{}"
                    
                    toolResponses.append([
                        "role": "tool",
                        "tool_call_id": id,
                        "name": fr.name,
                        "content": respString
                    ])
                }
            }
            
            if !textParts.isEmpty {
                message["content"] = textParts.joined(separator: "\n")
            } else if toolCalls.isEmpty && toolResponses.isEmpty {
                message["content"] = ""
            }
            
            if !toolCalls.isEmpty {
                message["tool_calls"] = toolCalls
            }
            
            if !toolResponses.isEmpty {
                // OpenAI requires tool responses to be separate messages
                // If we have a mix, we should just append the tool responses directly to openAIMessages
                // Wait, if it's user role, we can just drop the tool responses in as individual messages
                for tr in toolResponses {
                    openAIMessages.append(tr)
                }
            } else {
                openAIMessages.append(message)
            }
        }
        
        // Let's refine the ID matching. Iris sends back the function response in the next turn as 'user'.
        // So the IDs need to match the previous turn's tool calls. We can map by name.
        // Let's do a pass to fix tool_call_id mappings.
        var nameToLastId: [String: String] = [:]
        for i in 0..<openAIMessages.count {
            if let calls = openAIMessages[i]["tool_calls"] as? [[String: Any]] {
                for call in calls {
                    if let f = call["function"] as? [String: Any], let name = f["name"] as? String, let id = call["id"] as? String {
                        nameToLastId[name] = id
                    }
                }
            }
            if let role = openAIMessages[i]["role"] as? String, role == "tool", let name = openAIMessages[i]["name"] as? String {
                if let id = nameToLastId[name] {
                    openAIMessages[i]["tool_call_id"] = id
                }
            }
        }
        
        var body: [String: Any] = [
            "model": model,
            "messages": openAIMessages
        ]
        
        if let tools = request.tools, let fds = tools.first?.functionDeclarations {
            var openAITools = [[String: Any]]()
            for fd in fds {
                var parameters: [String: Any] = ["type": "object", "properties": [:] as [String: Any]]
                if let schema = fd.parameters {
                    let schemaData = try? JSONEncoder().encode(schema)
                    if let dict = try? JSONSerialization.jsonObject(with: schemaData ?? Data()) as? [String: Any] {
                        parameters = dict
                    }
                }
                openAITools.append([
                    "type": "function",
                    "function": [
                        "name": fd.name,
                        "description": fd.description,
                        "parameters": parameters
                    ]
                ])
            }
            if !openAITools.isEmpty {
                body["tools"] = openAITools
            }
        }
        
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.addValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError(message: "OpenAI HTTP \(httpResponse.statusCode): \(errorString)")
        }
        
        // Parse OpenAI response back to GeminiResponse
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var geminiResponse = GeminiResponse()
        geminiResponse.candidates = []
        
        if let choices = json["choices"] as? [[String: Any]], let first = choices.first, let msg = first["message"] as? [String: Any] {
            var content = Content(role: "model", parts: [])
            
            if let text = msg["content"] as? String, !text.isEmpty {
                content.parts.append(Part(text: text, functionCall: nil, functionResponse: nil, thought_signature: nil, thoughtSignature: nil))
            }
            
            if let toolCalls = msg["tool_calls"] as? [[String: Any]] {
                for call in toolCalls {
                    if let f = call["function"] as? [String: Any], let name = f["name"] as? String, let argsStr = f["arguments"] as? String {
                        let argsDict = (try? JSONSerialization.jsonObject(with: argsStr.data(using: .utf8) ?? Data())) as? [String: String] ?? [:]
                        content.parts.append(Part(text: nil, functionCall: FunctionCall(name: name, args: argsDict, thought_signature: nil, thoughtSignature: nil), functionResponse: nil, thought_signature: nil, thoughtSignature: nil))
                    }
                }
            }
            
            geminiResponse.candidates?.append(Candidate(content: content))
        }
        
        if let usage = json["usage"] as? [String: Any] {
            geminiResponse.usageMetadata = UsageMetadata(
                promptTokenCount: usage["prompt_tokens"] as? Int,
                candidatesTokenCount: usage["completion_tokens"] as? Int,
                totalTokenCount: usage["total_tokens"] as? Int
            )
        }
        
        return geminiResponse
    }
}
