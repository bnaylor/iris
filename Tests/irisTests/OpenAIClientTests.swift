import XCTest
@testable import iris

final class OpenAIClientTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
    }
    
    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.handler = nil
        super.tearDown()
    }
    
    func testOpenAIRequestTranslationText() async throws {
        let request = GeminiRequest(
            contents: [
                Content(role: "user", parts: [Part(text: "Hello, GPT", functionCall: nil, functionResponse: nil, thought_signature: nil, thoughtSignature: nil)])
            ],
            systemInstruction: Content(role: "system", parts: [Part(text: "Act as a helpful helper", functionCall: nil, functionResponse: nil, thought_signature: nil, thoughtSignature: nil)]),
            tools: nil
        )
        
        MockURLProtocol.handler = { urlRequest in
            XCTAssertEqual(urlRequest.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
            XCTAssertEqual(urlRequest.httpMethod, "POST")
            XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer test-key-openai")
            XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Content-Type"), "application/json")
            
            guard let bodyData = urlRequest.bodyData,
                  let bodyJson = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
                XCTFail("Failed to read HTTP request body")
                return (HTTPURLResponse(), Data())
            }
            
            XCTAssertEqual(bodyJson["model"] as? String, "gpt-4o")
            
            guard let messages = bodyJson["messages"] as? [[String: Any]] else {
                XCTFail("Missing messages field in OpenAI body")
                return (HTTPURLResponse(), Data())
            }
            
            XCTAssertEqual(messages.count, 2)
            XCTAssertEqual(messages[0]["role"] as? String, "system")
            XCTAssertEqual(messages[0]["content"] as? String, "Act as a helpful helper")
            
            XCTAssertEqual(messages[1]["role"] as? String, "user")
            XCTAssertEqual(messages[1]["content"] as? String, "Hello, GPT")
            
            let responseJson: [String: Any] = [
                "id": "chatcmpl-001",
                "object": "chat.completion",
                "created": 123456789,
                "model": "gpt-4o",
                "choices": [
                    [
                        "index": 0,
                        "message": [
                          "role": "assistant",
                          "content": "Hi! How can I assist you?"
                        ],
                        "finish_reason": "stop"
                    ]
                ],
                "usage": [
                    "prompt_tokens": 15,
                    "completion_tokens": 10,
                    "total_tokens": 25
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
        
        let response = try await OpenAIClient.generateContent(
            request: request,
            model: "gpt-4o",
            apiKey: "test-key-openai"
        )
        
        XCTAssertNotNil(response.candidates)
        XCTAssertEqual(response.candidates?.count, 1)
        let firstCandidate = response.candidates?[0]
        XCTAssertEqual(firstCandidate?.content?.parts.count, 1)
        XCTAssertEqual(firstCandidate?.content?.parts[0].text, "Hi! How can I assist you?")
        
        XCTAssertEqual(response.usageMetadata?.promptTokenCount, 15)
        XCTAssertEqual(response.usageMetadata?.candidatesTokenCount, 10)
        XCTAssertEqual(response.usageMetadata?.totalTokenCount, 25)
    }
    
    func testOpenAIRequestTranslationTools() async throws {
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
            XCTAssertEqual(firstTool["type"] as? String, "function")
            
            guard let function = firstTool["function"] as? [String: Any] else {
                XCTFail("Missing function subfield in tool")
                return (HTTPURLResponse(), Data())
            }
            XCTAssertEqual(function["name"] as? String, "get_weather")
            XCTAssertEqual(function["description"] as? String, "Get the current weather")
            
            guard let parameters = function["parameters"] as? [String: Any] else {
                XCTFail("Missing parameters schema in tool function")
                return (HTTPURLResponse(), Data())
            }
            XCTAssertEqual(parameters["type"] as? String, "object")
            
            let responseJson: [String: Any] = [
                "id": "chatcmpl-002",
                "object": "chat.completion",
                "model": "gpt-4o",
                "choices": [
                    [
                        "index": 0,
                        "message": [
                            "role": "assistant",
                            "tool_calls": [
                                [
                                    "id": "call_get_weather_1",
                                    "type": "function",
                                    "function": [
                                        "name": "get_weather",
                                        "arguments": "{\"location\":\"Boston\"}"
                                    ]
                                ]
                            ]
                        ]
                    ]
                ],
                "usage": [
                    "prompt_tokens": 42,
                    "completion_tokens": 12,
                    "total_tokens": 54
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
        
        let response = try await OpenAIClient.generateContent(
            request: request,
            model: "gpt-4o",
            apiKey: "test-key-openai"
        )
        
        XCTAssertNotNil(response.candidates)
        XCTAssertEqual(response.candidates?.count, 1)
        let firstCandidate = response.candidates?[0]
        XCTAssertEqual(firstCandidate?.content?.parts.count, 1)
        let firstPart = firstCandidate?.content?.parts[0]
        XCTAssertNotNil(firstPart?.functionCall)
        XCTAssertEqual(firstPart?.functionCall?.name, "get_weather")
        XCTAssertEqual(firstPart?.functionCall?.args["location"], "Boston")
    }
    
    func testOpenAIErrorPropagation() async throws {
        let request = GeminiRequest(
            contents: [Content(role: "user", parts: [Part(text: "Hello", functionCall: nil, functionResponse: nil, thought_signature: nil, thoughtSignature: nil)])],
            systemInstruction: nil,
            tools: nil
        )
        
        MockURLProtocol.handler = { urlRequest in
            let httpResponse = HTTPURLResponse(
                url: urlRequest.url!,
                statusCode: 401,
                httpVersion: nil,
                headerFields: nil
            )!
            let errorJson = ["error": ["message": "Incorrect API key provided.", "type": "invalid_request_error"]]
            let responseData = try! JSONSerialization.data(withJSONObject: errorJson)
            return (httpResponse, responseData)
        }
        
        do {
            _ = try await OpenAIClient.generateContent(
                request: request,
                model: "gpt-4o",
                apiKey: "test-key-openai"
            )
            XCTFail("Expected an error to be thrown")
        } catch let error as APIError {
            XCTAssertTrue(error.localizedDescription.contains("OpenAI HTTP 401"))
            XCTAssertTrue(error.localizedDescription.contains("Incorrect API key provided."))
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }
}
