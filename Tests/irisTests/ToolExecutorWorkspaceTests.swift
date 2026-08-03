import Testing
import Foundation
@testable import iris

@Suite("ToolExecutor workspace path resolution")
struct ToolExecutorWorkspaceTests {

    @Test("resolvePath joins relative paths onto the workspace; leaves absolute and tilde alone")
    func resolve() {
        #expect(ToolExecutor.resolvePath("f.txt", cwd: "/ws") == "/ws/f.txt")
        #expect(ToolExecutor.resolvePath("a/b.txt", cwd: "/ws") == "/ws/a/b.txt")
        #expect(ToolExecutor.resolvePath("/abs/f.txt", cwd: "/ws") == "/abs/f.txt")   // absolute unchanged
        #expect(ToolExecutor.resolvePath("f.txt", cwd: nil) == "f.txt")               // no workspace → prior behavior
        let home = ("~/f.txt" as NSString).expandingTildeInPath
        #expect(ToolExecutor.resolvePath("~/f.txt", cwd: "/ws") == home)              // tilde expands to absolute
    }

    @Test("write_file + read_file with a relative path use the bound workspace, not the process cwd")
    func relativeWriteLandsInWorkspace() async throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("iris-ws-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let writeResult = await ToolExecutor.shared.execute(
            name: "write_file",
            args: ["path": .string("hangman.py"), "content": .string("print('hi')")],
            cwd: tmp.path
        )

        // It landed under the workspace, NOT the process working directory.
        let landed = tmp.appendingPathComponent("hangman.py").path
        #expect(FileManager.default.fileExists(atPath: landed))
        #expect(writeResult.contains(landed))
        #expect(!FileManager.default.fileExists(atPath: FileManager.default.currentDirectoryPath + "/hangman.py"))

        // read_file with the same relative path + workspace reads it back.
        let readResult = await ToolExecutor.shared.execute(
            name: "read_file",
            args: ["path": .string("hangman.py")],
            cwd: tmp.path
        )
        #expect(readResult.contains("print('hi')"))
    }

    @Test("register_directory_watcher with a relative path resolves against the bound workspace")
    func relativeWatcherResolvesToWorkspace() async {
        let result = await ToolExecutor.shared.execute(
            name: "register_directory_watcher",
            args: ["path": .string("src"), "instructions": .string("note changes")],
            cwd: "/ws"
        )
        // The confirmation echoes the resolved path — under the workspace, not the process cwd.
        #expect(result.contains("/ws/src"))
        #expect(!result.contains(FileManager.default.currentDirectoryPath + "/src"))
    }
}
