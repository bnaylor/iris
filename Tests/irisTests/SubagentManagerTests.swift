import XCTest
@testable import iris

@MainActor
final class SubagentManagerTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
        // Clear user defaults for clean state
        UserDefaults.standard.removeObject(forKey: "iris_conversations")
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
    
    func testSubagentExecutionBlocksAndReturnsSummary() async throws {
        // Setup AppState
        let state = AppState()
        SubagentManager.shared.setGlobalState(state)
        
        let lock = NSLock()
        var count = 0
        
        // Mock the LLM to instantly call `goal_complete`
        MockURLProtocol.handler = { request in
            lock.lock()
            let currentCount = count
            count += 1
            lock.unlock()
            
            let responseJson: [String: Any]
            if currentCount >= 1 {
                // Break the loop
                responseJson = [
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
                    "usage": [
                        "input_tokens": 10,
                        "output_tokens": 10
                    ]
                ]
            } else {
                responseJson = [
                    "id": UUID().uuidString,
                    "type": "message",
                    "role": "assistant",
                    "model": "claude-3-5-sonnet",
                    "content": [
                        [
                            "type": "tool_use",
                            "id": "call_1",
                            "name": "goal_complete",
                            "input": [
                                "summary": "I have audited the code securely."
                            ]
                        ]
                    ],
                    "usage": [
                        "input_tokens": 10,
                        "output_tokens": 10
                    ]
                ]
            }
            let responseData = try! JSONSerialization.data(withJSONObject: responseJson)
            let httpResponse = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (httpResponse, responseData)
        }
        
        let parentConversationId = UUID()
        await MainActor.run {
            state.createNewConversation(id: parentConversationId)
        }
        
        let summary = await SubagentManager.shared.runSubagent(
            role: "security_auditor",
            task: "Find vulnerabilities",
            effort: "easy",
            parentConversationId: parentConversationId
        )
        
        XCTAssertEqual(summary, "I have audited the code securely.")
    }
    
    func testConcurrentSubagentExecution() async throws {
        let state = AppState()
        SubagentManager.shared.setGlobalState(state)
        
        let lock = NSLock()
        var count = 0
        
        // Mock LLM to return a success message indicating concurrency test
        MockURLProtocol.handler = { request in
            lock.lock()
            let currentCount = count
            count += 1
            lock.unlock()
            
            let responseJson: [String: Any]
            if currentCount >= 5 {
                responseJson = [
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
            } else {
                responseJson = [
                    "id": UUID().uuidString,
                    "type": "message",
                    "role": "assistant",
                    "model": "claude-3-5-sonnet",
                    "content": [
                        [
                            "type": "tool_use",
                            "id": "call_2",
                            "name": "goal_complete",
                            "input": [
                                "summary": "Concurrent execution complete."
                            ]
                        ]
                    ],
                    "usage": ["input_tokens": 10, "output_tokens": 10]
                ]
            }
            let responseData = try! JSONSerialization.data(withJSONObject: responseJson)
            let httpResponse = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (httpResponse, responseData)
        }
        
        let parentConversationId = UUID()
        await MainActor.run {
            state.createNewConversation(id: parentConversationId)
        }
        
        // Run 5 subagents concurrently using the ResultHolder fix
        let results = await withTaskGroup(of: String.self) { group in
            for i in 0..<5 {
                group.addTask {
                    return await SubagentManager.shared.runSubagent(
                        role: "worker_\(i)",
                        task: "Task \(i)",
                        effort: "medium",
                        parentConversationId: parentConversationId
                    )
                }
            }
            
            var collected: [String] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }
        
        XCTAssertEqual(results.count, 5, "All 5 concurrent subagents should return successfully")
        for res in results {
            XCTAssertEqual(res, "Concurrent execution complete.")
        }
    }
}
