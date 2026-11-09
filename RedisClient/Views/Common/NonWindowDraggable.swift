import SwiftUI
import AppKit

/// Hosts SwiftUI content in its own `NSHostingView` that refuses to move the
/// window. Needed for draggable content in the custom titlebar: there the
/// hit view is the root hosting view, whose `mouseDownCanMoveWindow` is true,
/// so AppKit drags the whole window (titlebar + `isMovableByWindowBackground`)
/// before SwiftUI's `.onDrag` ever sees the gesture. A blocker NSView behind
/// the content doesn't help — it's never the hit view.
///
/// Environment does not cross the hosting boundary: pass any environment
/// objects / values the content needs explicitly.
struct NonWindowDraggable<Content: View>: NSViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> Host {
        let host = Host(rootView: content)
        host.setContentHuggingPriority(.defaultLow, for: .horizontal)
        host.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return host
    }

    func updateNSView(_ nsView: Host, context: Context) {
        nsView.rootView = content
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: Host, context: Context) -> CGSize? {
        let fitting = nsView.fittingSize
        return CGSize(width: proposal.width ?? fitting.width, height: fitting.height)
    }

    final class Host: NSHostingView<Content> {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}
