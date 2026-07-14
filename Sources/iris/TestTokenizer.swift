import Foundation
#if canImport(Transformers)
import Transformers
#endif

public func testTokenizerLoad() {
    #if canImport(Transformers)
    do {
        let url = URL(fileURLWithPath: ("/Users/bnaylor/.iris/models/distilbert-prompt-injection.mlmodelc" as NSString).expandingTildeInPath)
        let tokenizer = try AutoTokenizer.from(modelFolder: url)
        print("Tokenizer Success")
    } catch {
        print("Tokenizer Error: \(error)")
    }
    #endif
}
