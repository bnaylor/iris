import Foundation
import Cocoa
import CryptoKit

final class SandboxingManager: @unchecked Sendable {
    static let shared = SandboxingManager()
    
    private init() {}
    
    var isContainerInstalled: Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["container"]
        
        // Also check /usr/local/bin/container since which might not pick it up if not in path
        if FileManager.default.fileExists(atPath: "/usr/local/bin/container") {
            return true
        }
        
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    func installContainer(completion: @escaping @MainActor (Bool, String?) -> Void) {
        Task {
            do {
                // Fetch the latest release pkg
                let urlString = "https://github.com/apple/container/releases/download/1.1.0/container-1.1.0-installer-signed.pkg"
                guard let url = URL(string: urlString) else {
                    await completion(false, "Invalid URL")
                    return
                }
                
                let pkgPath = "/tmp/container-installer.pkg"
                let (data, _) = try await URLSession.shared.data(from: url)
                
                let expectedHash = "0ca1c42a2269c2557efb1d82b1b38ac553e6a3a3da1b1179c439bcee1e7d6714"
                let actualHash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
                
                guard actualHash == expectedHash else {
                    await completion(false, "Security Error: Downloaded PKG hash mismatch. Expected: \(expectedHash), Got: \(actualHash)")
                    return
                }
                
                try data.write(to: URL(fileURLWithPath: pkgPath))
                
                // We use AppleScript to prompt for privileges to install the PKG
                let scriptSource = """
                do shell script "installer -pkg /tmp/container-installer.pkg -target / && /usr/local/bin/container system start" with administrator privileges
                """
                
                var error: NSDictionary?
                if let script = NSAppleScript(source: scriptSource) {
                    _ = script.executeAndReturnError(&error)
                    await MainActor.run {
                        if error != nil {
                            completion(false, "Installation failed or was cancelled.")
                        } else {
                            completion(true, nil)
                        }
                    }
                } else {
                    await completion(false, "Failed to create AppleScript.")
                }
            } catch {
                await completion(false, error.localizedDescription)
            }
        }
    }
}
