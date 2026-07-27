import SwiftUI
import AppKit

/// An NSTextView-backed chat composer. Replaces the SwiftUI TextField so the true
/// caret is available for emoji shortcode handling. Preserves Enter = send and
/// Shift+Enter = newline.
struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var emoji: EmojiTokenModel
    var onHeightChange: (CGFloat) -> Void = { _ in }

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
        context.coordinator.measureHeight(tv)
        context.coordinator.connectModel()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tv = nsView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        if tv.string != text {
            tv.string = text
            let len = (text as NSString).length
            tv.setSelectedRange(NSRange(location: len, length: 0))
        }
        context.coordinator.measureHeight(tv)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var textView: NSTextView?
        var isEditing = false
        private var lastHeight: CGFloat = 0

        init(_ parent: ComposerTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isEditing, let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            handleTextChange(tv)
            measureHeight(tv)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isEditing, let tv = notification.object as? NSTextView else { return }
            handleSelectionChange(tv)
        }

        /// Measure the laid-out text height and report it to SwiftUI (async to avoid
        /// mutating view state mid-update). Skips until the view has a real width,
        /// otherwise text wraps to zero width and reports a bogus height.
        func measureHeight(_ tv: NSTextView) {
            guard tv.bounds.width > 0, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let h = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2
            guard abs(h - lastHeight) > 0.5 else { return }
            lastHeight = h
            let report = parent.onHeightChange
            DispatchQueue.main.async { report(h) }
        }

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
            measureHeight(tv)
        }

        func afterProgrammaticEdit(_ tv: NSTextView) {
            parent.emoji.update(text: tv.string as NSString, caret: tv.selectedRange().location)
        }
    }
}

/// NSTextView that routes Return / arrows / Tab / Escape through the coordinator.
final class KeyCatchingTextView: NSTextView {
    weak var coordinator: ComposerTextView.Coordinator?

    override func keyDown(with event: NSEvent) {
        guard let coordinator else { super.keyDown(with: event); return }
        let flags = event.modifierFlags
        switch event.keyCode {
        case 36, 76: // Return / Enter
            if flags.contains(.shift) {
                super.keyDown(with: event)              // Shift+Enter → newline
            } else if flags.contains(.option) || flags.contains(.control) {
                insertNewline(nil)                      // Option/Ctrl+Enter → newline (from PR #24)
            } else if coordinator.handleNavKey(.enter) {
                return                                   // popup consumed it (emoji commit)
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
