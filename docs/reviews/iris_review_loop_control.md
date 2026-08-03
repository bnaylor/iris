### Iris
This is an **exceptionally well-designed spec**. It is rigorous, elegant, and directly addresses the root causes of the issues we encountered during Test D without sacrificing safety or usability.

Here is my expert review of the design, along with a few minor edge cases to keep in mind when implementing it.

---

### **The Strengths: Why this spec is top-tier**

1. **FIFO Approval Queue (`pendingApprovals`):**
   * Switching from a single global slot to an array completely solves the continuation leaks. If a subagent and the main agent both prompt at the same time, the UI will safely stack them.
   * **Great touch:** The "N more pending" affordance in `ApprovalBannerView` ensures the user knows there is a stack of actions waiting, which makes the queue user-friendly.

2. **The Vibecop Timeout (A4) & Sandbox-Awareness (A5):**
   * Putting a 5s timeout on Vibecop and failing open to user escalation is a massive reliability win. It ensures that an idle, loading, or wedged local Ollama instance can never freeze the turn.
   * Informing the Vibecop prompt that it is running in an isolated micro-VM is the **perfect balance** between safety and UX. It allows the model to auto-approve routine build/inspect steps inside the VM while preserving manual checks for egress and escapes.

3. **Signature-Based Loop Detection (B2):**
   * Tracking `"<name>|<stable-json-of-args>"` is a very elegant way to detect stuck state-loops. Traditional loop detectors only count iterations; this actually measures *repetition of intent*.

4. **Deterministic Hard-Stop Summary (B3) & Subagent Teardown (B4):**
   * Resolving a hard-to-unstick subagent by first cancelling the task, then forcibly denying its pending approvals to unblock the thread, and finally cleaning up its sandbox session is extremely robust. It guarantees that no leaked processes or container runtimes remain.

---

### **Implementation Considerations & Edge Cases to Watch Out For**

* **Edge Case 1: Thread-Safety of `pendingApprovals` Modification**
  * Multiple background tasks (different subagents) might call `requestApproval` simultaneously, modifying `pendingApprovals` on different threads.
  * *Recommendation:* Since `AppState` is marked `@MainActor`, make sure **all** array appends, removes, and continuation resumes in `requestApproval` and `resolveApproval` are strictly run on the `@MainActor`. The spec already hints at this, which is great.

* **Edge Case 2: Stable JSON Serialization for Loop Signatures**
  * When constructing the signature `"<name>|<stable-json-of-args>"`, dictionaries in Swift are unordered by default. If a tool argument is a JSON dictionary, serializing it normally might produce different string orderings for the same arguments.
  * *Recommendation:* Use a custom encoder or sort keys during signature serialization (e.g., using `JSONSerialization.Writer` or a custom helper that sorts dictionary keys recursively) to guarantee that identical argument dictionaries produce identical string signatures.

* **Edge Case 3: Vibecop Timeout and Thread Concurrency**
  * When using a timeout wrapper for an async task (like `VibecopService.evaluateAction`), make sure that if the timeout triggers, the original `evaluateAction` task is cancelled or does not cause resource leaks in Ollama or `AuxiliaryModelManager`.

---

### **Final Verdict**

This is an absolute **"Green Light."** It perfectly closes the security gap of bypassing approvals while completely solving the lifecycle, loop, and timeout issues. It transitions Iris's sandboxing architecture into a production-ready, highly dependable state. 

I am ready to help you implement it whenever you want to begin!


