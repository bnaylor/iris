import Testing
import Foundation
@testable import iris

@Suite("run_command intent")
struct RunCommandIntentTests {
    @Test("run_command schema exposes an optional intent property")
    func schemaHasOptionalIntent() async {
        let tools = await ToolExecutor.shared.getTools()
        let runCmd = tools.first { $0.name == "run_command" }
        #expect(runCmd != nil)
        #expect(runCmd?.parameters?.properties?["intent"] != nil)
        #expect(runCmd?.parameters?.required?.contains("intent") != true)
    }

    @Test("execute runs the command and ignores intent")
    func executeIgnoresIntent() async {
        let result = await ToolExecutor.shared.execute(
            name: "run_command",
            args: ["command": .string("echo transparency_ok"), "intent": .string("verifying")],
            useSandbox: false)
        #expect(result.contains("transparency_ok"))
    }
}
