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
