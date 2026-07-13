import Foundation

struct AnthropicClient {
    static func generateContent(request: GeminiRequest, model: String, apiKey: String, baseURL: String = "") async throws -> GeminiResponse {
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

        // Cache breakpoints for conversation history.
        // Marking the penultimate message's last block caches all prior history as a stable prefix.
        // Marking the current (last) message's last block seeds the cache for the next turn.
        let ephemeral: [String: Any] = ["cache_control": ["type": "ephemeral"]]
        func markLastContentBlock(_ messages: inout [[String: Any]], at index: Int) {
            var msg = messages[index]
            if var content = msg["content"] as? [[String: Any]], !content.isEmpty {
                content[content.count - 1].merge(ephemeral) { _, new in new }
                msg["content"] = content
                messages[index] = msg
            }
        }
        if anthropicMessages.count >= 2 {
            markLastContentBlock(&anthropicMessages, at: anthropicMessages.count - 2)
        }
        if !anthropicMessages.isEmpty {
            markLastContentBlock(&anthropicMessages, at: anthropicMessages.count - 1)
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": anthropicMessages
        ]
        
        if !systemPrompt.isEmpty {
            body["system"] = [["type": "text", "text": systemPrompt, "cache_control": ["type": "ephemeral"]]]
        }
        
        if let tools = request.tools, let fds = tools.first?.functionDeclarations {
            var anthropicTools = [[String: Any]]()
            for fd in fds {
                var inputSchema: [String: Any] = ["type": "object", "properties": [:] as [String: Any]]
                if let schema = fd.parameters {
                    let schemaData = try? JSONEncoder().encode(schema)
                    if var dict = try? JSONSerialization.jsonObject(with: schemaData ?? Data()) as? [String: Any] {
                        // Gemini often uses uppercase types (e.g. "OBJECT", "STRING").
                        // JSON Schema (Anthropic) requires lowercase.
                        func lowerCaseTypes(_ dictionary: inout [String: Any]) {
                            if let type = dictionary["type"] as? String {
                                dictionary["type"] = type.lowercased()
                            }
                            if var properties = dictionary["properties"] as? [String: [String: Any]] {
                                for (k, var v) in properties {
                                    lowerCaseTypes(&v)
                                    properties[k] = v
                                }
                                dictionary["properties"] = properties
                            }
                            if var items = dictionary["items"] as? [String: Any] {
                                lowerCaseTypes(&items)
                                dictionary["items"] = items
                            }
                        }
                        
                        lowerCaseTypes(&dict)
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
                anthropicTools[anthropicTools.count - 1]["cache_control"] = ["type": "ephemeral"]
                body["tools"] = anthropicTools
            }
        }
        
        var endpointUrl = "https://api.anthropic.com/v1/messages"
        if !baseURL.isEmpty {
            if baseURL.hasSuffix("/messages") {
                endpointUrl = baseURL
            } else {
                let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                endpointUrl = "\(trimmed)/messages"
            }
        }
        
        let url = URL(string: endpointUrl)!
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
            
            var foundToolUse = false
            for part in contentArray {
                if let type = part["type"] as? String {
                    if type == "text", let text = part["text"] as? String {
                        content.parts.append(Part(text: text, functionCall: nil, functionResponse: nil, thought_signature: nil, thoughtSignature: nil))
                    } else if type == "tool_use", !foundToolUse, let name = part["name"] as? String, let input = part["input"] as? [String: Any] {
                        foundToolUse = true
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
