import Foundation

struct PromptInjectionGuard {
    
    /// Tier 1: Strict Structural Isolation & Text Normalization
    /// Strips common LLM role delimiters, neutralizes closing tags, and normalizes text.
    static func sanitizeUntrustedInput(_ rawInput: String) -> String {
        var clean = rawInput
        
        // 1. Homoglyph & Encoding Normalization
        // Normalize to prevent attackers from using invisible characters or weird encodings to bypass filters.
        // We use NFKC to normalize compatibility characters.
        clean = clean.precomposedStringWithCompatibilityMapping
        
        // Remove control characters (except common whitespace like newlines/tabs)
        let controlChars = CharacterSet.controlCharacters.subtracting(CharacterSet.whitespacesAndNewlines)
        clean = clean.components(separatedBy: controlChars).joined()
        
        // 2. Strip common LLM role delimiters that attempt to hijack the conversation
        let malRolePatterns = [
            "system:",
            "assistant:",
            "user:",
            "model:",
            "---",
            "###",
            "<|im_start|>",
            "<|im_end|>",
            "Instruction:",
            "System Prompt:"
        ]
        
        for pattern in malRolePatterns {
            clean = clean.replacingOccurrences(of: pattern, with: "", options: [.caseInsensitive])
        }
        
        // 3. Escape any malicious closing tags an attacker injected to break out of context
        // If we plan to wrap the content in <untrusted_context>, we must neutralize </untrusted_context>
        clean = clean.replacingOccurrences(of: "</untrusted_context>", with: "[escaped_tag]", options: [.caseInsensitive])
        
        // 4. Encapsulate safely
        return "<untrusted_context>\n\(clean)\n</untrusted_context>"
    }
}
