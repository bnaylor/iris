import Foundation
import LlamaSwift

enum LlamaError: Error {
    case initializationFailed
    case modelLoadFailed
    case contextCreationFailed
    case tokenizationFailed
    case decodingFailed
}

final class LlamaCPPEngine: AuxiliaryInferenceEngine, @unchecked Sendable {
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?
    
    init() async throws {
        llama_backend_init()
    }
    
    func loadModel(config: AuxiliaryModelConfig) async throws {
        let modelParams = llama_model_default_params()
        
        let path = ("~/.iris/models/" as NSString).expandingTildeInPath + "/" + config.modelPathOrName
        guard let loadedModel = llama_model_load_from_file(path, modelParams) else {
            throw LlamaError.modelLoadFailed
        }
        self.model = loadedModel
        self.vocab = llama_model_get_vocab(loadedModel)
        
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 1024
        contextParams.n_batch = 512
        
        guard let ctx = llama_init_from_model(loadedModel, contextParams) else {
            throw LlamaError.contextCreationFailed
        }
        self.context = ctx
        print("LlamaCPPEngine loaded model at \(path)")
    }
    
    func unloadModel() async {
        if let ctx = context {
            llama_free(ctx)
            context = nil
        }
        if let m = model {
            llama_model_free(m)
            model = nil
        }
        vocab = nil
    }
    
    deinit {
        llama_backend_free()
    }
    
    func generate(prompt: String, jsonSchema: String?) async throws -> String {
        guard let ctx = context, let _ = model, let v = vocab else {
            throw LlamaError.modelLoadFailed
        }
        
        let utf8Count = prompt.utf8.count
        let maxTokenCount = utf8Count + 2
        var tokens = [llama_token](repeating: 0, count: maxTokenCount)
        
        let tokenCount = llama_tokenize(v, prompt, Int32(utf8Count), &tokens, Int32(maxTokenCount), true, true)
        guard tokenCount > 0 else { throw LlamaError.tokenizationFailed }
        
        let promptTokens = Array(tokens.prefix(Int(tokenCount)))
        
        var batch = llama_batch_init(512, 0, 1)
        defer { llama_batch_free(batch) }
        
        batch.n_tokens = Int32(promptTokens.count)
        for i in 0..<promptTokens.count {
            let idx = Int(i)
            batch.token[idx] = promptTokens[idx]
            batch.pos[idx] = Int32(i)
            batch.n_seq_id[idx] = 1
            if let seq_ids = batch.seq_id, let seq_id = seq_ids[idx] {
                seq_id[0] = 0
            }
            batch.logits[idx] = 0
        }
        
        if batch.n_tokens > 0 {
            batch.logits[Int(batch.n_tokens) - 1] = 1
        }
        
        guard llama_decode(ctx, batch) == 0 else { throw LlamaError.decodingFailed }
        
        var generatedText = ""
        var n_cur = batch.n_tokens
        
        for _ in 0..<128 { // Max tokens to generate
            guard let logits = llama_get_logits_ith(ctx, batch.n_tokens - 1) else { throw LlamaError.decodingFailed }
            
            let vocabSize = llama_vocab_n_tokens(v)
            var maxLogit = logits[0]
            var nextToken: llama_token = 0
            
            for i in 1..<Int(vocabSize) {
                if logits[i] > maxLogit {
                    maxLogit = logits[i]
                    nextToken = llama_token(i)
                }
            }
            
            if nextToken == llama_vocab_eos(v) { break }
            
            var buffer = [CChar](repeating: 0, count: 16)
            let length = llama_token_to_piece(v, nextToken, &buffer, Int32(buffer.count), 0, false)
            if length > 0 {
                let nullTruncated = buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
                generatedText += String(decoding: nullTruncated, as: UTF8.self)
            }
            
            batch.n_tokens = 1
            batch.token[0] = nextToken
            batch.pos[0] = n_cur
            batch.n_seq_id[0] = 1
            if let seq_ids = batch.seq_id, let seq_id = seq_ids[0] {
                seq_id[0] = 0
            }
            batch.logits[0] = 1
            n_cur += 1
            
            guard llama_decode(ctx, batch) == 0 else { throw LlamaError.decodingFailed }
        }
        
        return generatedText
    }
}
