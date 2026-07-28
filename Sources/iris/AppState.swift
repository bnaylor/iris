import Foundation
import SwiftUI

enum ChatRole: String, Codable {
    case user
    case agent
    case system
    /// Deterministic slash-command output rendered as Markdown, not attributed to Iris.
    case command
}

struct ChatMessage: Identifiable, Codable, Sendable {
    var id = UUID()
    let role: ChatRole
    let content: String
    var attachments: [FileAttachment] = []

    enum CodingKeys: String, CodingKey {
        case id, role, content, attachments
    }

    init(id: UUID = UUID(), role: ChatRole, content: String, attachments: [FileAttachment] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        role = try container.decode(ChatRole.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)
        attachments = try container.decodeIfPresent([FileAttachment].self, forKey: .attachments) ?? []
    }
}

struct TokenUsage: Codable, Equatable {
    var promptTokenCount: Int = 0
    var candidatesTokenCount: Int = 0
    var totalTokenCount: Int = 0
}

struct Conversation: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var messages: [ChatMessage] = []
    var workspacePath: String?
    var history: [Content] = []
    var tokenUsage: TokenUsage = TokenUsage()
    var activeGoal: String?
    var messageCountSinceReflection: Int = 0
    var goalIterationCount: Int = 0
    var mainAgentSandbox: SandboxPref? = nil
    var isSubagent: Bool = false

    init(id: UUID = UUID(), title: String, messages: [ChatMessage] = [], workspacePath: String? = nil, history: [Content] = [], tokenUsage: TokenUsage = TokenUsage(), activeGoal: String? = nil, messageCountSinceReflection: Int = 0) {
        self.id = id
        self.title = title
        self.messages = messages
        self.workspacePath = workspacePath
        self.history = history
        self.tokenUsage = tokenUsage
        self.activeGoal = activeGoal
        self.messageCountSinceReflection = messageCountSinceReflection
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, messages, workspacePath, history, tokenUsage, activeGoal, messageCountSinceReflection, mainAgentSandbox, isSubagent
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        workspacePath = try container.decodeIfPresent(String.self, forKey: .workspacePath)
        history = try container.decodeIfPresent([Content].self, forKey: .history) ?? []
        tokenUsage = try container.decodeIfPresent(TokenUsage.self, forKey: .tokenUsage) ?? TokenUsage()
        activeGoal = try container.decodeIfPresent(String.self, forKey: .activeGoal)
        messageCountSinceReflection = try container.decodeIfPresent(Int.self, forKey: .messageCountSinceReflection) ?? 0
        mainAgentSandbox = try container.decodeIfPresent(SandboxPref.self, forKey: .mainAgentSandbox)
        isSubagent = try container.decodeIfPresent(Bool.self, forKey: .isSubagent) ?? false
    }
    
    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ToolApprovalRequest: Identifiable {
    let id = UUID()
    let toolName: String
    let details: String
    let workspace: String?
    let conversationId: UUID?
    let origin: String
    let continuation: CheckedContinuation<Bool, Never>
}

struct ActiveSubagent: Identifiable, Hashable {
    let id: UUID
    let role: String
    let startTime: Date
    var status: String
}

@MainActor
@Observable
class AppState {
    /// The single app-wide AppState. `ChatView` and `SubagentManager` MUST share one instance —
    /// SwiftUI evaluates a `@State`'s default expression on every view re-init, so
    /// `@State var state = AppState()` was constructing several AppStates (each registering itself
    /// as the SubagentManager global and racing on UserDefaults). Referencing the singleton means
    /// the expression returns the same object every time.
    static let shared = AppState()

    var conversations: [Conversation] = []
    var selectedConversationId: UUID?
    /// Read-only for observers. Ownership is centralized through `beginThinking()`/`endThinking()`
    /// so overlapping turns (concurrent sends, subagents, auto-reprompt) can't leave it stuck.
    private(set) var isThinking = false
    var activeSubagents: [ActiveSubagent] = []
    var pendingApprovals: [ToolApprovalRequest] = []
    var availableUpdate: ReleaseInfo?
    var isCheckingForUpdates = false
    var updateCheckStatusMessage: String?
    var onSubagentComplete: [UUID: @Sendable (String) -> Void] = [:]

