import Testing
import Foundation
@testable import iris

@Suite("SystemSteering Tests")
struct SystemSteeringTests {

    @Test("shipped() loads the bundled SYSTEM.md with its key sections")
    func testShippedLoadsBundledSystemMd() {
        let steering = SystemSteering.shipped()
        #expect(!steering.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(steering.contains("Operating Context"))
        #expect(steering.contains("Workspace Conventions"))
        #expect(steering.contains("untrusted_context"))
        #expect(steering.contains("OKF"))
    }

    @Test("fallback still carries the security posture")
    func testFallbackCarriesSecurityPosture() {
        #expect(SystemSteering.fallback.contains("Operating Context"))
        #expect(SystemSteering.fallback.contains("untrusted_context"))
        #expect(SystemSteering.fallback.contains("authorization"))
    }
}
