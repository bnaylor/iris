import Foundation

public enum MetricOperationType: String, CaseIterable, Identifiable, Sendable {
    case vibecop = "Vibecop"
    case easy = "Model (Easy)"
    case medium = "Model (Medium)"
    case hard = "Model (Hard)"
    case rename = "Rename"
    case auxiliary = "Auxiliary"
    
    public var id: String { rawValue }
}

public struct ModelLatencyMetric: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp: Date
    public let operation: MetricOperationType
    public let modelName: String
    public let durationMs: Double
    public let success: Bool
}

@MainActor
public class MetricsManager: ObservableObject {
    public static let shared = MetricsManager()
    
    @Published public var recentMetrics: [ModelLatencyMetric] = []
    
    private let maxMetrics = 100
    
    private init() {}
    
    public func trackLatency(operation: MetricOperationType, modelName: String, durationMs: Double, success: Bool = true) {
        let metric = ModelLatencyMetric(timestamp: Date(), operation: operation, modelName: modelName, durationMs: durationMs, success: success)
        recentMetrics.insert(metric, at: 0)
        if recentMetrics.count > maxMetrics {
            recentMetrics.removeLast()
        }
    }
}