    /// Reference count of in-flight "thinking" work. `isThinking` is derived from this.
    private var thinkingCount = 0
    /// Tracked UI-initiated tasks so they can be cancelled (e.g. when a conversation is deleted).
    private var activeTasks: [UUID: (conversationId: UUID?, task: Task<Void, Never>)] = [:]

    private var engine: IrisEngine!
    
    init() {
        self.engine = IrisEngine(state: self)
        SubagentManager.shared.setGlobalState(self)
        loadConversations()
        if conversations.isEmpty {
            createNewConversation()
        }
    }
    
    var activeConversationIndex: Int? {
        conversations.firstIndex(where: { $0.id == selectedConversationId })
    }

    // MARK: - Thinking state

    /// Acquire one unit of "thinking". Balanced by `endThinking()`.
    func beginThinking() {
        thinkingCount += 1
        isThinking = true
    }

    /// Release one unit of "thinking".
    func endThinking() {
        thinkingCount = max(0, thinkingCount - 1)
        isThinking = thinkingCount > 0
    }

    /// Runs UI-initiated engine work while holding the thinking indicator and tracking the
    /// task so it can be cancelled. The `work` closure must not touch `isThinking` directly.
    private func runThinkingTask(conversationId: UUID?, _ work: @escaping @MainActor () async -> Void) {
        let id = UUID()
        beginThinking()
        let task = Task { @MainActor [weak self] in
            await work()
            guard let self else { return }
            self.activeTasks[id] = nil
            self.endThinking()
        }
        activeTasks[id] = (conversationId, task)
    }

    /// Cancels any tracked tasks associated with a conversation and asks the engine to stop
    /// its auto-reprompt loop for it.
    private func cancelTasks(for conversationId: UUID) {
        for (_, entry) in activeTasks where entry.conversationId == conversationId {
            entry.task.cancel()
        }
        let engine = self.engine
        Task { await engine?.cancelReprompt(for: conversationId) }
    }

    /// User-initiated interrupt of in-flight work for the active conversation. Bound to the
    /// Esc key / Stop button in the UI. Inert when nothing is running. Cancellation lands at
    /// the engine's next turn boundary (see `IrisEngine.processInput`), which then clears the
    /// thinking indicator via the tracked task's completion.
    func interruptActiveConversation() {
        guard let convId = selectedConversationId, isThinking else { return }
        cancelTasks(for: convId)
        appendMessage(role: .system, content: "Interrupted.", to: convId)
    }
    
    func createNewConversation(id: UUID = UUID(), isSubagent: Bool = false) {
        var newConv = Conversation(id: id, title: "New Conversation")
        newConv.isSubagent = isSubagent
        conversations.append(newConv)
        if !isSubagent {
            selectedConversationId = newConv.id
        }
        saveConversations()

        Task {
            _ = await HookManager.shared.fireSessionStart(conversationId: newConv.id)
        }
    }
    
    func updateConversationTitle(id: UUID, title: String) {
        if let idx = conversations.firstIndex(where: { $0.id == id }) {
            conversations[idx].title = title
            saveConversations()
        }
    }
    
    func registerSubagent(id: UUID, role: String) {
        let subagent = ActiveSubagent(id: id, role: role, startTime: Date(), status: "Initializing...")
        activeSubagents.append(subagent)
    }

    func removeSubagent(id: UUID) {
        activeSubagents.removeAll(where: { $0.id == id })
    }
    
    func updateSubagentStatus(id: UUID, status: String) {
        if let idx = activeSubagents.firstIndex(where: { $0.id == id }) {
            activeSubagents[idx].status = status
        }
    }
    
