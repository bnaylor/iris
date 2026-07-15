import Foundation

struct PromptInjectionGuard {
    
    /// Tier 1: Text normalization only.
    ///
    /// Normalizes homoglyphs/encodings and strips LLM role delimiters, and returns the
    /// cleaned text **unwrapped**. Wrapping the content in `<untrusted_context>` (and
    /// escaping any breakout closing tags) is the responsibility of `InjectionGuard.sanitize`,
    /// which owns the final encapsulation. This ordering is deliberate: the Tier 2/Tier 3
    /// classifiers in `InjectionGuard` must evaluate the *content*, not the XML scaffolding —
    /// a prompt-injection classifier reads `<untrusted_context>` wrapping as an injection and
    /// flags essentially all benign tool output (see docs/prompt_guard_coreml.md and the
    /// "Guardrail Diagnostics" regression).
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

        return clean
    }
}
