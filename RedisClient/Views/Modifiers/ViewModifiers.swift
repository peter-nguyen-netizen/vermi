import SwiftUI

extension View {
    func errorAlert(message: Binding<String?>) -> some View {
        alert("Error", isPresented: .constant(message.wrappedValue != nil)) {
            Button("OK") { message.wrappedValue = nil }
        } message: {
            if let message = message.wrappedValue {
                Text(message)
            }
        }
    }
}
