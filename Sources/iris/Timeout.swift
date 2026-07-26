import Foundation

struct TimeoutError: Error, Equatable {}

/// Runs `operation` with a wall-clock timeout. If it doesn't finish in `seconds`, throws
/// `TimeoutError` and cancels the operation (best-effort — a non-cooperative call may still run
/// to completion in the background, but its result is discarded).
func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        let result = try await group.next()!
        return result
    }
}
