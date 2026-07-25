import Foundation

/// Owns one long-lived container per conversation. Commands run via `container exec`; disk state
/// persists within a session. An `actor` so concurrent tool calls serialize and lazy creation
/// happens exactly once.
actor SandboxSessionManager {
    static let namePrefix = "iris-"

    struct Session { let name: String; var mountedWorkspace: String?; var lastUsed: Date }

    private let runtime: ContainerRuntime
    private let image: @Sendable () -> String
    private var sessions: [UUID: Session] = [:]
    /// Conversations whose container was lost (idle-reaped or died mid-session). The next `run`
    /// recreates and prefixes a reset notice, distinguishing an unexpected reset from a cold start.
    private var lostSessions: Set<UUID> = []

    static let shared = SandboxSessionManager(runtime: CLIContainerRuntime(),
                                              image: { ConfigManager.shared.sandboxImage })

    init(runtime: ContainerRuntime, image: @escaping @Sendable () -> String) {
        self.runtime = runtime
        self.image = image
    }

    func hasSession(_ id: UUID) -> Bool { sessions[id] != nil }

    private func name(for id: UUID) -> String { "\(Self.namePrefix)\(id.uuidString.lowercased())" }

    private static let resetNotice = """
    [sandbox] This session's container was reclaimed after being idle; previously installed \
    packages and temp files were cleared (your workspace files on disk are untouched). Re-run any \
    setup (installs/builds) before relying on them.
    """

    func run(command: String, conversationId id: UUID, workspace: String?) async -> String {
        let wasLost = lostSessions.contains(id)
        var created = false

        // Recreate if the workspace changed (agent-initiated — not a "loss").
        if let s = sessions[id], s.mountedWorkspace != workspace {
            await runtime.remove(name: s.name)
            sessions[id] = nil
        }

        if sessions[id] == nil {
            do { try await create(id, workspace: workspace); created = true }
            catch { return creationError(error) }
        }

        let workdir = workspace ?? "/"
        do {
            let r = try await runtime.exec(name: name(for: id), workdir: workdir, command: command)
            sessions[id]?.lastUsed = Date()
            return decorate(format(r), notice: wasLost && created, for: id)
        } catch {
            // Container likely died/was reaped: mark lost, recreate once, retry.
            lostSessions.insert(id)
            await runtime.remove(name: name(for: id))
            sessions[id] = nil
            do {
                try await create(id, workspace: workspace)
                let r = try await runtime.exec(name: name(for: id), workdir: workdir, command: command)
                sessions[id]?.lastUsed = Date()
                return decorate(format(r), notice: true, for: id)
            } catch {
                return "Error executing sandboxed command: \(error)"
            }
        }
    }

    func endSession(_ id: UUID) async {
        if let s = sessions[id] { await runtime.remove(name: s.name) }
        sessions[id] = nil
        lostSessions.remove(id)
    }

    func endAll() async {
        for (_, s) in sessions { await runtime.remove(name: s.name) }
        sessions.removeAll()
    }

    func reapOrphans() async {
        for n in await runtime.list(prefix: Self.namePrefix) { await runtime.remove(name: n) }
    }

    func reapIdle(olderThan seconds: TimeInterval, now: Date = Date()) async {
        for (id, s) in sessions where now.timeIntervalSince(s.lastUsed) > seconds {
            await runtime.remove(name: s.name)
            sessions[id] = nil
            lostSessions.insert(id)
        }
    }

    // MARK: - Helpers

    private func create(_ id: UUID, workspace: String?) async throws {
        let mount = workspace.map { "\($0):\($0)" }
        try await runtime.createDetached(name: name(for: id), image: image(),
                                         mount: mount, workdir: workspace ?? "/")
        sessions[id] = Session(name: name(for: id), mountedWorkspace: workspace, lastUsed: Date())
    }

    private func format(_ r: (stdout: String, stderr: String, exitCode: Int32)) -> String {
        var result = r.stdout
        if !r.stderr.isEmpty { result += "\nStderr: " + r.stderr }
        if r.exitCode != 0, let hint = ToolExecutor.sandboxSetupHint(for: result) { return hint }
        return result.isEmpty ? "Success" : result
    }

    private func decorate(_ output: String, notice: Bool, for id: UUID) -> String {
        guard notice else { return output }
        lostSessions.remove(id)
        return Self.resetNotice + "\n\n" + output
    }

    private func creationError(_ error: Error) -> String {
        if case ContainerRuntimeError.createFailed(let msg) = error,
           let hint = ToolExecutor.sandboxSetupHint(for: msg) {
            return hint
        }
        return "Error: could not start the sandbox container: \(error)"
    }
}
