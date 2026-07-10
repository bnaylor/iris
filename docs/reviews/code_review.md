# Code Review: Iris Harness Swift Concurrency

I reviewed the current codebase utilizing the `Swift-Concurrency-Agent-Skill`. I've found a few significant concurrency violations that are classic "gotchas" in modern Swift. 

## 1. Concurrency Pool Starvation via `readLine()`
**File:** `iris.swift` (Lines 79-86)
**Issue:** We spawn a `Task.detached` that runs an infinite `while let line = readLine()` loop. `readLine()` is a blocking C-level call. Because Swift Concurrency uses a fixed-size cooperative thread pool (one thread per CPU core), permanently blocking one of these threads just to wait for user input starves the system.
**Fix:** Since we set our minimum target to macOS 12, we can completely delete that detached task and use the native, non-blocking `AsyncSequence` provided by Foundation: 
`for try await line in FileHandle.standardInput.bytes.lines { ... }`

## 2. Actor Thread Blocking via `Process.waitUntilExit()`
**File:** `ToolExecutor.swift` (Lines 71, 43) & `iris.swift` (Line 38)
**Issue:** `ToolExecutor.execute()` is a synchronous function. When it calls `runCommand()`, it uses `process.waitUntilExit()`. Because it is called directly from `IrisEngine` (an `actor`), this synchronously blocks the actor's execution thread while the bash command runs. If a bash command takes 10 seconds, that thread in the cooperative pool is paralyzed for 10 seconds.
**Fix:** 
1. Make `ToolExecutor.execute()` an `async` function.
2. Refactor `runCommand()` to use `withCheckedContinuation` and `process.terminationHandler` to suspend the function instead of blocking the thread while the process runs.

## 3. Synchronous File I/O in the Actor
**File:** `SkillManager.swift` & `ToolExecutor.swift`
**Issue:** We are using `String(contentsOfFile:)` which is synchronous blocking I/O. 
**Fix:** While file I/O is usually fast enough that blocking isn't as catastrophic as blocking on a bash process, it's best practice to push these blocking calls off the cooperative pool. Since we need to make `execute()` async anyway, we can easily wrap file reads/writes in `Task.detached` to ensure they don't block the actor's thread, or use `FileHandle` async methods.

---

### Recommended Next Steps
These are fundamental structural issues that will cause the CLI to hang or crash under load. I can quickly apply these refactors using `multi_replace_file_content` to bring the code up to pristine Swift 6 Concurrency standards. Would you like me to implement these fixes?
