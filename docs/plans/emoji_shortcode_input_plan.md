# Emoji Shortcode Input Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Slack/Discord/Apple-level `:emoji:` shortcode entry to the chat composer — autocomplete popup + inline auto-replace + skin tones.

**Architecture:** A pure-logic emoji catalog and tokenizer (unit-tested, no AppKit) feed an `@Observable` glue model, which drives a keyboard-navigable popup and an `NSTextView`-backed composer that replaces the SwiftUI `TextField` so we can track the true caret. Settings gains a default-skin-tone preference.

**Tech Stack:** Swift 6 (language mode v6), SwiftUI + AppKit (`NSViewRepresentable`), swift-testing (`import Testing`), `iamcal/emoji-data` JSON bundled as an SPM resource.

## Global Constraints

- Dataset is `iamcal/emoji-data`, pinned to commit `097705020bcf82331c9ef10df3425aad15f5043c` (`0977050`), MIT licensed. Vendored at `Sources/iris/assets/emoji.json`, shipped via the existing `Package.swift` `.process("assets")` rule, loaded with `Bundle.module.url(forResource: "emoji", withExtension: "json")`.
- `SkinTone` raw values are Slack tone numbers: `none = 1`, then `2…6` = light→dark. Tone codepoints: 2→`1F3FB`, 3→`1F3FC`, 4→`1F3FD`, 5→`1F3FE`, 6→`1F3FF`. There is no `:skin-tone-1:`.
- Popup trigger: the `:` must be at a word boundary (start-of-text or preceded by whitespace) followed by `[a-zA-Z0-9_+-]`, and the query must be **≥ 2 chars**. This suppresses false-fires on `10:30` and lone colons.
- The composer MUST preserve current behavior: **Enter = send**, **Shift+Enter = newline**, and the existing slash-command popup must keep working.
- Explicit `::skin-tone-N:` in text always overrides the default-tone setting. Skin tone is ignored for non-capable emoji.
- Tests use swift-testing (`import Testing`, `@Suite`, `@Test`, `#expect`), `@testable import iris`. New test files live in `Tests/irisTests/`.
- Shared singletons follow the existing `final class … : @unchecked Sendable { static let shared = … }` pattern.

---

### Task 1: EmojiCatalog + vendored dataset

**Files:**
- Create: `scripts/fetch-emoji-data.sh`
- Create: `Sources/iris/assets/emoji.json` (produced by the script)
- Create: `Sources/iris/EmojiCatalog.swift`
- Test: `Tests/irisTests/EmojiCatalogTests.swift`

**Interfaces:**
- Produces:
  - `struct EmojiItem: Identifiable, Sendable, Equatable { var id: String { shortcode }; let shortcode: String; let glyph: String; let supportsSkinTone: Bool }`
  - `enum SkinTone: Int, CaseIterable, Codable, Sendable { case none = 1, light = 2, mediumLight = 3, medium = 4, mediumDark = 5, dark = 6 }` with `var codepoint: String?`, `var modifierName: String?`, `static func fromModifier(_:) -> SkinTone?`
  - `final class EmojiCatalog: @unchecked Sendable { static let shared; init(url:); var items: [EmojiItem]; func glyph(for:tone:) -> String?; func matches(prefix:limit:) -> [EmojiItem]; static func scalars(from:) -> String }`

- [ ] **Step 1: Create the fetch script**

Create `scripts/fetch-emoji-data.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
# Vendors iamcal/emoji-data emoji.json at a pinned commit. No Node/npm required.
PIN="097705020bcf82331c9ef10df3425aad15f5043c"
DEST="$(cd "$(dirname "$0")/.." && pwd)/Sources/iris/assets/emoji.json"
URL="https://raw.githubusercontent.com/iamcal/emoji-data/${PIN}/emoji.json"
echo "Fetching emoji.json @ ${PIN:0:7} …"
curl -fsSL "$URL" -o "$DEST"
COUNT=$(python3 -c "import json; print(len(json.load(open('$DEST'))))")
echo "Wrote $DEST ($COUNT entries)"
```

- [ ] **Step 2: Run the script to vendor the data**

Run: `chmod +x scripts/fetch-emoji-data.sh && ./scripts/fetch-emoji-data.sh`
Expected: `Wrote …/Sources/iris/assets/emoji.json (1911 entries)`

- [ ] **Step 3: Write the failing test**

