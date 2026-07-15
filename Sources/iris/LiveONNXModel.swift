import Foundation

// ONNX Runtime path for the Tier 2 prompt-injection guard.
//
// This is the recommended runtime for the accurate DeBERTa-v3 classifier: coremltools
// cannot convert DeBERTa without extensive, brittle op surgery, whereas the model exports
// to ONNX cleanly and runs identically to PyTorch on CPU (~6 ms). See
// docs/prompt_guard_coreml.md for the full investigation.
//
// The Swift module vended by microsoft/onnxruntime-swift-package-manager is imported
// below. Tokenization reuses swift-transformers exactly like LiveCoreMLModel.
#if canImport(OnnxRuntimeBindings) && canImport(Tokenizers)
import OnnxRuntimeBindings
import Tokenizers

public final class LiveONNXModel: CoreMLModelProtocol, @unchecked Sendable {
    private let env: ORTEnv
    private let session: ORTSession
    private let tokenizer: any Tokenizer
    private let maxSequenceLength: Int

    public init(modelURL: URL, tokenizerConfigURL: URL, maxSequenceLength: Int = 512) async throws {
        self.env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
        self.session = try ORTSession(env: env, modelPath: modelURL.path, sessionOptions: nil)
        self.tokenizer = try await AutoTokenizer.from(modelFolder: tokenizerConfigURL)
        self.maxSequenceLength = maxSequenceLength
    }

    public func evaluate(text: String) async throws -> Double {
        // Empty/whitespace-only input is trivially safe (mirrors LiveCoreMLModel).
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return 0.0
        }

        // The tokenizer already inserts [CLS]/[SEP]. The ONNX graph has dynamic sequence
        // length, so we feed the real token count (capped) with no padding.
        var inputIds = tokenizer.encode(text: text).map { Int64($0) }
        if inputIds.count > maxSequenceLength {
            inputIds = Array(inputIds.prefix(maxSequenceLength))
        }
        let attentionMask = [Int64](repeating: 1, count: inputIds.count)
        let shape: [NSNumber] = [1, NSNumber(value: inputIds.count)]

        let idsData = NSMutableData(bytes: inputIds, length: inputIds.count * MemoryLayout<Int64>.stride)
        let maskData = NSMutableData(bytes: attentionMask, length: attentionMask.count * MemoryLayout<Int64>.stride)

        let idsValue = try ORTValue(tensorData: idsData, elementType: ORTTensorElementDataType.int64, shape: shape)
        let maskValue = try ORTValue(tensorData: maskData, elementType: ORTTensorElementDataType.int64, shape: shape)

        let outputs = try session.run(
            withInputs: ["input_ids": idsValue, "attention_mask": maskValue],
            outputNames: ["logits"],
            runOptions: nil
        )

        guard let logitsValue = outputs["logits"] else { return 0.0 }
        let data = try logitsValue.tensorData() as Data
        let logits = data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
        // Binary classifier: logits shape [1, 2]; index 1 is INJECTION. Softmax to a prob.
        guard logits.count >= 2 else { return 0.0 }
        let logit0 = Double(logits[0])
        let logit1 = Double(logits[1])
        let maxLogit = max(logit0, logit1)
        let exp0 = exp(logit0 - maxLogit)
        let exp1 = exp(logit1 - maxLogit)
        return exp1 / (exp0 + exp1)
    }
}
#endif
