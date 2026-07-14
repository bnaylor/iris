# Quick bug list

Eventually replace this with github issues but we're in fast mode right now.

- [x] Can't select my own text in the chat window

## From Deepseek review:

ConfigManager.swift` — API keys stored in plaintext UserDefaults
**Issue:** All API keys (Gemini, Anthropic, OpenAI, Google OAuth tokens) are sto
red in `UserDefaults` without encryption. On macOS, UserDefaults is stored as a
plain plist file accessible to any process running as the same user.

**Severity:** Medium. This is standard practice for many desktop apps, but given
 that Iris can execute arbitrary shell commands, a malicious tool output could t
 heoretically read the plist file and exfiltrate keys.

 **Recommendation:** Store API keys in the macOS Keychain using `SecItemAdd`/`SecItemCopyMatching`. This is the expected practice for macOS apps handling credentials.

