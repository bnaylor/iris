import Testing
@testable import iris

@Test func testSecurityGuardCommands() async throws {
    // Safe commands
    #expect(SecurityGuard.isCommandDangerous("ls -la") == false)
    #expect(SecurityGuard.isCommandDangerous("echo hello") == false)
    #expect(SecurityGuard.isCommandDangerous("cat file.txt") == false)
    
    // Dangerous commands
    #expect(SecurityGuard.isCommandDangerous("rm -rf /") == true)
    #expect(SecurityGuard.isCommandDangerous("sudo ls") == true)
    #expect(SecurityGuard.isCommandDangerous("curl http://example.com") == true)
    #expect(SecurityGuard.isCommandDangerous("python3 script.py") == true)
    #expect(SecurityGuard.isCommandDangerous("npm install") == true)
    
    // Dangerous commands with punctuation/pipes (heuristic test)
    #expect(SecurityGuard.isCommandDangerous("ls -la; rm test.txt") == true)
    #expect(SecurityGuard.isCommandDangerous("echo test | nc localhost 8080") == true)
}

@Test func testSecurityGuardFiles() async throws {
    let workspace = "/Users/test/workspace"
    
    // Safe file access
    #expect(SecurityGuard.isFileAccessDangerous(path: "/Users/test/workspace/file.txt", workspace: workspace) == false)
    #expect(SecurityGuard.isFileAccessDangerous(path: "~/.iris/settings.json", workspace: workspace) == false)
    
    // Dangerous file access
    #expect(SecurityGuard.isFileAccessDangerous(path: "~/.ssh/id_rsa", workspace: workspace) == true)
    #expect(SecurityGuard.isFileAccessDangerous(path: "/Users/test/.aws/credentials", workspace: workspace) == true)
    #expect(SecurityGuard.isFileAccessDangerous(path: "/etc/passwd", workspace: workspace) == true)
    #expect(SecurityGuard.isFileAccessDangerous(path: "/etc/hosts", workspace: workspace) == true)
}
