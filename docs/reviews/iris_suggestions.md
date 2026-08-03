### Iris
I completely agree with your analysis. You hit the nail on the head regarding both the security implications and the lifecycle management of autonomous subagents. 

Here is my expert breakdown of these two issues and how we can architect the **correct, production-grade solutions** for them in Iris.

---

### **Issue 1: The Security Risk of Bypassing Sandboxed Approvals**

While running inside a container (like `ubuntu:latest`) isolates the macOS host filesystem from direct mutation, a containerized execution still carries significant security risks if left completely unmonitored:
1. **Network Side-Channels & Exfiltration:** The sandbox shares the host's network bridge by default. A compromised model could scan your local network (`192.168.x.x`), access local network-attached storage (NAS), hit local development servers, or exfiltrate sensitive files (read via the main agent and passed to the subagent) to an external server.
2. **Container Escapes:** Modern container runtimes (Docker, Podman, Apple Virtualization Framework) have had escape vulnerabilities. Allowing a subagent to run arbitrary, unreviewed root exploits inside the container could lead to host takeover.
3. **Resource Exhaustion:** A subagent could spawn a cryptocurrency miner, run fork-bombs, or saturate host CPU/RAM resources.

#### **The Right Architectural Fix:**
Instead of bypassing approvals completely, we should **bubble subagent approval requests up to the user**, but with enhanced context:
* **Subagent Context in Approval Requests:** The `ToolApprovalRequest` struct and the UI `ApprovalBannerView` should be aware of the *principal* making the request (e.g., displaying **"Subagent (Engineer) wants to run: `uname -a`"** instead of making it look like the main agent requested it).
* **Robust Vibecop Auto-Approvals:** For routine developer commands (`git status`, `uname -a`, `ls`), Vibecop (running locally via Ollama) should auto-approve them in milliseconds, preventing manual friction. However, if Vibecop hangs, fails, or evaluates a sketchy command, it must immediately fall back to a user confirmation banner that clearly states which subagent is asking and why.

---

### **Issue 2: Subagents "Getting Stuck" / Deterministic Task Cancellation**

Currently, `SubagentManager.swift` has a 5-minute timeout loop, but this timeout only stops the *parent* conversation from waiting. The underlying subagent's `IrisEngine` processing task **continues to run in the background indefinitely** (suspended on a pending approval continuation or looping on its LLM turns). 

This is a major leak of resources and API tokens.

#### **The Right Architectural Fix:**
We need strict **cooperative cancellation** of subagent tasks:
1. **Store the Subagent Task:** Keep a reference to the active `Task` running `engine.processInput(...)` for each subagent.
2. **Cancel on Timeout:** If the 5-minute timeout fires, explicitly call `.cancel()` on that task.
3. **Handle Cancellation in the Engine:** The `IrisEngine.processInputBody` turn loop already checks `if Task.isCancelled { break }` at the turn boundary, but we should make sure it also cancels any pending API requests or tool executions, clears the active goal, and cleans up the sandbox container immediately.

---

### **What do you think?**

If this matches your vision, we can write a clean, robust patch to implement these exact behaviors:
1. **Re-enable approvals** for sandboxed tools.
2. **Thread the principal role/subagent status** into `ToolApprovalRequest` so the UI banner displays it beautifully.
3. **Ensure Vibecop failures fail-open to the user prompt quickly** (with a timeout on Vibecop itself so it never hangs the subagent).
4. **Implement robust task cancellation** for timed-out or cancelled subagents.

Let's discuss what Claude suggests as well, and we can make this incredibly secure and deterministic!


