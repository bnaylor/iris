import Foundation

/// Lightweight helper for running `gcloud` CLI commands relevant to the
/// Google Workspace OAuth setup flow.
enum GCloudHelper {
    
    struct APIInfo: Identifiable {
        let id: String           // gcloud service name, e.g. "calendar-json.googleapis.com"
        let displayName: String  // human-readable, e.g. "Google Calendar"
        let scope: String        // OAuth scope, e.g. "https://www.googleapis.com/auth/calendar"
        var enabled: Bool
    }
    
    /// The seven APIs required by the Google Workspace integration.
    static let requiredAPIs: [APIInfo] = [
        APIInfo(id: "calendar-json.googleapis.com", displayName: "Google Calendar", scope: "https://www.googleapis.com/auth/calendar", enabled: false),
        APIInfo(id: "people.googleapis.com",        displayName: "Google People",  scope: "https://www.googleapis.com/auth/userinfo.email", enabled: false),
        APIInfo(id: "drive.googleapis.com",          displayName: "Google Drive",   scope: "https://www.googleapis.com/auth/drive", enabled: false),
        APIInfo(id: "docs.googleapis.com",           displayName: "Google Docs",    scope: "https://www.googleapis.com/auth/documents", enabled: false),
        APIInfo(id: "sheets.googleapis.com",         displayName: "Google Sheets",  scope: "https://www.googleapis.com/auth/spreadsheets", enabled: false),
        APIInfo(id: "gmail.googleapis.com",          displayName: "Gmail",          scope: "https://www.googleapis.com/auth/gmail.modify", enabled: false),
        APIInfo(id: "tasks.googleapis.com",          displayName: "Google Tasks",   scope: "https://www.googleapis.com/auth/tasks", enabled: false),
    ]
    
    // MARK: - Availability & auth
    
    /// Returns true if `gcloud` is on PATH.
    static var isAvailable: Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["which", "gcloud"]
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = Pipe()
        do { try task.run(); task.waitUntilExit() } catch { return false }
        return task.terminationStatus == 0
    }
    
    /// Returns the authenticated account email, or nil.
    static func activeAccount() -> String? {
        run("auth", "list", "--format=value(account)", "--filter=status:ACTIVE")
    }
    
    /// Returns the current GCP project ID, or nil.
    static func currentProject() -> String? {
        run("config", "get-value", "project")
    }
    
    // MARK: - API enablement
    
    /// Returns the list of enabled service names.
    static func enabledServices() -> Set<String> {
        guard let raw = run("services", "list", "--enabled", "--format=value(config.name)") else {
            return []
        }
        return Set(raw.components(separatedBy: .newlines).filter { !$0.isEmpty })
    }
    
    /// Enables a single API. Returns true on success.
    @discardableResult
    static func enableAPI(_ serviceName: String) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
                task.arguments = ["gcloud", "services", "enable", serviceName, "--quiet"]
                task.standardOutput = Pipe()
                task.standardError = Pipe()
                do {
                    try task.run()
                    task.waitUntilExit()
                } catch {
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: task.terminationStatus == 0)
            }
        }
    }
    
    // MARK: - Internal
    
    private static func run(_ args: String...) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["gcloud"] + args
        let pipe = Pipe(); task.standardOutput = pipe; task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return nil
        }
        guard task.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return output?.isEmpty == true ? nil : output
    }
}
