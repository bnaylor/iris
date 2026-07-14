import XCTest
@testable import iris

final class AnthropicClientTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
    }
    
    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.handler = nil
        super.tearDown()
    }
    
    func testAnthropicRequestTranslationText() async throws {
        let request = GeminiRequest(
            contents: [
                Content(role: "user", parts: [Part(text: "Hello, Claude", functionCall: nil, functionResponse: nil, thought_signature: nil, thoughtSignature: nil)])
            ],
            systemInstruction: Content(role: "system", parts: [Part(text: "System instructions here", functionCall: nil, functionResponse: nil, thought_signature: nil, thoughtSignature: nil)]),
            tools: nil
        )
        
        MockURLProtocol.handler = { urlRequest in
            XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.anthropic.com/v1/messages")
            XCTAssertEqual(urlRequest.httpMethod, "POST")
            XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "x-api-key"), "test-key-anthropic")
            XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
            XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
            
            guard let bodyData = urlRequest.bodyData,
                  let bodyJson = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
                XCTFail("Failed to read HTTP request body")
                return (HTTPURLResponse(), Data())
            }
            
            XCTAssertEqual(bodyJson["model"] as? String, "claude-3-5-sonnet")
            
            if let systemArray = bodyJson["system"] as? [[String: Any]],
               let firstBlock = systemArray.first,
               let text = firstBlock["text"] as? String {
                XCTAssertEqual(text, "System instructions here")
                if let cacheControl = firstBlock["cache_control"] as? [String: Any] {
                    XCTAssertEqual(cacheControl["type"] as? String, "ephemeral")
                } else {
                    XCTFail("Missing cache_control in system block")
                }
            } else {
                XCTFail("System prompt is not in the expected array of blocks format")
            }
            
            guard let messages = bodyJson["messages"] as? [[String: Any]] else {
                XCTFail("Missing messages array")
                return (HTTPURLResponse(), Data())
            }
            
            XCTAssertEqual(messages.count, 1)
            let firstMessage = messages[0]
            XCTAssertEqual(firstMessage["role"] as? String, "user")
            
            guard let contents = firstMessage["content"] as? [[String: Any]] else {
                XCTFail("Missing content array in message")
                return (HTTPURLResponse(), Data())
            }
            
            XCTAssertEqual(contents.count, 1)
            XCTAssertEqual(contents[0]["type"] as? String, "text")
            XCTAssertEqual(contents[0]["text"] as? String, "Hello, Claude")
            
            let responseJson: [String: Any] = [
                "id": "msg_01",
                "type": "message",
                "role": "assistant",
                "model": "claude-3-5-sonnet",
                "content": [
                    [
                        "type": "text",
                        "text": "Hello there! I am Claude."
                    ]
                ],
                "usage": [
                    "input_tokens": 12,
                    "output_tokens": 24
                ]
            ]
            
            let responseData = try! JSONSerialization.data(withJSONObject: responseJson)
            let httpResponse = HTTPURLResponse(
                url: urlRequest.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (httpResponse, responseData)
        }
        
        let response = try await AnthropicClient.generateContent(
            request: request,
            model: "claude-3-5-sonnet",
            apiKey: "test-key-anthropic"
        )
        
        XCTAssertNotNil(response.candidates)
        XCTAssertEqual(response.candidates?.count, 1)
        let firstCandidate = response.candidates?[0]
        XCTAssertEqual(firstCandidate?.content?.role, "model")
        XCTAssertEqual(firstCandidate?.content?.parts.count, 1)
        XCTAssertEqual(firstCandidate?.content?.parts[0].text, "Hello there! I am Claude.")
        
        XCTAssertEqual(response.usageMetadata?.promptTokenCount, 12)
        XCTAssertEqual(response.usageMetadata?.candidatesTokenCount, 24)
    }
    
    func testAnthropicRequestTranslationTools() async throws {
        let functionDecl = FunctionDeclaration(
            name: "get_weather",
            description: "Get the current weather",
            parameters: Schema(
                type: "object",
                properties: [
                    "location": Schema(type: "string", properties: nil, required: nil, description: "City and state, e.g. San Francisco, CA")
                ],
                required: ["location"],
                description: nil
            )
        )
        
        let request = GeminiRequest(
            contents: [
                Content(role: "user", parts: [Part(text: "What is the weather in Boston?", functionCall: nil, functionResponse: nil, thought_signature: nil, thoughtSignature: nil)])
            ],
            systemInstruction: nil,
            tools: [Tool(functionDeclarations: [functionDecl])]
        )
        
        MockURLProtocol.handler = { urlRequest in
            guard let bodyData = urlRequest.bodyData,
                  let bodyJson = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
                XCTFail("Failed to read HTTP request body")
                return (HTTPURLResponse(), Data())
            }
            
            guard let tools = bodyJson["tools"] as? [[String: Any]] else {
                XCTFail("Missing tools field")
                return (HTTPURLResponse(), Data())
            }
            
            XCTAssertEqual(tools.count, 1)
            let firstTool = tools[0]
            XCTAssertEqual(firstTool["name"] as? String, "get_weather")
            XCTAssertEqual(firstTool["description"] as? String, "Get the current weather")
            
            guard let inputSchema = firstTool["input_schema"] as? [String: Any] else {
                XCTFail("Missing input_schema field in tool")
                return (HTTPURLResponse(), Data())
            }
            
            XCTAssertEqual(inputSchema["type"] as? String, "object")
            guard let properties = inputSchema["properties"] as? [String: Any] else {
                XCTFail("Missing properties in schema")
                return (HTTPURLResponse(), Data())
            }
            
            XCTAssertNotNil(properties["location"])
            
            let responseJson: [String: Any] = [
                "id": "msg_02",
                "type": "message",
                "role": "assistant",
                "model": "claude-3-5-sonnet",
                "content": [
                    [
                        "type": "tool_use",
                        "id": "call_get_weather_1",
                        "name": "get_weather",
                        "input": [
                            "location": "Boston"
                        ]
                    ]
                ],
                "usage": [
                    "input_tokens": 50,
                    "output_tokens": 15
                ]
            ]
            
            let responseData = try! JSONSerialization.data(withJSONObject: responseJson)
            let httpResponse = HTTPURLResponse(
                url: urlRequest.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (httpResponse, responseData)
        }
        
        let response = try await AnthropicClient.generateContent(
            request: request,
            model: "claude-3-5-sonnet",
            apiKey: "test-key-anthropic"
        )
        
        XCTAssertNotNil(response.candidates)
        XCTAssertEqual(response.candidates?.count, 1)
        let firstCandidate = response.candidates?[0]
        XCTAssertEqual(firstCandidate?.content?.parts.count, 1)
        let firstPart = firstCandidate?.content?.parts[0]
        XCTAssertNotNil(firstPart?.functionCall)
        XCTAssertEqual(firstPart?.functionCall?.args["location"], "Boston")
    }
    
    func testAnthropicMultipleToolCalls() async throws {
        let tools = [
            FunctionDeclaration(
                name: "get_weather",
                description: "Get the current weather",
                parameters: Schema(
                    type: "OBJECT",
                    properties: ["location": Schema(type: "STRING", description: "City")],
                    required: ["location"]
                )
            ),
            FunctionDeclaration(
                name: "get_time",
                description: "Get the current time",
                parameters: Schema(
                    type: "OBJECT",
                    properties: ["location": Schema(type: "STRING", description: "City")],
                    required: ["location"]
                )
            )
        ]
        
        let request = GeminiRequest(
            contents: [Content(role: "user", parts: [Part(text: "What is the weather and time in Boston?", functionCall: nil, functionResponse: nil, thought_signature: nil, thoughtSignature: nil)])],
            systemInstruction: nil,
            tools: [Tool(functionDeclarations: tools)]
        )
        
        MockURLProtocol.handler = { urlRequest in
            let responseJson: [String: Any] = [
                "id": "msg_03",
                "type": "message",
                "role": "assistant",
                "model": "claude-3-5-sonnet",
                "content": [
                    [
                        "type": "tool_use",
                        "id": "call_1",
                        "name": "get_weather",
                        "input": [
                            "location": "Boston"
                        ]
                    ],
                    [
                        "type": "tool_use",
                        "id": "call_2",
                        "name": "get_time",
                        "input": [
                            "location": "Boston"
                        ]
                    ]
                ],
                "usage": [
                    "input_tokens": 50,
                    "output_tokens": 30
                ]
            ]
            
            let responseData = try! JSONSerialization.data(withJSONObject: responseJson)
            let httpResponse = HTTPURLResponse(
                url: urlRequest.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (httpResponse, responseData)
        }
        
        let response = try await AnthropicClient.generateContent(
            request: request,
            model: "claude-3-5-sonnet",
            apiKey: "test-key-anthropic"
        )
        
        XCTAssertNotNil(response.candidates)
        XCTAssertEqual(response.candidates?.count, 1)
        let firstCandidate = response.candidates?[0]
        XCTAssertEqual(firstCandidate?.content?.parts.count, 2)
        
        let firstPart = firstCandidate?.content?.parts[0]
        XCTAssertEqual(firstPart?.functionCall?.name, "get_weather")
        XCTAssertEqual(firstPart?.functionCall?.id, "call_1")
        
        let secondPart = firstCandidate?.content?.parts[1]
        XCTAssertEqual(secondPart?.functionCall?.name, "get_time")
        XCTAssertEqual(secondPart?.functionCall?.id, "call_2")
    }
    
    func testAnthropicErrorPropagation() async throws {
        let request = GeminiRequest(
            contents: [Content(role: "user", parts: [Part(text: "Hello", functionCall: nil, functionResponse: nil, thought_signature: nil, thoughtSignature: nil)])],
            systemInstruction: nil,
            tools: nil
        )
        
        MockURLProtocol.handler = { urlRequest in
            let httpResponse = HTTPURLResponse(
                url: urlRequest.url!,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            )!
            let errorJson = ["error": ["type": "invalid_request_error", "message": "API key is invalid"]]
            let responseData = try! JSONSerialization.data(withJSONObject: errorJson)
            return (httpResponse, responseData)
        }
        
        do {
            _ = try await AnthropicClient.generateContent(
                request: request,
                model: "claude-3-5-sonnet",
                apiKey: "test-key-anthropic"
            )
            XCTFail("Expected an error to be thrown")
        } catch let error as APIError {
            XCTAssertTrue(error.localizedDescription.contains("Anthropic HTTP 400"))
            XCTAssertTrue(error.localizedDescription.contains("API key is invalid"))
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }
}