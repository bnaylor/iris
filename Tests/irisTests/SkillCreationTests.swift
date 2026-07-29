import Testing
import Foundation
@testable import iris

@Suite("SkillCreation Tests")
struct SkillCreationTests {

    @Test("createSkill creates directory, SKILL.md with OKF frontmatter, and body")
    func testCreateSkill() async throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("iris-skill-test-\(UUID().uuidString)")
        let paths = IrisPaths(root: tempRoot)
        try paths.ensureDirectories()

        let skillName = "gke-debug-routine"
        let skillDesc = "Debug stuck GKE worker nodes"
        let skillBody = """
        # Steps
        1. Run `kubectl get nodes`
        2. Check `journalctl -u kubelet`
        """

        let result = await ToolExecutor.shared.createSkill(
            name: skillName,
            description: skillDesc,
            body: skillBody,
            paths: paths
        )

        #expect(result.contains("Successfully saved skill"))

        let skillFile = paths.skillsDir.appendingPathComponent("gke-debug-routine/SKILL.md")
        #expect(FileManager.default.fileExists(atPath: skillFile.path))

        let content = try String(contentsOf: skillFile, encoding: .utf8)
        #expect(content.contains("name: gke-debug-routine"))
        #expect(content.contains("description: Debug stuck GKE worker nodes"))
        #expect(content.contains("type: skill"))
        #expect(content.contains("journalctl -u kubelet"))

        // Verify SkillManager discovers the new skill
        let skills = await SkillManager.shared.listSkills(paths: paths)
        #expect(skills.count == 1)
        #expect(skills.first?.name == "gke-debug-routine")
        #expect(skills.first?.description == skillDesc)
    }

    @Test("deleteSkill removes skill directory and file")
    func testDeleteSkill() async throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("iris-skill-delete-\(UUID().uuidString)")
        let paths = IrisPaths(root: tempRoot)
        try paths.ensureDirectories()

        _ = await ToolExecutor.shared.createSkill(
            name: "temp-skill",
            description: "Temporary skill to delete",
            body: "Delete me",
            paths: paths
        )

        let deleteResult = await ToolExecutor.shared.deleteSkill(name: "temp-skill", paths: paths)
        #expect(deleteResult.contains("Successfully deleted skill"))

        let skillFolder = paths.skillsDir.appendingPathComponent("temp-skill")
        #expect(!FileManager.default.fileExists(atPath: skillFolder.path))
    }

    @Test("updateSkill modifies body/description while preserving skill name")
    func testUpdateSkill() async throws {
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("iris-skill-update-\(UUID().uuidString)")
        let paths = IrisPaths(root: tempRoot)
        try paths.ensureDirectories()

        _ = await ToolExecutor.shared.createSkill(
            name: "k8s-pod-debug",
            description: "Initial description",
            body: "Original body",
            paths: paths
        )

        let updateResult = await ToolExecutor.shared.updateSkill(
            name: "k8s-pod-debug",
            description: "Updated description",
            body: "Updated body content with new steps",
            paths: paths
        )

        #expect(updateResult.contains("Successfully updated skill"))

        let skillFile = paths.skillsDir.appendingPathComponent("k8s-pod-debug/SKILL.md")
        let content = try String(contentsOf: skillFile, encoding: .utf8)
        #expect(content.contains("description: Updated description"))
        #expect(content.contains("Updated body content with new steps"))
    }
}
