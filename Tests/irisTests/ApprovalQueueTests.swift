import Testing
import Foundation
@testable import iris

@MainActor
@Suite("Approval queue")
struct ApprovalQueueTests {
    @Test("resolveApproval resolves the FIFO head; deny then approve")
    func fifoResolve() async {
        let app = AppState()
        let cid = UUID()
        async let r1 = app.enqueueUserApproval(toolName: "run_command", details: "a", workspace: nil, conversationId: cid, origin: "Main agent")
        async let r2 = app.enqueueUserApproval(toolName: "run_command", details: "b", workspace: nil, conversationId: cid, origin: "Main agent")
        // Let both enqueue.
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(app.pendingApprovals.count == 2)
        app.resolveApproval(.deny)     // head (a) denied
        app.resolveApproval(.approve)  // next (b) approved
        let v1 = await r1
        let v2 = await r2
        #expect(v1 == false)
        #expect(v2 == true)
        #expect(app.pendingApprovals.isEmpty)
    }

    @Test("denyPendingApprovals denies only the matching conversation")
    func denyByConversation() async {
        let app = AppState()
        let a = UUID(); let b = UUID()
        async let ra = app.enqueueUserApproval(toolName: "t", details: "a", workspace: nil, conversationId: a, origin: "Subagent (x)")
        async let rb = app.enqueueUserApproval(toolName: "t", details: "b", workspace: nil, conversationId: b, origin: "Main agent")
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(app.pendingApprovals.count == 2)
        app.denyPendingApprovals(for: a)
        let va = await ra
        #expect(va == false)
        #expect(app.pendingApprovals.count == 1)
        #expect(app.pendingApprovals.first?.conversationId == b)
        app.resolveApproval(.approve)
        let vb = await rb
        #expect(vb == true)
    }
}
