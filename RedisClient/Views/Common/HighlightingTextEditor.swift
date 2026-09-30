import SwiftUI
import AppKit

/// Editable multi-line text (NSTextView) that highlights all matches of a search
/// term, marks the active match, and scrolls it into view. Used by the value
/// editor so find-in-value works while editing (SwiftUI's TextEditor can't
/// highlight or scroll to a range).
struct HighlightingTextEditor: NSViewRepresentable {
    @Binding var text: String
    var highlight: String = ""
    /// Occurrence index (0-based) to treat as the active match.
    var activeMatch: Int = 0
    var fontSize: CGFloat = 14

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
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        context.coordinator.textView = tv
        tv.string = text
        context.coordinator.apply(term: highlight, active: activeMatch, scroll: false)
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = nsView.documentView as? NSTextView else { return }
        if tv.string != text {
            tv.string = text
        }
        if abs((tv.font?.pointSize ?? 0) - fontSize) > 0.5 {
            tv.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        // Scroll only when the search moved (term/active changed), not on typing.
        let moved = context.coordinator.lastTerm != highlight || context.coordinator.lastActive != activeMatch
        context.coordinator.apply(term: highlight, active: activeMatch, scroll: moved)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: HighlightingTextEditor
        weak var textView: NSTextView?
        var lastTerm = ""
        var lastActive = -1
        init(_ parent: HighlightingTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            apply(term: parent.highlight, active: parent.activeMatch, scroll: false)
        }

        /// Highlight all matches (yellow), the active one (orange), and optionally
        /// scroll the active match into view.
        func apply(term: String, active: Int, scroll: Bool) {
            lastTerm = term
            lastActive = active
            guard let tv = textView, let storage = tv.textStorage else { return }
            let ns = tv.string as NSString
            let full = NSRange(location: 0, length: ns.length)
            storage.beginEditing()
            storage.removeAttribute(.backgroundColor, range: full)

            let t = term.trimmingCharacters(in: .whitespaces)
            var activeRange: NSRange?
            if !t.isEmpty {
                var searchLoc = 0
                var idx = 0
                while searchLoc < ns.length {
                    let r = ns.range(of: t, options: .caseInsensitive,
                                     range: NSRange(location: searchLoc, length: ns.length - searchLoc))
                    if r.location == NSNotFound { break }
                    let isActive = idx == active
                    let color: NSColor = isActive
                        ? NSColor.systemOrange.withAlphaComponent(0.6)
                        : NSColor.systemYellow.withAlphaComponent(0.4)
                    storage.addAttribute(.backgroundColor, value: color, range: r)
                    if isActive { activeRange = r }
                    searchLoc = r.location + max(1, r.length)
                    idx += 1
                }
            }
            storage.endEditing()

            if scroll, let ar = activeRange {
                tv.scrollRangeToVisible(ar)
            }
        }
    }
}
