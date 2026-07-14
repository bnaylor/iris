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
    
    public var hasModelLoaded: Bool {
        lock.withLock { model != nil }
    }
    
    public func loadModelIfNeeded() throws {
        if hasModelLoaded { return }
        let coreMLPathStr = ConfigManager.shared.promptGuardCoreMLModel
        if coreMLPathStr.isEmpty { return }
        
        let filename = coreMLPathStr.starts(with: "http") ? (URL(string: coreMLPathStr)?.lastPathComponent ?? coreMLPathStr) : coreMLPathStr
        var modelDirName = filename
        if modelDirName.hasSuffix(".zip") {
            modelDirName = String(modelDirName.dropLast(4))
        }
        
        let basePath = ("~/.iris/models/" as NSString).expandingTildeInPath
        let fullPath = URL(fileURLWithPath: basePath).appendingPathComponent(modelDirName)
        
        if FileManager.default.fileExists(atPath: fullPath.path) {
            #if canImport(Transformers)
            do {
                let liveModel = try LiveCoreMLModel(modelURL: fullPath, tokenizerConfigURL: fullPath)
                setModel(liveModel)
            } catch {
                print("[CoreMLEvaluator] Failed to load CoreML model: \(error)")
                throw error
            }
            #else
            print("[CoreMLEvaluator] Transformers framework not available. Cannot load CoreML model.")
            throw NSError(domain: "CoreMLEvaluator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Transformers framework not available."])
            #endif
        } else {
            throw NSError(domain: "CoreMLEvaluator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Model directory does not exist at \(fullPath.path)"])
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

#if canImport(Transformers)
import Transformers

public final class LiveCoreMLModel: CoreMLModelProtocol, @unchecked Sendable {
    private let mlModel: MLModel
    private let tokenizer: AutoTokenizer
    private let sequenceLength: Int
    
    public init(modelURL: URL, tokenizerConfigURL: URL, sequenceLength: Int = 512) throws {
        self.mlModel = try MLModel(contentsOf: modelURL)
        self.tokenizer = try AutoTokenizer.from(modelFolder: tokenizerConfigURL)
        self.sequenceLength = sequenceLength
    }
    
    public func evaluate(text: String) async throws -> Double {
        let tokens = tokenizer.encode(text: text)
        var inputIds = tokens.map { Int32($0) }
        var attentionMask = [Int32](repeating: 1, count: inputIds.count)
        
        // Pad or truncate
        if inputIds.count > sequenceLength {
            inputIds = Array(inputIds.prefix(sequenceLength))
            attentionMask = Array(attentionMask.prefix(sequenceLength))
        } else if inputIds.count < sequenceLength {
            let padCount = sequenceLength - inputIds.count
            inputIds.append(contentsOf: [Int32](repeating: 0, count: padCount))
            attentionMask.append(contentsOf: [Int32](repeating: 0, count: padCount))
        }
        
        guard let inputIdsArray = try? MLMultiArray(shape: [1, NSNumber(value: sequenceLength)], dataType: .int32),
              let attentionMaskArray = try? MLMultiArray(shape: [1, NSNumber(value: sequenceLength)], dataType: .int32) else {
            throw NSError(domain: "LiveCoreMLModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create MLMultiArray"])
        }
        
        for i in 0..<sequenceLength {
            inputIdsArray[i] = NSNumber(value: inputIds[i])
            attentionMaskArray[i] = NSNumber(value: attentionMask[i])
        }
        
        let featureProvider = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": inputIdsArray,
            "attention_mask": attentionMaskArray
        ])
        
        let prediction = try mlModel.prediction(from: featureProvider)
        
        // DeBERTa typically outputs "logits". We need to extract the injection probability.
        // Assuming logits is a float array, where index 1 is "injection". (Depends on the HF model's id2label).
        if let logitsFeature = prediction.featureValue(for: "logits"),
           let logitsArray = logitsFeature.multiArrayValue {
            // Apply softmax to get probability
            let logit0 = logitsArray[0].doubleValue
            let logit1 = logitsArray[1].doubleValue
            let maxLogit = max(logit0, logit1)
            let exp0 = exp(logit0 - maxLogit)
            let exp1 = exp(logit1 - maxLogit)
            let prob1 = exp1 / (exp0 + exp1)
            return prob1
        }
        
        return 0.0
    }
}
#endif
