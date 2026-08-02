import XCTest
@testable import iris

@MainActor
final class ParallelToolExecutionTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
        UserDefaults.standard.set("Anthropic", forKey: "PRIMARY_PROVIDER")
        UserDefaults.standard.set("claude-3-5-sonnet", forKey: "ANTHROPIC_MODEL_MEDIUM")
        ConfigManager.shared.primaryProvider = "Anthropic"
        ConfigManager.shared.anthropicModelMedium = "claude-3-5-sonnet"
        ConfigManager.shared.anthropicAPIKey = "mock-api-key"
    }
    
    override func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        MockURLProtocol.handler = nil
        super.tearDown()
    }
    
    func testParallelToolExecutionMaintainsOrder() async throws {
        // We will mock the LLM to return TWO tool calls in its first response.
        // We will then intercept the SECOND request (which contains the tool results)
        // and verify that the tool results are in the exact same order as the tool calls.
        
        let expectation = XCTestExpectation(description: "Second request contains ordered tool results")
        
        var count = 0
        let lock = NSLock()
        
        MockURLProtocol.handler = { request in
            lock.lock()
            let currentCount = count
            count += 1
            lock.unlock()
            
            if currentCount == 0 {
                // First request: return two tool calls
                let responseJson: [String: Any] = [
                    "id": UUID().uuidString,
                    "type": "message",
                    "role": "assistant",
                    "model": "claude-3-5-sonnet",
                    "content": [
                        [
                            "type": "tool_use",
                            "id": "call_1",
                            "name": "rename_conversation",
                            "input": [
                                "title": "Parallel Test 1"
                            ]
                        ],
                        [
                            "type": "tool_use",
                            "id": "call_2",
                            "name": "rename_conversation",
                            "input": [
                                "title": "Parallel Test 2"
                            ]
                        ]
                    ],
                    "usage": ["input_tokens": 10, "output_tokens": 10]
                ]
                let responseData = try! JSONSerialization.data(withJSONObject: responseJson)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, responseData)
            } else {
                // Second request: this should be the tool results being sent back to the LLM.
                // We must verify the order of the tool results in the request body.
                
                let bodyData = request.bodyData ?? Data()
                let bodyString = String(data: bodyData, encoding: .utf8) ?? ""
                
                // We expect "call_1" to appear BEFORE "call_2" in the body string!
                if let call1Index = bodyString.range(of: "call_1")?.lowerBound,
                   let call2Index = bodyString.range(of: "call_2")?.lowerBound {
                    XCTAssertTrue(call1Index < call2Index, "Tool results must maintain the order of the original tool calls")
                    expectation.fulfill()
                } else {
                    XCTFail("Could not find tool call IDs in the request body")
                }
                
                // Return a final Finished message
                let responseJson: [String: Any] = [
                    "id": UUID().uuidString,
                    "type": "message",
                    "role": "assistant",
                    "model": "claude-3-5-sonnet",
                    "content": [
                        [
                            "type": "text",
                            "text": "Finished."
                        ]
                    ],
                    "usage": ["input_tokens": 10, "output_tokens": 10]
                ]
                let responseData = try! JSONSerialization.data(withJSONObject: responseJson)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, responseData)
            }
        }
        
        let state = AppState()
        let convId = UUID()
        await MainActor.run {
            state.conversations.append(Conversation(id: convId, title: "Test", history: []))
        }
        SubagentManager.shared.setGlobalState(state)
        let engine = IrisEngine(state: state)
        await engine.processInput("Do the parallel test", source: "User", conversationId: convId)
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }
}
