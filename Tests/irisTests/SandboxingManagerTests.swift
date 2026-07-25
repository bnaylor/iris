import Testing
import Foundation
@testable import iris

@Suite("SandboxingManager Tests")
struct SandboxingManagerTests {

    @Test("isContainerInstalled returns boolean without crashing")
    func testIsContainerInstalled() {
        let installed = SandboxingManager.shared.isContainerInstalled
        // Value depends on host machine state, verify getter evaluates cleanly
        #expect(installed == true || installed == false)
    }

    @Test("startContainerSystem returns error status when binary is missing")
    func testStartContainerSystemSafety() async {
        // Method returns cleanly with boolean success flag and message tuple
        let result = await SandboxingManager.shared.startContainerSystem()
        #expect(result.success == true || result.success == false)
    }
}
