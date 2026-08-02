import Testing
import Foundation
@testable import iris

@Suite("withTimeout")
struct TimeoutTests {
    @Test("fast operation returns its value")
    func fastReturns() async throws {
        let v = try await withTimeout(seconds: 2) { () -> Int in 42 }
        #expect(v == 42)
    }

    @Test("slow operation throws TimeoutError")
    func slowThrows() async {
        await #expect(throws: TimeoutError.self) {
            try await withTimeout(seconds: 0.05) { () -> Int in
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return 1
            }
        }
    }
}
