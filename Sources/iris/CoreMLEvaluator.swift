import Foundation
import CoreML

public protocol CoreMLModelProtocol: Sendable {
    func evaluate(text: String) async throws -> Double
}

public final class CoreMLEvaluator: @unchecked Sendable {
    public static let shared = CoreMLEvaluator()
    
    private var model: CoreMLModelProtocol?
    private let lock = NSLock()
    
    private init() {}
    
    public func setModel(_ newModel: CoreMLModelProtocol) {
        lock.withLock {
            model = newModel
        }
    }
    
    public func evaluate(text: String) async throws -> Double {
        let currentModel = lock.withLock { model }
        guard let m = currentModel else {
            // If no model is loaded (e.g. BYOM not yet downloaded), we fail open (assume safe) 
            // so we don't break the user's workflow just because they haven't set up Tier 2 yet.
            print("[CoreMLEvaluator] No model loaded. Defaulting to 0.0 (safe).")
            return 0.0
        }
        
        return try await m.evaluate(text: text)
    }
}
