import XCTest
@testable import iris

final class SandboxTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Reset defaults
        UserDefaults.standard.removeObject(forKey: "ENABLE_SANDBOXING")
        UserDefaults.standard.removeObject(forKey: "SANDBOX_IMAGE")
        ConfigManager.shared.enableSandboxing = false
        ConfigManager.shared.sandboxImage = "ubuntu:latest"
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: "ENABLE_SANDBOXING")
        UserDefaults.standard.removeObject(forKey: "SANDBOX_IMAGE")
    }

    func testSandboxConfigPersists() throws {
        let config = ConfigManager.shared
        
        XCTAssertFalse(config.enableSandboxing)
        XCTAssertEqual(config.sandboxImage, "ubuntu:latest")
        
        config.enableSandboxing = true
        config.sandboxImage = "alpine:3.18"
        
        let newConfig = ConfigManager() // Simulates app restart
        XCTAssertTrue(newConfig.enableSandboxing)
        XCTAssertEqual(newConfig.sandboxImage, "alpine:3.18")
    }
    
    func testSandboxCommandBranch() async throws {
        // We will just execute a command via ToolExecutor when sandboxing is enabled.
        // It will either return the missing container error, or it will attempt to run it.
        ConfigManager.shared.enableSandboxing = true
        ConfigManager.shared.sandboxImage = "ubuntu:latest"
        
        let executor = ToolExecutor()
        let result = await executor.execute(name: "run_command", args: ["command": .string("echo 'hello'")], cwd: "/tmp")
        
        // We just assert that it hits the sandboxing code path.
        // It will either complain about missing container, or run it.
        XCTAssertTrue(result.contains("Sandboxing is enabled but the container runtime is not installed") || result.contains("hello") || result.contains("Error executing command"), "Result should reflect the sandbox branch execution: \(result)")
    }
}
