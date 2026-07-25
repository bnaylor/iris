import Testing
import Foundation
@testable import iris

@Suite("PerformanceProfiler value types")
struct PerformanceProfilerValueTypeTests {

    @Test("CommandProfile.add accumulates ms and count per category")
    func addAccumulates() {
        var profile = CommandProfile(id: UUID(), label: "test", source: "UI", startedAt: Date())
        profile.add(.primaryLLM, durationMs: 100)
        profile.add(.primaryLLM, durationMs: 50)
        profile.add(.vibecop, durationMs: 30)

        #expect(profile.categories[.primaryLLM]?.ms == 150)
        #expect(profile.categories[.primaryLLM]?.count == 2)
        #expect(profile.categories[.vibecop]?.ms == 30)
        #expect(profile.categories[.vibecop]?.count == 1)
    }

    @Test("derivedOtherMs is total minus top-level phases, clamped at 0")
    func derivedOther() {
        var profile = CommandProfile(id: UUID(), label: "test", source: "UI", startedAt: Date())
        profile.totalMs = 1000
        profile.add(.primaryLLM, durationMs: 400)
        profile.add(.toolExecution, durationMs: 300)
        profile.add(.hooks, durationMs: 50)
        profile.add(.contextAssembly, durationMs: 50)
        // vibecop/injection are sub-measures of tool time and must NOT reduce Other
        profile.add(.vibecop, durationMs: 200)
        profile.add(.injectionGuard, durationMs: 100)

        #expect(profile.derivedOtherMs == 200) // 1000 - (400+300+50+50)
    }

    @Test("derivedOtherMs clamps to 0 when phases exceed total")
    func derivedOtherClamps() {
        var profile = CommandProfile(id: UUID(), label: "test", source: "UI", startedAt: Date())
        profile.totalMs = 100
        profile.add(.primaryLLM, durationMs: 400)
        #expect(profile.derivedOtherMs == 0)
    }

    @Test("guard categories are flagged as sub-measures")
    func guardFlag() {
        #expect(PerfCategory.vibecop.isGuardSubMeasure)
        #expect(PerfCategory.injectionGuard.isGuardSubMeasure)
        #expect(!PerfCategory.toolExecution.isGuardSubMeasure)
        #expect(!PerfCategory.primaryLLM.isGuardSubMeasure)
    }
}
