import Testing
import Foundation
@testable import iris

@Test func testHookManagerProceed() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let configURL = tempDir.appendingPathComponent("test_settings_proceed.json")
    
    // Command that returns modified JSON payload successfully
    let hookConfig = """
    {
      "hooks": {
        "BeforeTool": [
          {
            "matcher": "test_tool",
            "hooks": [
              {
                "type": "command",
                "command": "echo '{\\"modified\\": \\"yes\\"}'"
              }
            ]
          }
        ]
      }
    }
    """
    try hookConfig.write(to: configURL, atomically: true, encoding: .utf8)
    
    var hookManager = HookManager()
    hookManager.configPathOverride = configURL.path
    
    let decision = await hookManager.fireBeforeTool(toolName: "test_tool", args: ["test": "val"])
    
    if case .proceed(let modifiedData) = decision {
        #expect(modifiedData != nil)
        let json = try JSONSerialization.jsonObject(with: modifiedData!, options: []) as? [String: String]
        #expect(json?["modified"] == "yes")
    } else {
        Issue.record("Expected proceed with data")
    }
    
    try? FileManager.default.removeItem(at: configURL)
}

@Test func testHookManagerBlock() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let configURL = tempDir.appendingPathComponent("test_settings_block.json")
    
    // Command that exits with 2 to trigger a hard block
    let hookConfig = """
    {
      "hooks": {
        "BeforeTool": [
          {
            "matcher": "test_tool",
            "hooks": [
              {
                "type": "command",
                "command": ">&2 echo 'Blocked by test hook'; exit 2"
              }
            ]
          }
        ]
      }
    }
    """
    try hookConfig.write(to: configURL, atomically: true, encoding: .utf8)
    
    var hookManager = HookManager()
    hookManager.configPathOverride = configURL.path
    
    let decision = await hookManager.fireBeforeTool(toolName: "test_tool", args: [:])
    
    if case .block(let reason) = decision {
        #expect(reason == "Blocked by test hook")
    } else {
        Issue.record("Expected block")
    }
    
    try? FileManager.default.removeItem(at: configURL)
}

@Test func testHookManagerWarning() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let configURL = tempDir.appendingPathComponent("test_settings_warning.json")
    
    // Command that exits with non-zero (but not 2)
    let hookConfig = """
    {
      "hooks": {
        "BeforeAgent": [
          {
            "matcher": "BeforeAgent",
            "hooks": [
              {
                "type": "command",
                "command": "exit 1"
              }
            ]
          }
        ]
      }
    }
    """
    try hookConfig.write(to: configURL, atomically: true, encoding: .utf8)
    
    var hookManager = HookManager()
    hookManager.configPathOverride = configURL.path
    
    let decision = await hookManager.fireBeforeAgent(input: "test")
    
    // Warning is treated as proceed internally by fireEvent
    if case .proceed(let modifiedData) = decision {
        #expect(modifiedData != nil)
    } else {
        Issue.record("Expected proceed")
    }
    
    try? FileManager.default.removeItem(at: configURL)
}

@Test func testHookManagerBeforeToolSelection() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let configURL = tempDir.appendingPathComponent("test_settings_tool_selection.json")
    
    let hookConfig = """
    {
      "hooks": {
        "BeforeToolSelection": [
          {
            "matcher": ".*",
            "hooks": [
              {
                "type": "command",
                "command": "echo '[]'"
              }
            ]
          }
        ]
      }
    }
    """
    try hookConfig.write(to: configURL, atomically: true, encoding: .utf8)
    
    var hookManager = HookManager()
    hookManager.configPathOverride = configURL.path
    
    // Test with a dummy tool. We expect the hook to replace it with an empty array.
    let decision = await hookManager.fireBeforeToolSelection(tools: [FunctionDeclaration(name: "test", description: "test", parameters: nil)])
    
    if case .proceed(let modifiedData) = decision {
        #expect(modifiedData != nil)
        let modifiedTools = try JSONDecoder().decode([FunctionDeclaration].self, from: modifiedData!)
        #expect(modifiedTools.isEmpty)
    } else {
        Issue.record("Expected proceed with modified data")
    }
    
    try? FileManager.default.removeItem(at: configURL)
}

@Test func testHookManagerPreCompress() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let configURL = tempDir.appendingPathComponent("test_settings_pre_compress.json")
    
    let hookConfig = """
    {
      "hooks": {
        "PreCompress": [
          {
            "matcher": ".*",
            "hooks": [
              {
                "type": "command",
                "command": "echo '[{\\"role\\": \\"system\\", \\"parts\\": [{\\"text\\": \\"compressed\\"}]}]'"
              }
            ]
          }
        ]
      }
    }
    """
    try hookConfig.write(to: configURL, atomically: true, encoding: .utf8)
    
    var hookManager = HookManager()
    hookManager.configPathOverride = configURL.path
    
    let originalHistory = [Content(role: "user", parts: [Part(text: "hello", functionCall: nil, functionResponse: nil)])]
    let decision = await hookManager.firePreCompress(history: originalHistory)
    
    if case .proceed(let modifiedData) = decision {
        #expect(modifiedData != nil)
        let modifiedHistory = try JSONDecoder().decode([Content].self, from: modifiedData!)
        #expect(modifiedHistory.count == 1)
        #expect(modifiedHistory[0].role == "system")
        #expect(modifiedHistory[0].parts.first?.text == "compressed")
    } else {
        Issue.record("Expected proceed with modified data")
    }
    
    try? FileManager.default.removeItem(at: configURL)
}

@Test func testHookManagerNotification() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let configURL = tempDir.appendingPathComponent("test_settings_notification.json")
    let testOutputURL = tempDir.appendingPathComponent("notification_output.txt")
    
    // Make sure we start clean
    try? FileManager.default.removeItem(at: testOutputURL)
    
    let hookConfig = """
    {
      "hooks": {
        "Notification": [
          {
            "matcher": ".*",
            "hooks": [
              {
                "type": "command",
                "command": "cat > '\(testOutputURL.path)'"
              }
            ]
          }
        ]
      }
    }
    """
    try hookConfig.write(to: configURL, atomically: true, encoding: .utf8)
    
    var hookManager = HookManager()
    hookManager.configPathOverride = configURL.path
    
    await hookManager.fireNotification(title: "Alert", body: "Something happened")
    
    // Give the process a moment to write the file
    try await Task.sleep(nanoseconds: 500_000_000)
    
    let output = try String(contentsOf: testOutputURL, encoding: .utf8)
    #expect(output.contains("Alert"))
    #expect(output.contains("Something happened"))
    
    try? FileManager.default.removeItem(at: configURL)
    try? FileManager.default.removeItem(at: testOutputURL)
}