Create `Tests/irisTests/EmojiCatalogTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@Suite("EmojiCatalog")
struct EmojiCatalogTests {
    let catalog = EmojiCatalog.shared

    @Test("dataset loads the full set")
    func loads() {
        #expect(catalog.items.count > 1900)
    }

    @Test("basic shortcode resolves")
    func wave() {
        #expect(catalog.glyph(for: "wave") == "👋")
    }

    @Test("aliases resolve to the same glyph")
    func aliases() {
        #expect(catalog.glyph(for: "thumbsup") == "👍")
        #expect(catalog.glyph(for: "+1") == catalog.glyph(for: "thumbsup"))
    }

    @Test("prefix search ranks exact first and respects the cap")
    func search() {
        let r = catalog.matches(prefix: "smi", limit: 5)
        #expect(r.count <= 5)
        #expect(r.contains { $0.shortcode == "smile" })
        #expect(catalog.matches(prefix: "smile", limit: 5).first?.shortcode == "smile")
    }

    @Test("skin tone applies to a capable emoji")
    func tone() {
        #expect(catalog.glyph(for: "wave", tone: .medium) == "👋🏽")
    }

    @Test("skin tone is ignored on a non-capable emoji")
    func toneIgnored() {
        #expect(catalog.glyph(for: "rocket", tone: .dark) == "🚀")
    }

    @Test("unknown shortcode returns nil")
    func unknown() {
        #expect(catalog.glyph(for: "definitelynotacode") == nil)
    }

    @Test("SkinTone modifier round-trips")
    func modifier() {
        #expect(SkinTone.fromModifier("skin-tone-4") == .medium)
        #expect(SkinTone.fromModifier("skin-tone-1") == nil)
        #expect(SkinTone.fromModifier("nonsense") == nil)
    }
}
```

- [ ] **Step 4: Run the test to verify it fails**

Run: `swift test --filter EmojiCatalogTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'EmojiCatalog' in scope`.

- [ ] **Step 5: Implement `EmojiCatalog.swift`**

Create `Sources/iris/EmojiCatalog.swift`:

```swift
import Foundation

struct EmojiItem: Identifiable, Sendable, Equatable {
    var id: String { shortcode }
    let shortcode: String        // without colons, e.g. "wave"
    let glyph: String            // base glyph, e.g. "👋"
    let supportsSkinTone: Bool
}

enum SkinTone: Int, CaseIterable, Codable, Sendable {
    case none = 1, light = 2, mediumLight = 3, medium = 4, mediumDark = 5, dark = 6

    /// Unified codepoint of the Fitzpatrick modifier, or nil for `.none`.
    var codepoint: String? {
        switch self {
        case .none: return nil
        case .light: return "1F3FB"
        case .mediumLight: return "1F3FC"
        case .medium: return "1F3FD"
        case .mediumDark: return "1F3FE"
        case .dark: return "1F3FF"
        }
    }

    /// Slack modifier shortcode, e.g. "skin-tone-2". Nil for `.none`.
    var modifierName: String? { self == .none ? nil : "skin-tone-\(rawValue)" }

    static func fromModifier(_ name: String) -> SkinTone? {
        let prefix = "skin-tone-"
        guard name.hasPrefix(prefix), let n = Int(name.dropFirst(prefix.count)),
              let tone = SkinTone(rawValue: n), tone != .none else { return nil }
        return tone
    }
}

final class EmojiCatalog: @unchecked Sendable {
    static let shared = EmojiCatalog()

    private var glyphByCode: [String: String] = [:]                 // shortcode -> base glyph
    private var tonedGlyphByCode: [String: [String: String]] = [:]  // shortcode -> tone codepoint -> glyph
    private(set) var items: [EmojiItem] = []                        // one entry per alias, ordered

    init(url: URL? = Bundle.module.url(forResource: "emoji", withExtension: "json")) {
        guard let url, let data = try? Data(contentsOf: url) else { return }
        load(data)
    }

    private struct RawEmoji: Decodable {
        let short_names: [String]
        let unified: String
        let skin_variations: [String: Variation]?
        struct Variation: Decodable { let unified: String }
    }

    private func load(_ data: Data) {
        guard let raw = try? JSONDecoder().decode([RawEmoji].self, from: data) else { return }
        for e in raw {
            let base = Self.scalars(from: e.unified)
            var toned: [String: String] = [:]
            if let sv = e.skin_variations {
                for (tone, v) in sv { toned[tone] = Self.scalars(from: v.unified) }
            }
            let supports = !toned.isEmpty
            for name in e.short_names {
                glyphByCode[name] = base
                if supports { tonedGlyphByCode[name] = toned }
                items.append(EmojiItem(shortcode: name, glyph: base, supportsSkinTone: supports))
            }
        }
    }

    /// "1F44B-1F3FB" -> "👋🏻"
    static func scalars(from unified: String) -> String {
        var out = ""
        for part in unified.split(separator: "-") {
            if let v = UInt32(part, radix: 16), let scalar = Unicode.Scalar(v) {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// Base glyph for a shortcode, applying `tone` when the emoji supports it.
    func glyph(for shortcode: String, tone: SkinTone = .none) -> String? {
        guard let base = glyphByCode[shortcode] else { return nil }
        guard tone != .none, let cp = tone.codepoint,
              let toned = tonedGlyphByCode[shortcode]?[cp] else { return base }
        return toned
    }

    /// Prefix search over all aliases: exact match first, then shorter, then alphabetical.
    func matches(prefix: String, limit: Int = 8) -> [EmojiItem] {
        let q = prefix.lowercased()
        guard !q.isEmpty else { return [] }
        let hits = items.filter { $0.shortcode.hasPrefix(q) }
        let ranked = hits.sorted {
            if ($0.shortcode == q) != ($1.shortcode == q) { return $0.shortcode == q }
            if $0.shortcode.count != $1.shortcode.count { return $0.shortcode.count < $1.shortcode.count }
            return $0.shortcode < $1.shortcode
        }
        return Array(ranked.prefix(limit))
    }
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `swift test --filter EmojiCatalogTests 2>&1 | tail -20`
Expected: PASS (8 tests).

- [ ] **Step 7: Commit**

```bash
git add scripts/fetch-emoji-data.sh Sources/iris/assets/emoji.json Sources/iris/EmojiCatalog.swift Tests/irisTests/EmojiCatalogTests.swift
git commit -m "feat(emoji): vendored emoji-data catalog with skin tones (#22)"
```

---

### Task 2: EmojiTokenizer (pure token + replacement logic)

**Files:**
- Create: `Sources/iris/EmojiTokenizer.swift`
- Test: `Tests/irisTests/EmojiTokenizerTests.swift`

**Interfaces:**
- Consumes: `EmojiCatalog`, `SkinTone` (Task 1).
- Produces:
  - `enum EmojiTokenizer { static func activeToken(in: NSString, caret: Int) -> (query: String, range: NSRange)?; static func completedReplacement(in: NSString, caret: Int, catalog: EmojiCatalog, defaultTone: SkinTone) -> (glyph: String, range: NSRange)? }`
- Note: `caret` is a UTF-16 offset (matches `NSTextView.selectedRange().location`). Returned `NSRange`s are UTF-16 ranges suitable for `NSTextStorage.replaceCharacters(in:with:)`.

- [ ] **Step 1: Write the failing test**

Create `Tests/irisTests/EmojiTokenizerTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@Suite("EmojiTokenizer")
struct EmojiTokenizerTests {
    let catalog = EmojiCatalog.shared

