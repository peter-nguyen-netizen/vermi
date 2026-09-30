import SwiftUI

/// Small icon button that copies `value` to the pasteboard and briefly shows a
/// checkmark for feedback. Reusable across key lists, analysis, monitoring, etc.
struct CopyButton: View {
    let value: String
    var size: CGFloat = 11
    var help: String = "Copy"

    @State private var copied = false

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(value, forType: .string)
            withAnimation(.easeOut(duration: 0.15)) { copied = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                withAnimation(.easeIn(duration: 0.2)) { copied = false }
            }
        } label: {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: size))
                .foregroundColor(copied ? Theme.colors.success : Theme.colors.textTertiary)
        }
        .buttonStyle(.plain).handCursor()
        .help(help)
    }
}
