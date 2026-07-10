import SwiftUI

struct ChatView: View {
    @State var state = AppState()
    @State private var inputText = ""
    @Environment(\.openSettings) private var openSettings
    
    var body: some View {
        NavigationSplitView {
            List(selection: $state.selectedConversationId) {
                ForEach(state.conversations) { conv in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(conv.title)
                                .font(.headline)
                            if let wp = conv.workspacePath {
                                Text(wp)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .tag(conv.id)
                    .contextMenu {
                        Button("Link to Workspace...") {
                            linkWorkspace(to: conv.id)
                        }
                    }
                }
            }
            .navigationTitle("Conversations")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { state.createNewConversation() }) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        } detail: {
            if let activeConvIndex = state.activeConversationIndex {
                let conv = state.conversations[activeConvIndex]
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 12) {
                                ForEach(conv.messages) { message in
                                    MessageView(message: message)
                                        .id(message.id)
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
                                }
                            }
                            .padding()
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
                    
                    Divider()
                    
                    HStack {
                        TextField("Ask Iris or override a workflow...", text: $inputText)
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
                    .background(Color(NSColor.windowBackgroundColor))
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
                
                Text(message.content)
                    .padding(10)
                    .background(backgroundColor)
                    .foregroundColor(textColor)
                    .cornerRadius(12)
                    // Apply different corners depending on role
                    .cornerRadius(0, corners: message.role == .user ? [.bottomRight] : [.bottomLeft])
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
