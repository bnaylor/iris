import Foundation

enum ContainerRuntimeError: Error, Equatable {
    case launchFailed(String)
    case createFailed(String)
}

/// Seam over the `container` CLI so `SandboxSessionManager` is unit-testable without a real VM.
protocol ContainerRuntime: Sendable {
    /// `container run -d --name <name> [-v <mount>] -w <workdir> <image> sleep infinity`
    func createDetached(name: String, image: String, mount: String?, workdir: String) async throws
    /// `container exec -w <workdir> <name> bash -c <command>`
    func exec(name: String, workdir: String, command: String) async throws -> (stdout: String, stderr: String, exitCode: Int32)
    /// `container stop <name>` then `container delete <name>` — best-effort, never throws.
    func remove(name: String) async
    /// Names of existing containers whose name starts with `prefix`.
    func list(prefix: String) async -> [String]
}

struct CLIContainerRuntime: ContainerRuntime {
    private let binary = "/usr/local/bin/container"

    private func runCLI(_ args: [String]) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        try await withCheckedThrowingContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: binary)
            p.arguments = args
            let out = Pipe(); let err = Pipe()
            p.standardOutput = out; p.standardError = err
            p.terminationHandler = { proc in
                let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                cont.resume(returning: (o, e, proc.terminationStatus))
            }
            do { try p.run() } catch { cont.resume(throwing: ContainerRuntimeError.launchFailed(error.localizedDescription)) }
        }
    }

    func createDetached(name: String, image: String, mount: String?, workdir: String) async throws {
        var args = ["run", "-d", "--name", name]
        if let mount { args += ["-v", mount] }
        args += ["-w", workdir, image, "sleep", "infinity"]
        let r = try await runCLI(args)
        if r.exitCode != 0 {
            throw ContainerRuntimeError.createFailed((r.stdout + r.stderr).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func exec(name: String, workdir: String, command: String) async throws -> (stdout: String, stderr: String, exitCode: Int32) {
        try await runCLI(["exec", "-w", workdir, name, "bash", "-c", command])
    }

    func remove(name: String) async {
        _ = try? await runCLI(["stop", name])
        _ = try? await runCLI(["delete", name])
    }

    func list(prefix: String) async -> [String] {
        guard let r = try? await runCLI(["list", "-a", "--format", "json"]),
              let data = r.stdout.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        // Each entry's identifier may be under "configuration.id" or top-level "id"/"name".
        return arr.compactMap { entry -> String? in
            if let id = entry["id"] as? String { return id }
            if let cfg = entry["configuration"] as? [String: Any], let id = cfg["id"] as? String { return id }
            return entry["name"] as? String
        }.filter { $0.hasPrefix(prefix) }
    }
}
