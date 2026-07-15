import Testing
import Foundation
@testable import iris

@Suite("IrisPaths Tests")
struct IrisPathsTests {

    @Test("accessors compose paths under the injected root")
    func testAccessorsComposeUnderRoot() {
        let root = URL(fileURLWithPath: "/tmp/iris-test-root")
        let p = IrisPaths(root: root)
        #expect(p.memoryDir.path == "/tmp/iris-test-root/memory")
        #expect(p.soulMd.path == "/tmp/iris-test-root/memory/SOUL.md")
        #expect(p.userMd.path == "/tmp/iris-test-root/memory/USER.md")
        #expect(p.memoryMd.path == "/tmp/iris-test-root/memory/memory.md")
        #expect(p.skillsDir.path == "/tmp/iris-test-root/memory/skills")
        #expect(p.artifactsDir.path == "/tmp/iris-test-root/memory/artifacts")
        #expect(p.holographicDB.path == "/tmp/iris-test-root/memory/holographic_memory.sqlite")
        #expect(p.configDir.path == "/tmp/iris-test-root/config")
        #expect(p.settingsJSON.path == "/tmp/iris-test-root/config/settings.json")
        #expect(p.permissionsJSON.path == "/tmp/iris-test-root/config/permissions.json")
        #expect(p.mcpServersJSON.path == "/tmp/iris-test-root/config/mcp_servers.json")
        #expect(p.modelsDir.path == "/tmp/iris-test-root/models")
    }

    @Test("ensureDirectories creates the bucket directories")
    func testEnsureDirectoriesCreatesBuckets() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("iris-ensure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let p = IrisPaths(root: root)
        try p.ensureDirectories()
        for dir in [p.memoryDir, p.skillsDir, p.artifactsDir, p.configDir, p.modelsDir] {
            var isDir: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir))
            #expect(isDir.boolValue)
        }
    }
}
