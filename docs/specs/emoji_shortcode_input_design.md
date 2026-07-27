---
type: design
title: Emoji Shortcode Input Support
description: Slack/Discord/Apple-level :emoji: shortcode entry in the chat composer, with autocomplete popup, inline auto-replace, and skin-tone support.
tags: [ui, composer, emoji, chatview]
timestamp: 2026-07-27
---

# Emoji Shortcode Input Support

Closes [#22](https://github.com/bnaylor/iris/issues/22).

## Goal

Let users type emoji in the chat composer using the common `:shortcode:` syntax
with a completeness bar set by Slack/Discord/Apple — not a hardcoded top-20. Two
interaction modes work together:

1. **Autocomplete popup** — typing `:sm` opens a keyboard-navigable list of
   matches; ↑/↓ move, Tab/Enter insert, Esc dismisses.
2. **Inline auto-replace** — typing a complete valid `:smile:` swaps it for 😄 in
   place, at the caret.

Skin-tone modifiers (`:wave::skin-tone-4:` → 👋🏾) are supported, plus a
default-skin-tone preference in Settings that bare skin-capable emoji honor.

## Non-Goals

- Retrofitting keyboard navigation onto the existing slash-command popup (the nav
  code will be reusable, but slash stays click-only for now).
- A graphical emoji picker / grid. This is shortcode-driven text entry only.
- Custom/uploaded emoji (`:my_custom_thing:`). Standard Unicode only.

## Data Source

`iamcal/emoji-data` — the same emoji database Slack uses. MIT licensed.

- Pinned to upstream commit `0977050` (`097705020bcf82331c9ef10df3425aad15f5043c`).
- File: `emoji.json`, ~1.3 MB, 1,911 entries.
- Vendored into `Sources/iris/assets/emoji.json` and shipped via the existing
  `Package.swift` `.process("assets")` resource rule; loaded with
  `Bundle.module.url(forResource: "emoji", withExtension: "json")` (same idiom as
  `SYSTEM.md`, `iris-icon.png`).
- `scripts/fetch-emoji-data.sh` (re)downloads the pinned file so the vendored copy
  is reproducible without Node/npm.

### Relevant fields per entry

```json
{
  "short_names": ["wave"],
  "unified": "1F44B",
  "skin_variations": {
    "1F3FB": { "unified": "1F44B-1F3FB" },
    "1F3FC": { "unified": "1F44B-1F3FC" },
    ...
    "1F3FF": { "unified": "1F44B-1F3FF" }
  }
}
```

- `unified` is dash-joined hex codepoints. Convert each hex group to a
  `Unicode.Scalar` and concatenate to build the glyph
  (`"1F44B-1F3FB"` → 👋🏻).
- `short_names` holds every alias; **all** map to the same glyph.
- `skin_variations` present ⇒ the emoji is skin-tone-capable. Keys are the tone
  codepoints `1F3FB`…`1F3FF`, corresponding to `:skin-tone-2:`…`:skin-tone-6:`
  (there is no `:skin-tone-1:` — that is the default yellow / no modifier).

## Components

### 1. `EmojiCatalog` (pure logic, unit-tested)

Loads and indexes the dataset. No UI, no AppKit.

```
struct EmojiItem: Identifiable, Sendable, Equatable {
    var id: String { shortcode }
    let shortcode: String        // without colons, e.g. "wave"
    let glyph: String            // base glyph, e.g. "👋"
    let supportsSkinTone: Bool
}

enum SkinTone: Int, CaseIterable, Codable {  // rawValue = Slack tone number
    case none = 1, light = 2, mediumLight = 3, medium = 4, mediumDark = 5, dark = 6
    var codepoint: String? { ... }   // nil for .none, "1F3FB"… for 2…6
}

final class EmojiCatalog {
    static let shared = EmojiCatalog()

    /// Prefix search over all short_names, ranked (exact first, then
    /// prefix, then length). Capped at `limit` results.
    func matches(prefix: String, limit: Int = 8) -> [EmojiItem]

    /// Glyph for a shortcode, applying an explicit tone if the emoji supports it.
    func glyph(for shortcode: String, tone: SkinTone = .none) -> String?
}
```

Parsing builds two maps: `shortcode → base glyph` and
`shortcode → toneCodepoint → toned glyph`, plus the ordered `[EmojiItem]` for
search. Built once at first access.

### 2. `ComposerTextView: NSViewRepresentable` (replaces the `TextField`)

An `NSTextView`-backed composer that exposes the real caret. Replaces the current
SwiftUI `TextField(axis: .vertical)` in `messageInputBar`.

Responsibilities:
- Two-way bind the text (`inputText`).
- Re-home current key behavior: **Enter = send**, **Shift+Enter = newline**
  (currently in `ChatView.messageInputBar`'s `.onKeyPress`).
- Expose an **active token** derived from the caret: the `:query` the caret sits
  inside/at the end of, and its `NSRange`. A token is a `:` that is at a **word
  boundary** (preceded by whitespace or the start of the text) followed by
  `[a-z0-9_+-]` characters, with the caret at or immediately after the run.
- Insertion API: replace a given `NSRange` with a string and place the caret
  after it (used by both popup insert and auto-replace).
- Forward navigation keys (↑/↓/Tab/Enter/Esc) to the popup controller **only
  while the emoji popup is open**; otherwise Enter sends.

The slash-command popup logic is unchanged; only the underlying field swaps. Slash
matching still keys off the whole-string prefix as today.

### 3. `EmojiTokenModel` (glue state, `@Observable`)

Bridges the composer and the views. Holds:
- `activeQuery: String?` and `activeRange: NSRange?` (from the composer).
- `suggestions: [EmojiItem]` (from `EmojiCatalog.matches`).
- `selectedIndex: Int` (keyboard highlight).
- `defaultTone: SkinTone` (from Settings).

Exposes `moveSelection(_:)`, `commitSelection()` (insert highlighted glyph at
`activeRange`), and `autoReplaceIfComplete()`.

### 4. `EmojiAutoCompleteView`

Mirrors `SlashCommandAutoCompleteView` (same container styling / placement above
`messageInputBar`). Adds a highlighted row bound to `selectedIndex`. Each row: the
glyph, `:shortcode:`, click-to-insert. Shows the glyph rendered with `defaultTone`
when the emoji is skin-capable.

Trigger to show: active query exists AND `query.count >= 2` (kills false-fires on
lone colons and `10:30`).

### 5. Auto-replace pass

On every text change, after updating the active token:
- If the text ending at the caret contains a **complete** `:code:` (optionally
  immediately followed by `::skin-tone-N:`) where `code` is valid, replace that
  range with the glyph (applying tone: explicit modifier wins, else `defaultTone`
  if the emoji is skin-capable).
- Invalid codes are left as literal text.
- Only the token ending at the caret is considered, so earlier literal `:foo:`
  the user chose to keep are untouched.

### 6. Settings: default skin tone

A picker (None + the 5 tones, light→dark — i.e. `SkinTone` cases 2…6 — shown as
swatches or toned 👋) persisted in the existing settings store. Applied to bare skin-capable emoji at insert/replace time.
Explicit `::skin-tone-N:` in the text always overrides.

## Data Flow

```
keystroke → NSTextView updates inputText binding
          → composer recomputes active token from caret (query + range)
          → EmojiTokenModel:
               • query length >= 2  → matches() → popup shows
               • complete :code:    → autoReplaceIfComplete() swaps glyph
navigation (popup open): ↑/↓ moveSelection · Tab/Enter commitSelection · Esc clear
click on row: commit that item
commit: composer replaces activeRange with glyph, caret placed after
```

## Testing

**Unit-tested (`EmojiCatalog` + token/replacement logic — pure, no AppKit):**
- Dataset parses: count > 1,900; `wave` → 👋; a multi-scalar sequence emoji builds
  correctly.
- Aliases: two short_names for the same emoji both resolve to the same glyph.
- `matches(prefix:)`: exact-before-prefix ranking; cap respected; empty for junk.
- Skin tone: `glyph(for:"wave", tone:.mediumDark)` → 👋🏾; tone ignored on a
  non-capable emoji (e.g. `:rocket:`).
- Token detection: `:` at word boundary with ≥2 chars is a token; `10:30` is not;
  a `:` mid-word (`foo:bar`) is not.
- Replacement: `":smile:"` at caret → 😄; `":wave::skin-tone-4:"` → 👋🏽; invalid
  `":notacode:"` left literal; default tone applied to bare capable emoji.

**GUI-verified by the user (the `NSTextView` glue — same split as the rest of the
app):** caret-accurate insertion mid-sentence, arrow/Tab/Enter/Esc behavior,
Enter=send / Shift+Enter=newline still correct, coexistence with the slash popup.

## Risks / Notes

- Swapping the composer from `TextField` to `NSViewRepresentable` is the main blast
  radius: Enter/Shift+Enter and the slash popup must keep working. These are
  explicit test/verify items.
- The two popups (slash + emoji) must never show at once — slash only matches at
  string start, emoji only inside a `:` token, so they are mutually exclusive by
  construction; still worth a manual check.
