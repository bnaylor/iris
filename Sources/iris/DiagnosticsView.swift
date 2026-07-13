import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject private var metrics = MetricsManager.shared
    
    var body: some View {
        VStack {
            Text("Diagnostics & Latency")
                .font(.headline)
                .padding()
            
            Table(metrics.recentMetrics) {
                TableColumn("Time") { metric in
                    Text(metric.timestamp, style: .time)
                }
                TableColumn("Operation") { metric in
                    Text(metric.operation.rawValue)
                }
                TableColumn("Model") { metric in
                    Text(metric.modelName)
                }
                TableColumn("Latency") { metric in
                    Text(String(format: "%.0f ms", metric.durationMs))
                        .foregroundColor(metric.durationMs > 5000 ? .orange : .primary)
                }
                TableColumn("Status") { metric in
                    Image(systemName: metric.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(metric.success ? .green : .red)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