    private func token(_ s: String, _ caret: Int? = nil) -> (query: String, range: NSRange)? {
        let ns = s as NSString
        return EmojiTokenizer.activeToken(in: ns, caret: caret ?? ns.length)
    }
    private func replace(_ s: String, tone: SkinTone = .none) -> (glyph: String, range: NSRange)? {
        let ns = s as NSString
        return EmojiTokenizer.completedReplacement(in: ns, caret: ns.length, catalog: catalog, defaultTone: tone)
    }

    @Test("active token at start of text")
    func atStart() {
        let t = token(":sm")
        #expect(t?.query == "sm")
        #expect(t?.range == NSRange(location: 0, length: 3))
    }

    @Test("active token mid-sentence")
    func midSentence() {
        let t = token("nice work :wav")
        #expect(t?.query == "wav")
        #expect(t?.range == NSRange(location: 10, length: 4))
    }

    @Test("time colon is not a token")
    func timeColon() {
        #expect(token("meet at 10:30") == nil)
    }

    @Test("mid-word colon is not a token")
    func midWord() {
        #expect(token("foo:bar") == nil)
    }

    @Test("bare colon is not a token")
    func bareColon() {
        #expect(token(":") == nil)
    }

    @Test("complete code replaces")
    func completeCode() {
        let r = replace("hi :smile:")
        #expect(r?.glyph == "😄")
        #expect(r?.range == NSRange(location: 3, length: 7))
    }

    @Test("explicit skin-tone modifier replaces and overrides default")
    func explicitTone() {
        let r = replace("hey :wave::skin-tone-4:", tone: .dark)
        #expect(r?.glyph == "👋🏽")
        #expect(r?.range == NSRange(location: 4, length: 19))
    }

    @Test("default tone applies to a bare capable emoji")
    func defaultTone() {
        #expect(replace(":wave:", tone: .medium)?.glyph == "👋🏽")
    }

    @Test("default tone ignored on non-capable emoji")
    func defaultToneIgnored() {
        #expect(replace(":rocket:", tone: .dark)?.glyph == "🚀")
    }

    @Test("invalid code is left literal")
    func invalid() {
        #expect(replace(":notacode:") == nil)
    }

