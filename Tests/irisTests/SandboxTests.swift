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
    
    func testSandboxingManagerCheck() throws {
        // We cannot guarantee the runner has 'container' installed, but we can verify it doesn't crash
        let isInstalled = SandboxingManager.shared.isContainerInstalled
        print("Container installed on this system: \(isInstalled)")
    }
}
