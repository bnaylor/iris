import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject private var metrics = MetricsManager.shared
    
    var body: some View {
        VStack {
            Text("Diagnostics & Latency")
                .font(.headline)
                .padding()
            
            Table(metrics.aggregatedMetrics) {
                TableColumn("Operation") { metric in
                    Text(metric.operation.rawValue)
                }
                TableColumn("Model") { metric in
                    Text(metric.modelName)
                }
                TableColumn("Count") { metric in
                    Text("\(metric.count)")
                }
                TableColumn("Min") { metric in
                    Text(String(format: "%.0f ms", metric.minMs))
                }
                TableColumn("Avg") { metric in
                    Text(String(format: "%.0f ms", metric.avgMs))
                }
                TableColumn("Max") { metric in
                    Text(String(format: "%.0f ms", metric.maxMs))
                        .foregroundColor(metric.maxMs > 5000 ? .orange : .primary)
                }
                TableColumn("StdDev") { metric in
                    Text(String(format: "%.0f ms", metric.stddevMs))
                }
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