    @Test("lone skin-tone modifier is left literal")
    func loneTone() {
        #expect(replace(":skin-tone-3:") == nil)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter EmojiTokenizerTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'EmojiTokenizer' in scope`.

- [ ] **Step 3: Implement `EmojiTokenizer.swift`**

Create `Sources/iris/EmojiTokenizer.swift`:

```swift
import Foundation

enum EmojiTokenizer {
    private static let colon = unichar(UInt16(UnicodeScalar(":").value))
    private static let allowed = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_+-")

    private static func isAllowed(_ c: unichar) -> Bool {
        guard let s = Unicode.Scalar(c) else { return false }
        return allowed.contains(s)
    }
    private static func isBoundary(before colon: Int, in text: NSString) -> Bool {
        guard colon > 0 else { return true }
        guard let s = Unicode.Scalar(text.character(at: colon - 1)) else { return true }
        return CharacterSet.whitespacesAndNewlines.contains(s)
    }

    /// The `:query` token the caret currently sits at the end of. A token is a `:`
    /// at a word boundary followed by allowed chars, with the caret within the run.
    static func activeToken(in text: NSString, caret: Int) -> (query: String, range: NSRange)? {
        guard caret >= 1, caret <= text.length else { return nil }
        var i = caret
        while i > 0 {
            let c = text.character(at: i - 1)
            if c == colon {
                let open = i - 1
                guard isBoundary(before: open, in: text) else { return nil }
                let query = text.substring(with: NSRange(location: i, length: caret - i))
                return (query, NSRange(location: open, length: caret - open))
            }
            if !isAllowed(c) { return nil }
            i -= 1
        }
        return nil
    }

    /// Reads a `:content:` segment whose closing colon is at `closing`. Returns the
    /// content and the opening colon index, or nil if the pattern doesn't hold.
    private static func segment(endingAt closing: Int, in text: NSString) -> (content: String, open: Int)? {
        guard closing >= 1, text.character(at: closing) == colon else { return nil }
        var i = closing
        while i > 0 {
            let c = text.character(at: i - 1)
            if c == colon {
                let open = i - 1
                let len = closing - i
                guard len > 0 else { return nil }
                return (text.substring(with: NSRange(location: i, length: len)), open)
            }
            if !isAllowed(c) { return nil }
            i -= 1
        }
        return nil
    }

    /// If a complete `:code:` (optionally `:code::skin-tone-N:`) ends exactly at the
    /// caret and resolves, return the glyph and the UTF-16 range to replace.
    static func completedReplacement(in text: NSString, caret: Int,
                                     catalog: EmojiCatalog,
                                     defaultTone: SkinTone) -> (glyph: String, range: NSRange)? {
        guard caret >= 1, text.character(at: caret - 1) == colon else { return nil }
        guard let last = segment(endingAt: caret - 1, in: text) else { return nil }

        if let tone = SkinTone.fromModifier(last.content) {
            // Form: :code::skin-tone-N:  — a base segment closes at last.open - 1.
            guard last.open >= 1, text.character(at: last.open - 1) == colon,
                  let base = segment(endingAt: last.open - 1, in: text),
                  isBoundary(before: base.open, in: text),
                  let glyph = catalog.glyph(for: base.content, tone: tone) else { return nil }
            return (glyph, NSRange(location: base.open, length: caret - base.open))
        } else {
            // Form: :code:  — apply the default tone (ignored when unsupported).
            guard isBoundary(before: last.open, in: text),
                  let glyph = catalog.glyph(for: last.content, tone: defaultTone) else { return nil }
            return (glyph, NSRange(location: last.open, length: caret - last.open))
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter EmojiTokenizerTests 2>&1 | tail -20`
Expected: PASS (11 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/EmojiTokenizer.swift Tests/irisTests/EmojiTokenizerTests.swift
git commit -m "feat(emoji): pure token detection + auto-replace logic (#22)"
```

---

### Task 3: ConfigManager default skin tone + Settings picker

**Files:**
- Modify: `Sources/iris/ConfigManager.swift` (add property + init read)
- Modify: `Sources/iris/SettingsView.swift` (add picker to the Preferences section)
- Test: `Tests/irisTests/EmojiSettingsTests.swift`

**Interfaces:**
- Consumes: `SkinTone` (Task 1).
- Produces: `ConfigManager.defaultEmojiSkinTone: Int` (persisted under `DEFAULT_EMOJI_SKIN_TONE`, defaults to `SkinTone.none.rawValue`).

- [ ] **Step 1: Write the failing test**

Create `Tests/irisTests/EmojiSettingsTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@Suite("Emoji settings")
struct EmojiSettingsTests {
    @Test("default skin tone persists to UserDefaults")
    func persists() {
        let key = "DEFAULT_EMOJI_SKIN_TONE"
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let config = ConfigManager.shared
        config.defaultEmojiSkinTone = SkinTone.dark.rawValue
        #expect(UserDefaults.standard.integer(forKey: key) == 6)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter EmojiSettingsTests 2>&1 | tail -20`
Expected: FAIL — `value of type 'ConfigManager' has no member 'defaultEmojiSkinTone'`.

- [ ] **Step 3: Add the property to ConfigManager**

In `Sources/iris/ConfigManager.swift`, add this property alongside the other `var … { didSet … }` declarations (e.g. right after `copyChatsAsMarkdown`):

```swift
    var defaultEmojiSkinTone: Int {
        didSet { UserDefaults.standard.set(defaultEmojiSkinTone, forKey: "DEFAULT_EMOJI_SKIN_TONE") }
    }
```

- [ ] **Step 4: Initialize it in `init()`**

In `ConfigManager.init()` (around line 190), add:

```swift
        self.defaultEmojiSkinTone = UserDefaults.standard.object(forKey: "DEFAULT_EMOJI_SKIN_TONE") as? Int ?? SkinTone.none.rawValue
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter EmojiSettingsTests 2>&1 | tail -20`
Expected: PASS.

- [ ] **Step 6: Add the Settings picker**

In `Sources/iris/SettingsView.swift`, inside the `Section(header: Text("Preferences")…)` block (right after the `Toggle("Copy chats as Markdown (default)"…)` line), add:

```swift
                    Picker("Default emoji skin tone", selection: $config.defaultEmojiSkinTone) {
                        Text("Default 👋").tag(SkinTone.none.rawValue)
                        Text("Light 👋🏻").tag(SkinTone.light.rawValue)
                        Text("Medium-Light 👋🏼").tag(SkinTone.mediumLight.rawValue)
                        Text("Medium 👋🏽").tag(SkinTone.medium.rawValue)
                        Text("Medium-Dark 👋🏾").tag(SkinTone.mediumDark.rawValue)
                        Text("Dark 👋🏿").tag(SkinTone.dark.rawValue)
                    }
```

- [ ] **Step 7: Build to verify the Settings change compiles**

Run: `swift build 2>&1 | tail -20`
Expected: `Build complete!`

- [ ] **Step 8: Commit**

```bash
git add Sources/iris/ConfigManager.swift Sources/iris/SettingsView.swift Tests/irisTests/EmojiSettingsTests.swift
git commit -m "feat(emoji): default skin-tone preference (#22)"
```

---

### Task 4: EmojiTokenModel (observable glue)

**Files:**
- Create: `Sources/iris/EmojiTokenModel.swift`
- Test: `Tests/irisTests/EmojiTokenModelTests.swift`

**Interfaces:**
- Consumes: `EmojiCatalog`, `EmojiItem`, `SkinTone` (Task 1); `EmojiTokenizer` (Task 2).
- Produces:
  - `@MainActor @Observable final class EmojiTokenModel` with:
    - `var activeQuery: String?`, `var activeRange: NSRange?`, `var suggestions: [EmojiItem]`, `var selectedIndex: Int`, `var defaultTone: SkinTone`
    - `var performReplace: ((_ glyph: String, _ range: NSRange) -> Void)?`
    - `var isShowing: Bool`
    - `func update(text: NSString, caret: Int)`, `func clear()`, `func moveSelection(_:)`, `func commitSelection() -> (glyph: String, range: NSRange)?`, `func commitSelected()`, `func displayGlyph(for: EmojiItem) -> String`
    - `let minQueryLength = 2`

- [ ] **Step 1: Write the failing test**

Create `Tests/irisTests/EmojiTokenModelTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@MainActor
@Suite("EmojiTokenModel")
struct EmojiTokenModelTests {
    @Test("update populates suggestions for a valid query")
    func populates() {
        let m = EmojiTokenModel()
        m.update(text: "hi :sm" as NSString, caret: 6)
        #expect(m.isShowing)
        #expect(m.activeRange == NSRange(location: 3, length: 3))
    }

    @Test("query shorter than the minimum clears the popup")
    func tooShort() {
        let m = EmojiTokenModel()
        m.update(text: "hi :s" as NSString, caret: 5)
        #expect(!m.isShowing)
    }

    @Test("moveSelection wraps around")
    func wraps() {
        let m = EmojiTokenModel()
        m.update(text: ":smi" as NSString, caret: 4)
        #expect(m.selectedIndex == 0)
        m.moveSelection(-1)
        #expect(m.selectedIndex == m.suggestions.count - 1)
        m.moveSelection(1)
        #expect(m.selectedIndex == 0)
    }

    @Test("commitSelection returns a glyph and the active range")
    func commit() {
        let m = EmojiTokenModel()
        m.update(text: ":smile" as NSString, caret: 6)
        let c = m.commitSelection()
        #expect(c?.glyph == "😄")
        #expect(c?.range == NSRange(location: 0, length: 6))
    }

    @Test("commitSelected forwards to performReplace and clears")
    func commitSelected() {
        let m = EmojiTokenModel()
        var captured: (String, NSRange)? = nil
        m.performReplace = { g, r in captured = (g, r) }
        m.update(text: ":smile" as NSString, caret: 6)
        m.commitSelected()
        #expect(captured?.0 == "😄")
        #expect(!m.isShowing)
    }

    @Test("displayGlyph honors the default tone")
    func toned() {
        let m = EmojiTokenModel()
        m.defaultTone = .medium
        let item = EmojiItem(shortcode: "wave", glyph: "👋", supportsSkinTone: true)
        #expect(m.displayGlyph(for: item) == "👋🏽")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter EmojiTokenModelTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'EmojiTokenModel' in scope`.

- [ ] **Step 3: Implement `EmojiTokenModel.swift`**

Create `Sources/iris/EmojiTokenModel.swift`:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class EmojiTokenModel {
    var activeQuery: String? = nil
    var activeRange: NSRange? = nil
    var suggestions: [EmojiItem] = []
    var selectedIndex: Int = 0
    var defaultTone: SkinTone = .none

    /// Set by the composer's coordinator; performs the actual text-storage edit.
    var performReplace: ((_ glyph: String, _ range: NSRange) -> Void)? = nil

    let minQueryLength = 2
    private let catalog: EmojiCatalog

    init(catalog: EmojiCatalog = .shared) { self.catalog = catalog }

    var isShowing: Bool { !suggestions.isEmpty }

    /// Recompute popup state from the composer's text + caret.
    func update(text: NSString, caret: Int) {
        guard let token = EmojiTokenizer.activeToken(in: text, caret: caret),
              token.query.count >= minQueryLength else { clear(); return }
        let hits = catalog.matches(prefix: token.query, limit: 8)
        guard !hits.isEmpty else { clear(); return }
        if suggestions.map(\.id) != hits.map(\.id) { selectedIndex = 0 }
        activeQuery = token.query
        activeRange = token.range
        suggestions = hits
    }

    func clear() {
        activeQuery = nil
        activeRange = nil
        suggestions = []
        selectedIndex = 0
    }

    func moveSelection(_ delta: Int) {
        guard !suggestions.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + suggestions.count) % suggestions.count
    }

    /// Glyph + range for the highlighted suggestion (does not mutate state).
    func commitSelection() -> (glyph: String, range: NSRange)? {
        guard let range = activeRange, suggestions.indices.contains(selectedIndex) else { return nil }
        let item = suggestions[selectedIndex]
        let glyph = catalog.glyph(for: item.shortcode, tone: defaultTone) ?? item.glyph
        return (glyph, range)
    }

    /// Insert the highlighted suggestion via `performReplace`, then clear.
    func commitSelected() {
        guard let (glyph, range) = commitSelection() else { return }
        performReplace?(glyph, range)
        clear()
    }

    /// The glyph to show in a popup row, honoring the default tone.
    func displayGlyph(for item: EmojiItem) -> String {
        catalog.glyph(for: item.shortcode, tone: defaultTone) ?? item.glyph
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter EmojiTokenModelTests 2>&1 | tail -20`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/EmojiTokenModel.swift Tests/irisTests/EmojiTokenModelTests.swift
git commit -m "feat(emoji): observable token model driving the popup (#22)"
```

---

### Task 5: ComposerTextView — NSTextView parity replacement for the TextField

**Files:**
- Create: `Sources/iris/ComposerTextView.swift`
- Modify: `Sources/iris/ChatView.swift` (replace `TextField` in `messageInputBar`, ~lines 456-477)
- Test: none (AppKit glue; GUI-verified — see Step 4)

**Interfaces:**
- Produces: `struct ComposerTextView: NSViewRepresentable { @Binding var text: String; var onSubmit: () -> Void }` (the emoji model is added in Task 6). Coordinator exposes `func replace(range: NSRange, with: String)` and holds `weak var textView`.

**This task delivers behavior parity only** — the composer must work exactly like the old `TextField` (type, send on Enter, newline on Shift+Enter, grows vertically). Emoji wiring lands in Task 6.

- [ ] **Step 1: Implement `ComposerTextView.swift`**

Create `Sources/iris/ComposerTextView.swift`:

```swift
import SwiftUI
import AppKit

/// An NSTextView-backed chat composer. Replaces the SwiftUI TextField so the true
/// caret is available for emoji shortcode handling. Preserves Enter = send and
/// Shift+Enter = newline.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let tv = KeyCatchingTextView()
        tv.delegate = context.coordinator
        tv.coordinator = context.coordinator
        tv.string = text
        tv.font = .systemFont(ofSize: NSFont.systemFontSize)
        tv.isRichText = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 4, height: 8)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.documentView = tv
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder
        context.coordinator.textView = tv
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if tv.string != text {
            tv.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: NSTextView?
        var isEditing = false

        init(_ parent: ComposerTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isEditing, let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            handleTextChange(tv)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isEditing, let tv = notification.object as? NSTextView else { return }
            handleSelectionChange(tv)
        }

        /// Replaced in place in Task 6 to drive the emoji popup. No-op for parity.
        func handleTextChange(_ tv: NSTextView) {}
        func handleSelectionChange(_ tv: NSTextView) {}

        /// Replace a UTF-16 range with a string; place the caret after it.
        func replace(range: NSRange, with str: String) {
            guard let tv = textView, tv.shouldChangeText(in: range, replacementString: str) else { return }
            isEditing = true
            tv.textStorage?.replaceCharacters(in: range, with: str)
            tv.didChangeText()
            let newCaret = range.location + (str as NSString).length
            tv.setSelectedRange(NSRange(location: newCaret, length: 0))
            parent.text = tv.string
            isEditing = false
            afterProgrammaticEdit(tv)
        }

        /// Replaced in place in Task 6 to refresh popup state after a programmatic edit.
        func afterProgrammaticEdit(_ tv: NSTextView) {}
    }
}

/// NSTextView that routes Return / arrows / Tab / Escape through the coordinator.
final class KeyCatchingTextView: NSTextView {
    weak var coordinator: ComposerTextView.Coordinator?

    override func keyDown(with event: NSEvent) {
        guard let coordinator else { super.keyDown(with: event); return }
        let shift = event.modifierFlags.contains(.shift)
        switch event.keyCode {
        case 36, 76: // Return / Enter
            if shift {
                super.keyDown(with: event)              // newline
            } else if coordinator.handleNavKey(.enter) {
                return                                   // popup consumed it
            } else {
                coordinator.parent.onSubmit()
            }
        case 48: // Tab
            if !coordinator.handleNavKey(.tab) { super.keyDown(with: event) }
        case 125: // Down arrow
            if !coordinator.handleNavKey(.down) { super.keyDown(with: event) }
        case 126: // Up arrow
            if !coordinator.handleNavKey(.up) { super.keyDown(with: event) }
        case 53: // Escape
            if !coordinator.handleNavKey(.escape) { super.keyDown(with: event) }
        default:
            super.keyDown(with: event)
        }
    }
}

extension ComposerTextView.Coordinator {
    enum NavKey { case up, down, tab, enter, escape }
    /// Replaced in place in Task 6 to consume nav keys when the popup is open. Parity: no-op.
    func handleNavKey(_ key: NavKey) -> Bool { false }
}
```

- [ ] **Step 2: Replace the TextField in `messageInputBar`**

In `Sources/iris/ChatView.swift`, replace the `TextField(…)` and its modifiers (the block from `TextField("Message Iris...", …)` through the closing of `.onKeyPress { … }`, roughly lines 456-477) with:

```swift
            ComposerTextView(text: $inputText, onSubmit: submit)
                .frame(minHeight: 24, maxHeight: 120)
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )
```

Leave the surrounding `HStack`, the send `Button`, and the `submit()` method unchanged.

- [ ] **Step 3: Build**

Run: `swift build 2>&1 | tail -20`
Expected: `Build complete!`

- [ ] **Step 4: GUI verification (manual — ask the user to run `swift run`)**

Report to the human partner and request they verify in the running app:
- Typing text appears normally; the field grows vertically as lines are added.
- **Enter** sends the message; **Shift+Enter** inserts a newline.
- The slash-command popup still appears when typing `/` at the start and inserting a command still works.

Do not proceed to Task 6 until parity is confirmed.

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/ComposerTextView.swift Sources/iris/ChatView.swift
git commit -m "feat(emoji): NSTextView-backed composer (parity) (#22)"
```

---

### Task 6: Wire the emoji popup, keyboard nav, and auto-replace

**Files:**
- Create: `Sources/iris/EmojiAutoCompleteView.swift`
- Modify: `Sources/iris/ComposerTextView.swift` (add `emoji` model; override the coordinator hooks)
- Modify: `Sources/iris/ChatView.swift` (own the model, render the popup, feed default tone, clear on send)
- Test: none (integration/AppKit; GUI-verified — see Step 6)

**Interfaces:**
- Consumes: `EmojiTokenModel` (Task 4), `EmojiTokenizer` (Task 2), `EmojiCatalog` (Task 1), `ComposerTextView` (Task 5), `ConfigManager.defaultEmojiSkinTone` (Task 3).

- [ ] **Step 1: Create `EmojiAutoCompleteView.swift`**

Create `Sources/iris/EmojiAutoCompleteView.swift`:

```swift
import SwiftUI

struct EmojiAutoCompleteView: View {
    var model: EmojiTokenModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "face.smiling")
                    .foregroundColor(.irisIndigo)
                    .font(.caption)
                Text("EMOJI")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(model.suggestions.enumerated()), id: \.element.id) { idx, item in
                    Button(action: { model.selectedIndex = idx; model.commitSelected() }) {
                        HStack(spacing: 10) {
                            Text(model.displayGlyph(for: item)).font(.title3)
                            Text(":\(item.shortcode):")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.irisIndigo)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(idx == model.selectedIndex
                                ? Color.irisIndigo.opacity(0.18)
                                : Color.primary.opacity(0.04))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(.thinMaterial)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.bottom, 4)
    }
}
```

- [ ] **Step 2: Add the `emoji` model to `ComposerTextView`**

In `Sources/iris/ComposerTextView.swift`, add a stored property to the struct (right after `var onSubmit: () -> Void`):

```swift
    var emoji: EmojiTokenModel
```

- [ ] **Step 3: Wire the coordinator to the model**

In `ComposerTextView.makeNSView`, before `return scroll`, connect the model's replace hook:

```swift
        context.coordinator.connectModel()
```

Then replace the four placeholder hook methods in `Coordinator` (`handleTextChange`, `handleSelectionChange`, `afterProgrammaticEdit`, and the `handleNavKey` extension) with real implementations:

```swift
        func connectModel() {
            parent.emoji.performReplace = { [weak self] glyph, range in
                self?.replace(range: range, with: glyph)
            }
        }

        func handleTextChange(_ tv: NSTextView) {
            let caret = tv.selectedRange().location
            let ns = tv.string as NSString
            if let (glyph, range) = EmojiTokenizer.completedReplacement(
                in: ns, caret: caret, catalog: .shared, defaultTone: parent.emoji.defaultTone) {
                replace(range: range, with: glyph)
                parent.emoji.clear()
                return
            }
            parent.emoji.update(text: ns, caret: caret)
        }

        func handleSelectionChange(_ tv: NSTextView) {
            parent.emoji.update(text: tv.string as NSString, caret: tv.selectedRange().location)
        }

        func afterProgrammaticEdit(_ tv: NSTextView) {
            parent.emoji.update(text: tv.string as NSString, caret: tv.selectedRange().location)
        }
```

Note: change the base declarations of `handleTextChange`, `handleSelectionChange`, and `afterProgrammaticEdit` in Task 5's file from plain methods to `func … {}` that are overridable — mark them and their overrides as needed. Since `Coordinator` is a single class (not subclassed), do NOT use `override`; instead replace the empty method bodies directly with the implementations above (drop the `override` keyword). The four methods are edited in place.

And replace the `handleNavKey` extension method body:

```swift
extension ComposerTextView.Coordinator {
    enum NavKey { case up, down, tab, enter, escape }

    func handleNavKey(_ key: NavKey) -> Bool {
        guard parent.emoji.isShowing else { return false }
        switch key {
        case .up:     parent.emoji.moveSelection(-1)
        case .down:   parent.emoji.moveSelection(1)
        case .tab, .enter: parent.emoji.commitSelected()
        case .escape: parent.emoji.clear()
        }
        return true
    }
}
```

(Remove the `@objc` marker and the parity `false` body from Task 5.)

- [ ] **Step 4: Own the model and render the popup in `ChatView`**

In `Sources/iris/ChatView.swift`:

1. Add a state property near `@State private var inputText = ""`:

```swift
    @State private var emojiModel = EmojiTokenModel()
```

2. In the composer VStack, directly above the `SlashCommandAutoCompleteView` block (near line 213), add:

```swift
                    if emojiModel.isShowing {
                        EmojiAutoCompleteView(model: emojiModel)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
```

3. Pass the model into the composer (update the Task 5 call site):

```swift
            ComposerTextView(text: $inputText, onSubmit: submit, emoji: emojiModel)
```

4. Keep the default tone in sync. Add these modifiers to the composer (or the enclosing view that has access to `config`):

```swift
                .onAppear { emojiModel.defaultTone = SkinTone(rawValue: config.defaultEmojiSkinTone) ?? .none }
                .onChange(of: config.defaultEmojiSkinTone) { _, new in
                    emojiModel.defaultTone = SkinTone(rawValue: new) ?? .none
                }
```

If `ChatView` does not already hold a `config` reference, add `private let config = ConfigManager.shared` near the other stored properties.

5. Clear the popup on send. In `submit()` (near line 449, after `inputText = ""`), add:

```swift
        emojiModel.clear()
```

- [ ] **Step 5: Build**

Run: `swift build 2>&1 | tail -20`
Expected: `Build complete!`

- [ ] **Step 6: GUI verification (manual — ask the user to run `swift run`)**

Report to the human partner and request they verify:
- Typing `:sm` opens the emoji popup; `↑/↓` move the highlight; `Tab`/`Enter` insert the highlighted glyph at the caret; `Esc` dismisses; clicking a row inserts it.
- Typing a full `:smile:` auto-replaces to 😄 inline, including **mid-sentence** (caret parked in the middle).
- `:wave::skin-tone-4:` produces 👋🏽; with a default tone set in Settings, a bare `:wave:` honors it while `:rocket:` is unaffected.
- Regression: Enter still sends, Shift+Enter still newlines, the slash popup still works, and slash + emoji popups never appear simultaneously.

- [ ] **Step 7: Run the full unit suite**

Run: `swift test 2>&1 | tail -20`
Expected: all tests pass (existing suite + `EmojiCatalogTests`, `EmojiTokenizerTests`, `EmojiSettingsTests`, `EmojiTokenModelTests`).

- [ ] **Step 8: Commit**

```bash
git add Sources/iris/EmojiAutoCompleteView.swift Sources/iris/ComposerTextView.swift Sources/iris/ChatView.swift
git commit -m "feat(emoji): popup, keyboard nav, and inline auto-replace (#22)"
```

---

## Notes for the implementer

- `swift test` builds the whole package (MLX/ONNX deps included) and can be slow on a cold build; use `--filter <SuiteName>` while iterating, and run the full suite once at the end (Task 6, Step 7).
- The `Coordinator` in Task 5 defines `handleTextChange`, `handleSelectionChange`, `afterProgrammaticEdit`, and `handleNavKey` as no-op/parity methods; Task 6 replaces those bodies in place (no subclassing, no `override`). This lets Task 5 ship and be reviewed as pure TextField parity before emoji behavior is layered on.
- Slash and emoji popups are mutually exclusive by construction (slash matches only at string start via `SlashCommandItem.matches`; emoji only inside a boundary `:` token) — but confirm it during Task 6 GUI verification.
- **Swift 6 concurrency:** `EmojiTokenModel` is `@MainActor`. The `Coordinator` touches it from `NSTextViewDelegate` callbacks and `KeyCatchingTextView.keyDown`, all of which run on the main thread. If strict-concurrency errors appear (e.g. "call to main actor-isolated … in a synchronous nonisolated context"), annotate `Coordinator` with `@MainActor` (and, if needed, assert `MainActor.assumeIsolated` at the delegate entry points). Prefer `@MainActor` on the `Coordinator` over sprinkling `Task { @MainActor in … }`, which would make the caret/replace edits async and race the keystroke.
