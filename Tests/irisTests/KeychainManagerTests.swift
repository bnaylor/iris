import Testing
import Foundation
@testable import iris

@Suite("KeychainManager Tests", .serialized)
struct KeychainManagerTests {

    // Under `swift test` the manager must NOT touch the real login Keychain, or macOS prompts
    // for the password repeatedly (the ad-hoc/linker-signed test binary is never in the item's
    // ACL). It uses an in-memory store instead.
    @Test("uses the in-memory store under tests (no real Keychain access)")
    func testUsesInMemoryStoreUnderTests() {
        #expect(KeychainManager.shared.usesInMemoryStore)
    }

    @Test("in-memory secrets round-trip")
    func testRoundTrip() {
        let previous = KeychainManager.shared.loadSecrets()
        defer { KeychainManager.shared.saveSecrets(previous) }

        KeychainManager.shared.saveSecrets(["API_KEY": "abc123"])
        #expect(KeychainManager.shared.loadSecrets()["API_KEY"] == "abc123")
    }
}