    func setWorkspace(for conversationId: UUID, path: String) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].workspacePath = path
            saveConversations()
        }
    }

    func setMainAgentSandbox(for conversationId: UUID, pref: SandboxPref?) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].mainAgentSandbox = pref
            saveConversations()
        }
    }

    /// The resolved main-agent sandbox state for a conversation, used by the sidebar toggle's
    /// checkmark. Subagent conversations are not user-togglable, so this is only meaningful for
    /// main conversations.
    func effectiveMainSandboxed(_ conv: Conversation) -> Bool {
        let decision = SandboxPolicy.resolve(
            masterEnabled: ConfigManager.shared.enableSandboxing,
            principal: .main,
            perConversation: conv.mainAgentSandbox,
            perWorkspace: SandboxPolicy.perWorkspaceOverride(workspace: conv.workspacePath),
            globalDefault: ConfigManager.shared.mainAgentSandboxDefault,
            runtimeAvailable: SandboxingManager.shared.isContainerInstalled)
        return decision == .sandboxed
    }

    private func handleSandboxCommand(_ trimmed: String, convId: UUID) {
        guard let conv = conversations.first(where: { $0.id == convId }) else { return }
        let args = trimmed.dropFirst("/sandbox".count).trimmingCharacters(in: .whitespaces)

        // Sub-command: /sandbox workspace <host|sandboxed|clear>
        if args.hasPrefix("workspace") {
            let value = args.dropFirst("workspace".count).trimmingCharacters(in: .whitespaces).lowercased()
            guard let ws = conv.workspacePath else {
                emitCommandOutput("No workspace is linked to this conversation. Link one first (right-click → Link to Workspace…).", format: .markdown, to: convId)
                return
            }
            let success: Bool
            switch value {
            case "host": success = SandboxPolicy.setWorkspaceOverride(.host, for: ws)
            case "sandboxed": success = SandboxPolicy.setWorkspaceOverride(.sandboxed, for: ws)
            case "clear": success = SandboxPolicy.setWorkspaceOverride(nil, for: ws)
            default:
                emitCommandOutput("Usage: `/sandbox workspace host|sandboxed|clear`", format: .markdown, to: convId)
                return
            }
            guard success else {
                emitCommandOutput("Failed to write the per-workspace sandbox setting to `\(ws)` (check permissions).", format: .markdown, to: convId)
                return
            }
            if value == "clear" {
                emitCommandOutput("Cleared the per-workspace main-agent sandbox override for `\(ws)`.", format: .markdown, to: convId)
            } else {
                emitCommandOutput("Per-workspace main-agent sandbox set to **\(value)** for `\(ws)`.", format: .markdown, to: convId)
            }
            return
        }

        // No arg (or anything else): report status.
        let master = ConfigManager.shared.enableSandboxing
        let runtime = SandboxingManager.shared.isContainerInstalled
        let effective = effectiveMainSandboxed(conv)
        let source: String
        if conv.mainAgentSandbox != nil { source = "this conversation" }
        else if SandboxPolicy.perWorkspaceOverride(workspace: conv.workspacePath) != nil { source = "workspace `.iris/sandbox.json`" }
        else { source = "global default" }

        let body = """
        **Sandbox policy**

        - Feature master switch: **\(master ? "on" : "off")**
        - Container runtime installed: **\(runtime ? "yes" : "no")**
        - Main agent (this conversation): **\(effective ? "sandboxed" : "host")** — from \(source)
        - Global default: **\(ConfigManager.shared.mainAgentSandboxDefault.rawValue)**
        - Subagents: **always sandboxed** when the master switch is on and a runtime is present

        Set a per-workspace default with `/sandbox workspace host|sandboxed|clear`.
        """
        emitCommandOutput(body, format: .markdown, to: convId)
    }

    func deleteConversation(_ id: UUID) {
        cancelTasks(for: id)
        Task { await SandboxSessionManager.shared.endSession(id) }
        conversations.removeAll { $0.id == id }
        if selectedConversationId == id {
            selectedConversationId = conversations.last?.id
        }
        if conversations.isEmpty {
            createNewConversation()
        } else {
            saveConversations()
        }
    }
    
    func start() {
        Task {
            await engine.start()
        }
    }
    
    func sendMessage(_ text: String, attachments: [FileAttachment] = []) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (!trimmed.isEmpty || !attachments.isEmpty), let convId = selectedConversationId else { return }
        
        var messageContent = trimmed
        if trimmed.hasPrefix("/goal") {
            let goalText = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            if goalText.isEmpty {
                appendMessage(role: .system, content: "Please specify a goal, e.g., `/goal Build a snake game in Python`", to: convId)
                return
            }
            if let idx = conversations.firstIndex(where: { $0.id == convId }) {
                conversations[idx].activeGoal = goalText
                saveConversations()
            }
            messageContent = "GOAL MODE ACTIVATED. Your goal is: \(goalText). You must continually use tools to achieve this goal. If you need to stop and think or plan, use the `reflect` tool or just output text. When the goal is COMPLETELY FINISHED, use the `goal_complete` tool."
        } else if trimmed.hasPrefix("/stop") {
            if let idx = conversations.firstIndex(where: { $0.id == convId }) {
                conversations[idx].activeGoal = nil
                saveConversations()
            }
            cancelTasks(for: convId)
            appendMessage(role: .system, content: "Goal mode cancelled.", to: convId)
            return
        } else if trimmed == "/skills" {
            // Handled deterministically in-app — never sent to the model, which would otherwise
            // improvise its own summary.
            Task { [weak self] in
                let skills = await SkillManager.shared.listSkills()
                guard let self else { return }
                let body: String
                if skills.isEmpty {
                    body = "No skills are currently registered."
                } else {
                    let list = skills
                        .map { "- **\($0.name)** — \($0.description)" }
                        .joined(separator: "\n")
                    body = "**Registered skills (\(skills.count))**\n\n\(list)"
                }
                self.emitCommandOutput(body, format: .markdown, to: convId)
            }
            return
        } else if trimmed == "/sandbox" || trimmed.hasPrefix("/sandbox ") {
            handleSandboxCommand(trimmed, convId: convId)
            return
        } else if trimmed.hasPrefix("/reflect") {
            appendMessage(role: .system, content: "Triggering manual memory reflection...", to: convId)
            let reflectionPrompt = """
            System Event [Reflection Trigger]: It's time to consolidate your memories. Reflect on the recent conversation. Have you learned any new user preferences, project structures, or recurring workflows? If so, use `update_soul` to evolve your persona, `update_user_profile` to update the user profile, `update_memory` to consolidate durable facts, and `write_file`/`read_file` under `~/.iris/memory/skills/` for skills. When you learn something durable — a lesson, recipe, decision, or reusable artifact — archive it to your permanent library at `~/.iris/memory/library/` (see your Library Management skill).

            Additionally, perform a grooming pass on your Markdown memory library. Ensure ALL memory files (`~/.iris/memory/skills/*`, `~/.iris/memory/USER.md`, `~/.iris/memory/SOUL.md`) use the Open Knowledge Format (OKF). This means each file MUST start with a YAML frontmatter block containing at least:
            ---
            type: [skill|profile|core|etc]
            title: ...
            description: ...
            tags: [..., ...]
            timestamp: ...
            ---
            Verify that your cross-links between files are still valid, and reorganize or fix any broken links. Output a transparent summary of the gist of the updates and grooming performed for the user. If nothing needs updating, just reply 'No memory consolidation needed at this time.'
            """
            runThinkingTask(conversationId: convId) { [self] in
                await engine.processInput(reflectionPrompt, source: "System", conversationId: convId)
            }
            return
        } else if trimmed.hasPrefix("/vibecop init") {
            appendMessage(role: .system, content: "Initializing Vibecop Guardian mode...", to: convId)
            let initPrompt = "System Event [Vibecop Init]: Analyze the current workspace directory to understand the project structure, language, framework, and tooling. Generate a custom Guardian prompt that defines what terminal commands and file operations are 'routine' for this specific workspace, and what should be escalated to the user. Write this prompt to a new file at `.iris/vibecop.md` inside the workspace using the `write_file` tool. Output a transparent summary of the generated rules for the user."
            runThinkingTask(conversationId: convId) { [self] in
                await engine.processInput(initPrompt, source: "System", conversationId: convId)
            }
            return
        } else if trimmed.hasPrefix("/rename") {
            appendMessage(role: .system, content: "Triggering automatic conversation rename...", to: convId)
            let renamePrompt = "System Event [Rename Trigger]: Evaluate the conversation history and use the `rename_conversation` tool to assign a short, descriptive title (1-4 words) that captures the true gist of this conversation."
            runThinkingTask(conversationId: convId) { [self] in
                await engine.processInput(renamePrompt, source: "System", conversationId: convId)
            }
            return
        }

        appendMessage(role: .user, content: messageContent, attachments: attachments, to: convId)

        if let idx = conversations.firstIndex(where: { $0.id == convId }) {
            conversations[idx].messageCountSinceReflection += 1
            saveConversations()
            
            let userMessagesCount = conversations[idx].messages.filter { $0.role == .user }.count
            let shouldRename = userMessagesCount == 3 && conversations[idx].messageCountSinceReflection == 3
            let shouldReflect = conversations[idx].messageCountSinceReflection >= 30

            let attachmentsToProcess = attachments
            let rawContent = messageContent
            
            runThinkingTask(conversationId: convId) { [self] in
                var promptForEngine = rawContent
                var inlineParts: [Part] = []

                if !attachmentsToProcess.isEmpty {
                    let primaryModel = ConfigManager.shared.getModel(for: .medium)
                    let primarySupportsVision = VisionRouter.isVisionCapable(modelName: primaryModel)
                    let processed = (try? await AttachmentProcessor.process(attachments: attachmentsToProcess, primarySupportsVision: primarySupportsVision)) ?? AttachmentProcessingResult()

                    for warning in processed.warnings {
                        appendMessage(role: .system, content: "⚠️ \(warning)", to: convId)
                    }

                    var textParts: [String] = []
                    if !rawContent.isEmpty {
                        textParts.append(rawContent)
                    }
                    if !processed.extractedPromptText.isEmpty {
                        textParts.append(processed.extractedPromptText)
                    }

                    if !primarySupportsVision {
                        let visionResult = await VisionRouter.processTextOnlyImages(attachments: attachmentsToProcess)
                        if !visionResult.descriptionText.isEmpty {
                            textParts.append(visionResult.descriptionText)
                        }
                        for warning in visionResult.warnings {
                            appendMessage(role: .system, content: "⚠️ \(warning)", to: convId)
                        }
                    }

                    promptForEngine = textParts.joined(separator: "\n\n")
                    inlineParts = processed.inlineParts
                }

                await engine.processInput(promptForEngine, source: "UI", conversationId: convId, inlineParts: inlineParts)

                if shouldReflect {
                    if let idx = conversations.firstIndex(where: { $0.id == convId }) {
                        conversations[idx].messageCountSinceReflection = 0
                        saveConversations()
                    }
                    let reflectionPrompt = "System Event [Reflection Trigger]: It's time to consolidate your memories. Reflect on the recent conversation. Have you learned any new user preferences, project structures, or recurring workflows? If so, use `update_soul` to evolve your persona, `update_user_profile` to update the user profile, `update_memory` to consolidate durable facts, and `write_file`/`read_file` under `~/.iris/memory/skills/` for skills. When you learn something durable — a lesson, recipe, decision, or reusable artifact — archive it to your permanent library at `~/.iris/memory/library/` (see your Library Management skill). Output a transparent summary of the gist of the updates for the user. If nothing needs updating, just reply 'No memory consolidation needed at this time.'"
                    appendMessage(role: .system, content: "Triggering automatic memory reflection...", to: convId)
                    await engine.processInput(reflectionPrompt, source: "System", conversationId: convId)
                } else if shouldRename {
                    let renamePrompt = "System Event [Rename Trigger]: Evaluate the conversation history and use the `rename_conversation` tool to assign a short, descriptive title (1-4 words) that captures the true gist of this conversation."
                    appendMessage(role: .system, content: "Triggering automatic conversation rename...", to: convId)
                    await engine.processInput(renamePrompt, source: "System", conversationId: convId)
                }
            }
        } else {
            runThinkingTask(conversationId: convId) { [self] in
                await engine.processInput(messageContent, source: "UI", conversationId: convId)
            }
        }
    }
    
    /// How a slash command's direct output is rendered. All command output is display-only —
    /// it is never added to the LLM `history` the agent sees on later turns.
    enum CommandOutputFormat {
        /// Monospaced "System Event" styling (plain text, no Markdown).
        case system
        /// Rendered Markdown, not attributed to Iris.
        case markdown
    }

    /// Emit deterministic slash-command output into the conversation for display only.
    /// This is the sugar slash-command handlers use instead of reaching for `appendMessage`
    /// directly, so each command just declares how its output should look.
    func emitCommandOutput(_ text: String, format: CommandOutputFormat, to conversationId: UUID) {
        let role: ChatRole = format == .markdown ? .command : .system
        appendMessage(role: role, content: text, to: conversationId)
    }

    func appendMessage(role: ChatRole, content: String, attachments: [FileAttachment] = [], to conversationId: UUID) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].messages.append(ChatMessage(role: role, content: content, attachments: attachments))
            
            // Auto-title generation based on first message
            if role == .user && conversations[idx].messages.filter({ $0.role == .user }).count == 1 {
                let displayTitle = content.isEmpty ? (attachments.first?.filename ?? "Attachment") : content
                conversations[idx].title = String(displayTitle.prefix(30)) + (displayTitle.count > 30 ? "..." : "")
            }
            saveConversations()
        }
    }
    
    func updateHistory(for conversationId: UUID, history: [Content]) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].history = history
            saveConversations()
        }
    }
    
    func appendContentToHistory(for conversationId: UUID, content: Content) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].history.append(content)
            saveConversations()
        }
    }
    
    func appendContentsToHistory(for conversationId: UUID, contents: [Content]) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].history.append(contentsOf: contents)
            saveConversations()
        }
    }
    
    func updateTokenUsage(for conversationId: UUID, usage: UsageMetadata) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].tokenUsage.promptTokenCount += usage.promptTokenCount ?? 0
            conversations[idx].tokenUsage.candidatesTokenCount += usage.candidatesTokenCount ?? 0
            conversations[idx].tokenUsage.totalTokenCount += usage.totalTokenCount ?? 0
            saveConversations()
        }
    }
    
    func clearGoal(for conversationId: UUID) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].activeGoal = nil
            conversations[idx].goalIterationCount = 0
            saveConversations()
        }
    }
    
    func setGoal(for conversationId: UUID, goal: String) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].activeGoal = goal
            conversations[idx].goalIterationCount = 0
            saveConversations()
        }
    }
    
    enum ApprovalResolution {
        case approve
        case deny
        case alwaysAllowGlobal
        case alwaysAllowProject
    }
    
    func requestApproval(toolName: String, details: String, workspace: String? = nil,
                         conversationId: UUID? = nil, origin: String = "Main agent",
                         inSandbox: Bool = false) async -> Bool {
        // Fast path: deterministic permissions.
        if PermissionManager.shared.isAllowed(toolName: toolName, details: details, workspace: workspace) {
            return true
        }

        // Vibecop, bounded by a timeout so a wedged local model can't hang the turn.
        // Uses adaptive timeout: if the Ollama model is cold (unloaded), give it 30s to load.
        do {
            let configuredTimeout = Double(ConfigManager.shared.vibecopTimeoutSeconds)
            let engineType = AuxiliaryEngineType(rawValue: ConfigManager.shared.vibecopEngine) ?? .llamaCPP
            var timeout = configuredTimeout
            
            if engineType == .ollama {
                let engine = try? await AuxiliaryModelManager.shared.getEngine(
                    for: "vibecop", config: AuxiliaryModelConfig(
                        role: "vibecop",
                        engineType: .ollama,
                        modelPathOrName: ConfigManager.shared.vibecopModel
                    )
                )
                if let ollamaEngine = engine, !(await ollamaEngine.isModelLoaded()) {
                    timeout = 30.0  // cold-start budget
                    print("Vibecop: Ollama model cold, using \(timeout)s timeout")
                }
            }
            
            let decision = try await withTimeout(seconds: timeout) {
                try await VibecopService.shared.evaluateAction(toolName: toolName, details: details, workspace: workspace, inSandbox: inSandbox)
            }
            if decision.decision == "APPROVE" { return true }
            if decision.decision == "DENY" { return false }
            // ESCALATE → fall through to the user prompt.
        } catch {
            // Timeout or Vibecop error → fail open to the user prompt.
            print("Vibecop evaluation failed/timed out: \(error)")
        }

        return await enqueueUserApproval(toolName: toolName, details: details, workspace: workspace,
                                         conversationId: conversationId, origin: origin)
    }

    /// Appends an approval request and awaits the user's decision. The queue/continuation seam,
    /// separated from `requestApproval`'s permission/Vibecop fast paths so it is unit-testable.
    func enqueueUserApproval(toolName: String, details: String, workspace: String?,
                             conversationId: UUID?, origin: String) async -> Bool {
        // If our task was already cancelled (e.g. a subagent torn down while we were suspended
        // in the Vibecop/timeout window), do NOT enqueue a request nobody will resolve — the
        // teardown's denyPendingApprovals already ran and would miss a late append.
        if Task.isCancelled { return false }
        return await withCheckedContinuation { continuation in
            pendingApprovals.append(ToolApprovalRequest(
                toolName: toolName, details: details, workspace: workspace,
                conversationId: conversationId, origin: origin, continuation: continuation))
        }
    }

    /// Resolves-false and removes every queued request for a conversation. Used to unstick a
    /// subagent blocked on approval when it is cancelled/timed-out.
    func denyPendingApprovals(for conversationId: UUID) {
        let matching = pendingApprovals.filter { $0.conversationId == conversationId }
        pendingApprovals.removeAll { $0.conversationId == conversationId }
        for req in matching { req.continuation.resume(returning: false) }
    }

    func resolveApproval(_ resolution: ApprovalResolution) {
        guard !pendingApprovals.isEmpty else { return }
        let pending = pendingApprovals.removeFirst()
        var approved = false
        switch resolution {
        case .approve:
            approved = true
        case .deny:
            approved = false
        case .alwaysAllowGlobal:
            PermissionManager.shared.allowGlobally(toolName: pending.toolName, details: pending.details)
            approved = true
        case .alwaysAllowProject:
            if let workspace = pending.workspace {
                PermissionManager.shared.allowInProject(toolName: pending.toolName, details: pending.details, workspace: workspace)
            } else {
                PermissionManager.shared.allowGlobally(toolName: pending.toolName, details: pending.details)
            }
            approved = true
        }
        pending.continuation.resume(returning: approved)
    }
    
    func checkForUpdates(explicit: Bool = false) {
        isCheckingForUpdates = true
        updateCheckStatusMessage = "Checking for updates..."
        Task {
            let result = await UpdateManager.shared.checkForUpdates()
            await MainActor.run {
                self.isCheckingForUpdates = false
                switch result {
                case .updateAvailable(let release):
                    self.availableUpdate = release
                    self.updateCheckStatusMessage = "Update available: \(release.tagName)"
                case .upToDate:
                    self.availableUpdate = nil
                    self.updateCheckStatusMessage = explicit ? "Iris is up to date (v\(Constants.appVersion))." : nil
                case .error(let msg):
                    self.updateCheckStatusMessage = explicit ? "Failed to check for updates: \(msg)" : nil
                }
            }
        }
    }
    
    private var saveTask: Task<Void, Never>? = nil
    
    private func saveConversations() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(conversations) {
                UserDefaults.standard.set(data, forKey: "iris_conversations")
            }
        }
    }
    
    func renameConversation(id: UUID, newTitle: String) {
        if let idx = conversations.firstIndex(where: { $0.id == id }) {
            conversations[idx].title = newTitle
            saveConversations()
        }
    }
    
    private func loadConversations() {
        if let data = UserDefaults.standard.data(forKey: "iris_conversations") {
            do {
                let decoded = try JSONDecoder().decode([Conversation].self, from: data)
                self.conversations = decoded
                self.selectedConversationId = decoded.last?.id
            } catch {
                print("Failed to decode conversations: \(error)")
                UserDefaults.standard.set(data, forKey: "iris_conversations_backup_\(Date().timeIntervalSince1970)")
            }
        }
    }
}
