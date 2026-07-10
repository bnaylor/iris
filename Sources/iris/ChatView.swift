import SwiftUI
import MarkdownUI
import UniformTypeIdentifiers

struct ChatView: View {
    @State var state = AppState()
    @State private var inputText = ""
    @State private var selectedMessageIDs = Set<UUID>()
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        NavigationSplitView {
            VStack {
                List(selection: $state.selectedConversationId) {
                    Section(header: Text("Conversations").font(.caption.weight(.bold)).foregroundColor(.secondary).padding(.bottom, 4)) {
                        ForEach(state.conversations) { conv in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(conv.title)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    if let wp = conv.workspacePath {
                                        Text(wp)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 2)
                            .tag(conv.id)
                            .contextMenu {
                                Button("Link to Workspace...") {
                                    linkWorkspace(to: conv.id)
                                }
                                Button("Export to Markdown...") {
                                    exportConversation(id: conv.id)
                                }
                                Divider()
                                Button(role: .destructive, action: {
                                    state.deleteConversation(conv.id)
                                }) {
                                    Text("Delete Conversation")
                                    Image(systemName: "trash")
                                }
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
                
                Button(action: { state.createNewConversation() }) {
                    HStack {
                        Image(systemName: "plus.message.fill")
                        Text("New Conversation")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
            .navigationTitle("Iris")
        } detail: {
            if let activeConvIndex = state.activeConversationIndex {
                let conv = state.conversations[activeConvIndex]
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        List(selection: $selectedMessageIDs) {
                            ForEach(groupedMessages(for: conv)) { item in
                                Group {
                                    switch item {
                                    case .single(let message):
                                        MessageView(message: message)
                                    case .systemGroup(_, let messages):
                                        SystemGroupView(messages: messages)
                                    }
                                }
                                .tag(item.id)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .contextMenu {
                                    Button("Copy as Markdown") {
                                        copyMessagesToClipboard(ids: selectedMessageIDs.contains(item.id) ? selectedMessageIDs : [item.id], from: conv)
                                    }
                                }
                                .simultaneousGesture(TapGesture().onEnded {
                                    if selectedMessageIDs.contains(item.id) {
                                        DispatchQueue.main.async {
                                            selectedMessageIDs.remove(item.id)
                                        }
                                    }
                                })
                            }
                            
                            if state.isThinking {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Iris is thinking...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.leading, 12)
                                .padding(.top, 4)
                                .id("thinkingIndicator")
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                        .onCopyCommand {
                            var selectedMessages: [ChatMessage] = []
                            for item in groupedMessages(for: conv) {
                                if selectedMessageIDs.contains(item.id) {
                                    switch item {
                                    case .single(let msg): selectedMessages.append(msg)
                                    case .systemGroup(_, let msgs): selectedMessages.append(contentsOf: msgs)
                                    }
                                }
                            }
                            
                            if selectedMessages.isEmpty { return [] }
                            
                            var markdown = ""
                            for msg in selectedMessages {
                                let roleName = msg.role == .user ? "You" : (msg.role == .system ? "System" : "Iris")
                                markdown += "### \(roleName)\n"
                                if msg.role == .system {
                                    markdown += "`\(msg.content)`\n\n"
                                } else {
                                    markdown += "\(msg.content)\n\n"
                                }
                            }
                            return [NSItemProvider(object: markdown as NSString)]
                        }
                        .onChange(of: conv.messages.count) { _, _ in
                            if let last = conv.messages.last {
                                withAnimation {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                        .onChange(of: state.isThinking) { _, _ in
                            if state.isThinking {
                                withAnimation {
                                    proxy.scrollTo("thinkingIndicator", anchor: .bottom)
                                }
                            }
                        }
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    
                    if let request = state.pendingApproval {
                        ApprovalBannerView(request: request, onResolve: { resolution in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                state.resolveApproval(resolution)
                            }
                        })
                        .padding(.horizontal)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state.pendingApproval != nil)
                    }
                    
                    Divider()
                    
                    HStack {
                        TextField("Message Iris...", text: $inputText)
                            .textFieldStyle(.plain)
                            .padding(10)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .onSubmit {
                                submit()
                            }
                        
                        Button(action: submit) {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(inputText.isEmpty ? .secondary : .accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(inputText.isEmpty)
                    }
                    .padding()
                    .background(.regularMaterial)
                }
                .background(Color(NSColor.textBackgroundColor))
                .navigationTitle(conv.title)
                .toolbar {
                    if conv.tokenUsage.totalTokenCount > 0 {
                        ToolbarItem(placement: .automatic) {
                            HStack(spacing: 12) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.circle")
                                    Text("\(conv.tokenUsage.promptTokenCount)")
                                }
                                .foregroundColor(.secondary)
                                .help("Prompt Tokens")
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle")
                                    Text("\(conv.tokenUsage.candidatesTokenCount)")
                                }
                                .foregroundColor(.secondary)
                                .help("Candidate Tokens")
                                
                                HStack(spacing: 4) {
                                    Image(systemName: "sum")
                                    Text("\(conv.tokenUsage.totalTokenCount)")
                                }
                                .foregroundColor(.primary)
                                .bold()
                                .help("Total Tokens Used")
                            }
                            .font(.caption)
                        }
                    }
                }
            } else {
                Text("Select or create a conversation.")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 600, idealWidth: 800, minHeight: 400, idealHeight: 600)
        .onAppear {
            if !ConfigManager.shared.isConfigured {
                openSettings()
            } else {
                state.start()
            }
        }
    }
    
    private func linkWorkspace(to id: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select Workspace"
        
        if panel.runModal() == .OK, let url = panel.url {
            state.setWorkspace(for: id, path: url.path)
        }
    }
    
    private func groupedMessages(for conv: Conversation) -> [MessageItem] {
        var result: [MessageItem] = []
        var currentSystemGroup: [ChatMessage] = []
        
        for msg in conv.messages {
            if msg.role == .system {
                currentSystemGroup.append(msg)
            } else {
                if !currentSystemGroup.isEmpty {
                    result.append(.systemGroup(id: currentSystemGroup.first!.id, messages: currentSystemGroup))
                    currentSystemGroup = []
                }
                result.append(.single(msg))
            }
        }
        if !currentSystemGroup.isEmpty {
            result.append(.systemGroup(id: currentSystemGroup.first!.id, messages: currentSystemGroup))
        }
        return result
    }
    
    private func exportConversation(id: UUID) {
        guard let conv = state.conversations.first(where: { $0.id == id }) else { return }
        
        var markdown = "# \(conv.title)\n\n"
        for msg in conv.messages {
            let roleName = msg.role == .user ? "You" : (msg.role == .system ? "System" : "Iris")
            markdown += "### \(roleName)\n"
            if msg.role == .system {
                markdown += "`\(msg.content)`\n\n"
            } else {
                markdown += "\(msg.content)\n\n"
            }
        }
        
        let panel = NSSavePanel()
        if let mdType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [mdType]
        } else {
            panel.allowedContentTypes = [.plainText]
        }
        
        // Clean title for filename
        let cleanTitle = conv.title.replacingOccurrences(of: " ", with: "_").prefix(30)
        panel.nameFieldStringValue = "\(cleanTitle).md"
        panel.prompt = "Export"
        
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to save markdown: \(error)")
            }
        }
    }
    
    private func copyMessagesToClipboard(ids: Set<UUID>, from conv: Conversation) {
        var selectedMessages: [ChatMessage] = []
        for item in groupedMessages(for: conv) {
            if ids.contains(item.id) {
                switch item {
                case .single(let msg): selectedMessages.append(msg)
                case .systemGroup(_, let msgs): selectedMessages.append(contentsOf: msgs)
                }
            }
        }
        
        guard !selectedMessages.isEmpty else { return }
        
        var markdown = ""
        for msg in selectedMessages {
            let roleName = msg.role == .user ? "You" : (msg.role == .system ? "System" : "Iris")
            markdown += "### \(roleName)\n"
            if msg.role == .system {
                markdown += "`\(msg.content)`\n\n"
            } else {
                markdown += "\(msg.content)\n\n"
            }
        }
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(markdown, forType: .string)
    }
    
    private func submit() {
        state.sendMessage(inputText)
        inputText = ""
    }
}

struct MessageView: View {
    let message: ChatMessage
    
    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .system {
                    HStack {
                        Image(systemName: "gearshape.fill")
                        Text("System Event")
                    }
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                } else {
                    Text(message.role == .user ? "You" : "Iris")
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                }
                
                if message.role == .system {
                    SystemMessageContent(text: message.content)
                        .textSelection(.enabled)
                } else if message.role == .user {
                    Text(message.content)
                        .textSelection(.enabled)
                        .padding(10)
                        .background(backgroundColor)
                        .foregroundColor(textColor)
                        .cornerRadius(12)
                        .cornerRadius(0, corners: [.bottomRight])
                } else {
                    Markdown(message.content)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
            }
            
            if message.role != .user {
                Spacer()
            }
        }
    }
    
    private var backgroundColor: Color {
        switch message.role {
        case .user: return Color.accentColor
        case .agent: return Color(NSColor.controlBackgroundColor)
        case .system: return Color(NSColor.windowBackgroundColor).opacity(0.8)
        }
    }
    
    private var textColor: Color {
        switch message.role {
        case .user: return .white
        case .agent, .system: return .primary
        }
    }
    
}

struct SystemGroupView: View {
    let messages: [ChatMessage]
    @State private var isExpanded = false
    
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if messages.count > 1 {
                        Button(action: { withAnimation { isExpanded.toggle() } }) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .foregroundColor(.secondary)
                                .frame(width: 14)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Spacer().frame(width: 14)
                    }
                    
                    Image(systemName: "gearshape.fill")
                    Text(messages.count > 1 && isExpanded ? "System Events (\(messages.count))" : "System Event")
                }
                .font(.caption.bold())
                .foregroundColor(.secondary)
                
                if isExpanded || messages.count == 1 {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(messages) { msg in
                            SystemMessageContent(text: msg.content)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.leading, 22)
                } else if let last = messages.last {
                    SystemMessageContent(text: last.content)
                        .textSelection(.enabled)
                        .padding(.leading, 22)
                }
            }
            Spacer()
        }
    }
}

