import SwiftUI

@MainActor
enum PreviewFixture {
    static func makeView() -> some View { LiveExample() }
}

// Synthetic, view-local interactions only; no persistence or external services.
private struct LiveExample: View {
    private enum Step { case welcome, form, success }
    @State private var step = Step.welcome
    @State private var name = "Alex Example"
    @State private var email = "alex@example.invalid"
    @State private var simulateError = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            switch step {
            case .welcome:
                Image(systemName: "hand.wave.fill").font(.largeTitle).foregroundStyle(.tint)
                Text("Welcome to the demo").font(.title.bold())
                Text("Explore an interactive SwiftUI fixture with synthetic data.")
                    .foregroundStyle(.secondary)
                Button("Get started") { step = .form }
                    .buttonStyle(.borderedProminent)
            case .form:
                Text("Create a demo profile").font(.title2.bold())
                TextField("Name", text: $name)
                TextField("Email", text: $email)
                Toggle("Simulate an error", isOn: $simulateError)
                if let error { Text(error).foregroundStyle(.red) }
                HStack {
                    Button("Back") { error = nil; step = .welcome }
                    Spacer()
                    Button("Continue") {
                        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !email.contains("@") {
                            error = "Enter a name and an email containing @."
                        } else if simulateError {
                            error = "Demo error. Turn off Simulate an error to continue."
                        } else {
                            error = nil
                            step = .success
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .success:
                Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
                Text("You're ready, \(name)").font(.title2.bold())
                Text("The demo profile for \(email) exists only in this fixture.")
                    .foregroundStyle(.secondary)
                Text(12345.67, format: .number.precision(.fractionLength(2)))
                    .help("This number follows the selected preview locale")
                Button("Back") { step = .form }
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
