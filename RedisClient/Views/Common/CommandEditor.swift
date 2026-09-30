import SwiftUI
import AppKit

/// Multi-line command editor (NSTextView) for the Console. Reports the caret
/// offset (for token/argument-aware suggestions), applies lightweight syntax
/// highlighting, and forwards key commands so the suggestion list can be driven
/// from the keyboard. macOS 13 has no SwiftUI `.onKeyPress`, hence AppKit.
///
/// Keys: Enter runs (onSubmit); Shift+Enter inserts a newline; ⌘Enter also runs;
/// Up/Down and Tab/Esc are forwarded (onMoveUp/Down, onAccept/onCancel).
struct CommandEditor: NSViewRepresentable {
    @Binding var text: String
    /// Caret position as a UTF-16 offset into `text` (for arg detection).
    @Binding var caret: Int
    /// Reported content height so the container can size to the text (1..N lines).
    @Binding var contentHeight: CGFloat
    var fontSize: CGFloat = 14

    /// Return true if the key was consumed (a suggestion list handled it); false
    /// lets the text view move the caret between lines as usual.
    var onMoveUp: () -> Bool = { false }
    var onMoveDown: () -> Bool = { false }
    var onAccept: () -> Bool = { false }
    var onCancel: () -> Bool = { false }
    var onSubmit: () -> Void = {}

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        guard let tv = scroll.documentView as? NSTextView else { return scroll }

        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true

        context.coordinator.textView = tv
        tv.string = text
        context.coordinator.applyHighlight()
        context.coordinator.reportHeight()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text {
            let sel = tv.selectedRange()
            tv.string = text
            context.coordinator.applyHighlight()
            // Keep caret valid after an external text change (history / complete).
            let loc = min(caret, (text as NSString).length)
            tv.setSelectedRange(NSRange(location: loc, length: 0))
            _ = sel
            context.coordinator.reportHeight()
        }
        if abs(tv.font!.pointSize - fontSize) > 0.5 {
            tv.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
            context.coordinator.applyHighlight()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CommandEditor
        weak var textView: NSTextView?
        init(_ parent: CommandEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            parent.caret = tv.selectedRange().location
            applyHighlight()
            reportHeight()
        }

        /// Publish the laid-out text height so SwiftUI can grow the editor.
        func reportHeight() {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let h = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if abs(self.parent.contentHeight - h) > 0.5 { self.parent.contentHeight = h }
            }
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.caret = tv.selectedRange().location
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.insertNewline(_:)):
                // Shift+Enter → newline; plain Enter → run.
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    tv.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                parent.onSubmit()
                return true
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                parent.onSubmit(); return true
            case #selector(NSResponder.moveUp(_:)):
                return parent.onMoveUp()
            case #selector(NSResponder.moveDown(_:)):
                return parent.onMoveDown()
            case #selector(NSResponder.insertTab(_:)):
                if parent.onAccept() { return true }
                tv.insertText("  ", replacementRange: tv.selectedRange())  // indent
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                return parent.onCancel()
            default:
                return false
            }
        }

        /// Lightweight highlighting: command name (first token) in accent, quoted
        /// strings in green, the rest default. Cheap enough to run on each change.
        func applyHighlight() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let ns = tv.string as NSString
            let full = NSRange(location: 0, length: ns.length)
            let base = NSColor.labelColor
            storage.beginEditing()
            storage.removeAttribute(.foregroundColor, range: full)
            storage.addAttribute(.foregroundColor, value: base, range: full)

            // First token (command name) — accent color from the active theme.
            let accentNS = NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                let t = isDark ? AccentTheme.current.dark : AccentTheme.current.light
                return NSColor(red: t.0, green: t.1, blue: t.2, alpha: 1)
            }
            let firstSpace = ns.rangeOfCharacter(from: .whitespacesAndNewlines)
            let nameLen = firstSpace.location == NSNotFound ? ns.length : firstSpace.location
            if nameLen > 0 {
                storage.addAttribute(.foregroundColor, value: accentNS,
                                     range: NSRange(location: 0, length: nameLen))
            }

            // Quoted strings — JSON string color from the theme (constant across accents).
            let stringNS = NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                return isDark
                    ? NSColor(red: 0.48, green: 0.82, blue: 0.56, alpha: 1)
                    : NSColor(red: 0.13, green: 0.55, blue: 0.30, alpha: 1)
            }
            highlightQuotes(in: ns, storage: storage, quote: "\"", color: stringNS)
            highlightQuotes(in: ns, storage: storage, quote: "'", color: stringNS)
            storage.endEditing()
        }

        private func highlightQuotes(in ns: NSString, storage: NSTextStorage, quote: Character, color: NSColor) {
            let q = String(quote)
            var searchStart = 0
            while searchStart < ns.length {
                let open = ns.range(of: q, range: NSRange(location: searchStart, length: ns.length - searchStart))
                if open.location == NSNotFound { break }
                let afterOpen = open.location + 1
                guard afterOpen <= ns.length else { break }
                let close = ns.range(of: q, range: NSRange(location: afterOpen, length: ns.length - afterOpen))
                if close.location == NSNotFound {
                    storage.addAttribute(.foregroundColor, value: color,
                                         range: NSRange(location: open.location, length: ns.length - open.location))
                    break
                }
                let len = close.location - open.location + 1
                storage.addAttribute(.foregroundColor, value: color,
                                     range: NSRange(location: open.location, length: len))
                searchStart = close.location + 1
            }
        }
    }
}