struct SystemMessageContent: View {
    let text: String
    @State private var isExpanded = false
    
    var body: some View {
        if text.hasPrefix("[TOOL_CALL]\n") {
            let jsonString = String(text.dropFirst("[TOOL_CALL]\n".count))
            if let data = jsonString.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let name = dict["name"] as? String {
                
                VStack(alignment: .leading, spacing: 0) {
                    Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isExpanded.toggle() } }) {
                        HStack {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .foregroundColor(.blue)
                            Text("Tool Execution: ")
                                .foregroundColor(.secondary)
                            + Text(name).bold()
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .padding(10)
                        .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    
                    if isExpanded {
                        Divider()
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(jsonString)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                                .padding(10)
                        }
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    }
                }
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            } else {
                fallbackView
            }
        } else {
            fallbackView
        }
    }
    
    private var fallbackView: some View {
        HStack(alignment: .top) {
            if text.hasPrefix("Running tool:") {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundColor(.blue)
                Text(text)
                    .foregroundColor(.blue)
            } else if text.contains("Hook blocked") || text.contains("denied permission") {
                Image(systemName: "xmark.shield.fill")
                    .foregroundColor(.red)
                Text(text)
                    .foregroundColor(.red)
            } else {
                Image(systemName: "terminal.fill")
                    .foregroundColor(.secondary)
                Text(text)
            }
        }
        .font(.caption.monospaced())
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
        .cornerRadius(12)
        .cornerRadius(0, corners: [.bottomLeft])
    }
}

