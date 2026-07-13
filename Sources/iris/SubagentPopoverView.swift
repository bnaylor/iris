import SwiftUI

struct SubagentPopoverView: View {
    @Bindable var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Active Subagents")
                .font(.headline)
                .padding()
            
            Divider()
            
            if appState.activeSubagents.isEmpty {
                Text("No active subagents")
                    .foregroundColor(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                List(appState.activeSubagents) { agent in
                    HStack {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 20, height: 20)
                        
                        VStack(alignment: .leading) {
                            Text(agent.role)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            HStack {
                                Text(agent.status)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text(timerInterval: agent.startTime...Date.distantFuture)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .frame(width: 300, height: 350)
    }
}
