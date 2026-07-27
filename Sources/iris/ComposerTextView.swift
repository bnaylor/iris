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
            let sel = tv.selectedRange()
            tv.string = text
            let len = (text as NSString).length
            tv.setSelectedRange(NSRange(location: min(sel.location, len), length: 0))
        }
    }

    @MainActor
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
