import Testing
import Foundation
@testable import iris

@Suite("ShippedSkills Tests")
struct ShippedSkillsTests {

    private func tempPaths() -> IrisPaths {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("iris-seed-\(UUID().uuidString)")
        return IrisPaths(root: root)
    }
    private func read(_ url: URL) -> String? { try? String(contentsOf: url, encoding: .utf8) }

    @Test("seeds the library skill and README when absent")
    func testSeedsWhenAbsent() {
        let p = tempPaths(); defer { try? FileManager.default.removeItem(at: p.root) }
        ShippedSkills.seed(into: p, librarySkill: "SKILL BODY", libraryReadme: "README BODY")
        #expect(read(p.skillsDir.appendingPathComponent("library/SKILL.md")) == "SKILL BODY")
        #expect(read(p.libraryDir.appendingPathComponent("README.md")) == "README BODY")
    }

    @Test("does not overwrite existing (bot-edited) files")
    func testIdempotentNonDestructive() {
        let p = tempPaths(); defer { try? FileManager.default.removeItem(at: p.root) }
        try? p.ensureDirectories()
        let skillDir = p.skillsDir.appendingPathComponent("library")
        try? FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
        try? "MY EDITS".write(to: skillDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try? "MY README".write(to: p.libraryDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        ShippedSkills.seed(into: p, librarySkill: "SHIPPED", libraryReadme: "SHIPPED README")

        #expect(read(skillDir.appendingPathComponent("SKILL.md")) == "MY EDITS")
        #expect(read(p.libraryDir.appendingPathComponent("README.md")) == "MY README")
    }

    @Test("bundled assets load and are non-empty")
    func testBundledAssetsLoad() {
        #expect(ShippedSkills.bundledText("library-SKILL").contains("Library Management"))
        #expect(ShippedSkills.bundledText("library-README").contains("Iris Library"))
    }
}
