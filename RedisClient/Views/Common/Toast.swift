import SwiftUI

/// Subtle dotted/line grid background to make large empty areas less flat.
struct GridBackground: View {
    var spacing: CGFloat = 24
    var lineColor: Color = Theme.colors.border.opacity(0.5)

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(lineColor), lineWidth: 0.5)
        }
        .drawingGroup()
    }
}

enum ToastKind {
    case success, error, info, warning

    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.octagon.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: return Theme.colors.success
        case .error: return Theme.colors.error
        case .info: return Theme.colors.info
        case .warning: return Theme.colors.warning
        }
    }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let kind: ToastKind
    let time = Date()
    /// Optional inline action (e.g. "Undo"). Not part of equality.
    var actionLabel: String?
    var action: (() -> Void)?

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool { lhs.id == rhs.id }
}

/// App-wide toast queue. Single shared instance keeps posting simple from
/// anywhere (view models, services) without dependency plumbing.
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    @Published private(set) var toasts: [ToastMessage] = []

    private let maxVisible = 5

    private init() {}

    /// Errors linger longer; transient success/info clear quickly.
    private func dismissDelay(_ kind: ToastKind) -> TimeInterval {
        switch kind {
        case .error, .warning: return 10
        case .success, .info: return 4
        }
    }

    func show(_ title: String, kind: ToastKind = .info, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Skip exact duplicate of the most recent toast (avoids spam)
        if toasts.last?.title == trimmed, toasts.last?.kind == kind { return }

        let toast = ToastMessage(title: trimmed, kind: kind, actionLabel: actionLabel, action: action)
        toasts.append(toast)
        if toasts.count > maxVisible {
            toasts.removeFirst(toasts.count - maxVisible)
        }

        let delay = dismissDelay(kind)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self?.dismiss(toast.id)
        }
    }

    func success(_ title: String) { show(title, kind: .success) }
    func error(_ title: String) { show(title, kind: .error) }
    func info(_ title: String) { show(title, kind: .info) }

    func dismiss(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }
}

// MARK: - Overlay

/// Bottom-left stack of toasts. Overlay this on the root view.
struct ToastOverlay: View {
    @ObservedObject private var center = ToastCenter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing.md) {
            Spacer()
            ForEach(center.toasts) { toast in
                ToastRow(toast: toast) { center.dismiss(toast.id) }
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(Theme.spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .allowsHitTesting(true)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: center.toasts)
    }
}

struct ToastRow: View {
    let toast: ToastMessage
    let onClose: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing.md) {
            Image(systemName: toast.kind.icon)
                .font(.system(size: 15, design: .rounded))
                .foregroundColor(toast.kind.color)

            Text(toast.title)
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(Theme.colors.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320, alignment: .leading)

            // Optional inline action (e.g. Undo).
            if let label = toast.actionLabel, let action = toast.action {
                Button(label) { action(); onClose() }
                    .buttonStyle(.plain).handCursor()
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(toast.kind.color)
            }

            // Errors get a quick copy for pasting into a bug report.
            if toast.kind == .error {
                CopyButton(value: toast.title, size: 11, help: "Copy error")
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Theme.colors.textTertiary)
                    .frame(width: 16, height: 16)
                    .background(isHovering ? Theme.colors.muted : Color.clear)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain).handCursor()
            .onHover { isHovering = $0 }
        }
        .padding(.vertical, Theme.spacing.md)
        .padding(.horizontal, Theme.spacing.lg)
        .background(Theme.colors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.sizes.cardCornerRadius)
                .stroke(Theme.colors.border, lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(toast.kind.color)
                .frame(width: 3)
                .padding(.vertical, 6)
        }
        .cornerRadius(Theme.sizes.cardCornerRadius)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
    }
}
