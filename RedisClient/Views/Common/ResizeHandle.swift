import SwiftUI
import AppKit

/// Prevents `isMovableByWindowBackground` from capturing drags on this view.
private struct WindowDragBlocker: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = BlockerView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private class BlockerView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
    }
}

/// Draggable vertical divider that resizes the pane to its left by mutating
/// `width`. Shows a horizontal-resize cursor on hover. Clamps to [min, max].
struct HResizeHandle: View {
    @Binding var width: CGFloat
    var minWidth: CGFloat = 200
    var maxWidth: CGFloat = 700

    @State private var dragStartWidth: CGFloat?
    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 12)
                .contentShape(Rectangle())

            RoundedRectangle(cornerRadius: 1)
                .fill(isHovering || isDragging
                      ? Theme.colors.primary.opacity(0.6)
                      : Theme.colors.text.opacity(0.15))
                .frame(width: isHovering || isDragging ? 3 : 2, height: 32)
        }
        .frame(width: 12)
        .background(WindowDragBlocker())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let start = dragStartWidth ?? width
                    if dragStartWidth == nil { dragStartWidth = width; isDragging = true }
                    width = min(max(start + value.translation.width, minWidth), maxWidth)
                }
                .onEnded { _ in dragStartWidth = nil; isDragging = false }
        )
    }
}

/// Draggable horizontal divider that resizes the pane above it by mutating `height`.
struct VResizeHandle: View {
    @Binding var height: CGFloat
    var minHeight: CGFloat = 80
    var maxHeight: CGFloat = 500

    @State private var dragStartHeight: CGFloat?
    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 12)
                .contentShape(Rectangle())

            RoundedRectangle(cornerRadius: 1)
                .fill(isHovering || isDragging
                      ? Theme.colors.primary.opacity(0.6)
                      : Theme.colors.text.opacity(0.15))
                .frame(width: 32, height: isHovering || isDragging ? 3 : 2)
        }
        .frame(height: 12)
        .background(WindowDragBlocker())
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let start = dragStartHeight ?? height
                    if dragStartHeight == nil { dragStartHeight = height; isDragging = true }
                    height = min(max(start + value.translation.height, minHeight), maxHeight)
                }
                .onEnded { _ in dragStartHeight = nil; isDragging = false }
        )
    }
}
