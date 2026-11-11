import SwiftUI

@MainActor
enum PreviewFixture {
    static func makeView() -> some View { ExampleSettings() }
}

private struct ExampleSettings: View {
    @State private var email = "alex@example.invalid"
    @State private var password = "preview-only"
    @State private var notifications = true

    var body: some View {
        Form {
            Section("Demo account") {
                TextField("Email", text: $email)
                SecureField("Password", text: $password)
                Toggle("Notifications", isOn: $notifications)
            }
            Section {
                Button("Save example") { /* Intentionally inert fixture action. */ }
            }
        }
        .formStyle(.grouped)
    }
}
