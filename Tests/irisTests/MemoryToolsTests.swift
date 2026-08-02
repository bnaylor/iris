import Testing
import Foundation
@testable import iris

@Suite("Memory Tools Tests", .serialized)
struct MemoryToolsTests {

    private func withTempPaths(_ body: (IrisPaths) -> Void) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("iris-tools-\(UUID().uuidString)")
        let p = IrisPaths(root: root)
        try? p.ensureDirectories()
        let previous = MemoryManager.shared.paths
        MemoryManager.shared.paths = p
        defer { MemoryManager.shared.paths = previous; try? FileManager.default.removeItem(at: root) }
        body(p)
    }

    @Test("updateSoul writes memory/SOUL.md")
    func testUpdateSoul() {
        withTempPaths { p in
            MemoryManager.shared.updateSoul(content: "new soul")
            #expect((try? String(contentsOf: p.soulMd, encoding: .utf8)) == "new soul")
        }
    }

    @Test("updateMemory writes memory/memory.md")
    func testUpdateMemory() {
        withTempPaths { p in
            MemoryManager.shared.updateMemory(content: "new memory")
            #expect((try? String(contentsOf: p.memoryMd, encoding: .utf8)) == "new memory")
        }
    }

    @Test("updateUserProfile writes memory/USER.md")
    func testUpdateUserProfile() {
        withTempPaths { p in
            MemoryManager.shared.updateUserProfile(content: "new user")
            #expect((try? String(contentsOf: p.userMd, encoding: .utf8)) == "new user")
        }
    }
}
