import Foundation
#if canImport(Tokenizers)
import Tokenizers
#endif

public func testTokenizerLoad() async {
    #if canImport(Tokenizers)
    do {
        let url = URL(fileURLWithPath: ("/Users/bnaylor/.iris/models/distilbert-prompt-injection.mlmodelc" as NSString).expandingTildeInPath)
        let _ = try await AutoTokenizer.from(modelFolder: url)
        print("Tokenizer Success")
    } catch {
        print("Tokenizer Error: \(error)")
    }
    #endif
}
