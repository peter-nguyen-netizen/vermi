import SwiftUI

/// Shows the pointing-hand cursor while hovering an actionable element
/// (button, link, clickable row). macOS doesn't do this automatically for
/// SwiftUI controls, so anything that triggers an action should carry this.
///
/// Uses NSCursor push/pop (same approach as ResizeHandle) — balanced per
/// enter/exit. macOS 13 lacks the `.cursor()` / `.pointerStyle` modifiers.
private struct PointingHandCursor: ViewModifier {
    var enabled: Bool = true
    /// Per-instance guard so push/pop stay balanced even if the view is removed
    /// mid-hover (conditionally-rendered buttons) — otherwise the hand can stick.
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside && enabled {
                    if !pushed { NSCursor.pointingHand.push(); pushed = true }
                } else if pushed {
                    NSCursor.pop(); pushed = false
                }
            }
            .onDisappear {
                if pushed { NSCursor.pop(); pushed = false }
            }
    }
}

extension View {
    /// Pointing-hand cursor on hover. Pass `enabled: false` to suppress when a
    /// control is disabled.
    func handCursor(_ enabled: Bool = true) -> some View {
        modifier(PointingHandCursor(enabled: enabled))
    }
}