// Helper to round specific corners in SwiftUI
extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape( RoundedCorner(radius: radius, corners: corners) )
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: RectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tr = corners.contains(.topRight) ? radius : 0
        let tl = corners.contains(.topLeft) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0
        
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br), radius: br, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl), radius: bl, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        
        return path
    }
}

struct ApprovalBannerView: View {
    let request: ToolApprovalRequest
    let onResolve: (AppState.ApprovalResolution) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(.orange)
                Text("Security Guard: Permission Required")
                    .font(.headline)
            }
            
            Text("Iris is attempting to execute a potentially sensitive action:")
                .font(.subheadline)
            
            Text("\(request.toolName): \(request.details)")
                .font(.caption.monospaced())
                .padding(8)
                .background(Color.black.opacity(0.1))
                .cornerRadius(4)
            
            HStack {
                Button(action: { onResolve(.alwaysAllowGlobal) }) {
                    Text("Always Allow (Global)")
                }
                
                if request.workspace != nil {
                    Button(action: { onResolve(.alwaysAllowProject) }) {
                        Text("Always Allow (Project)")
                    }
                }
                
                Spacer()
                
                Button(role: .cancel, action: { onResolve(.deny) }) {
                    Text("Deny")
                }
                .keyboardShortcut(.cancelAction)
                
                Button(action: { onResolve(.approve) }) {
                    Text("Approve Once")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.15))
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

