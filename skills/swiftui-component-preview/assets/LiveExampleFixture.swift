import SwiftUI

@MainActor
enum PreviewFixture {
    static func makeView() -> some View { LiveExample() }
}

// Synthetic, view-local interactions only; no persistence or external services.
// Covers pushed screens, a sheet, an alert, a confirmation dialog, and common controls.

private enum Route: Hashable { case profile, success, details }

private enum Plan: String, CaseIterable, Identifiable {
    case free = "Free", team = "Team", business = "Business"
    var id: Self { self }
    var seatPrice: Double {
        switch self {
        case .free: 0
        case .team: 8
        case .business: 20
        }
    }
}

private enum Digest: String, CaseIterable, Identifiable {
    case daily = "Daily", weekly = "Weekly", never = "Never"
    var id: Self { self }
}

private struct Profile {
    var name = "Alex Example"
    var email = "alex@example.invalid"
    var plan = Plan.team
    var seats = 3
    var newsletter = true
    var digest = Digest.weekly
    var volume = 60.0

    var monthlyCost: Double { plan.seatPrice * Double(seats) }
}

private struct LiveExample: View {
    @State private var path: [Route] = []
    @State private var profile = Profile()

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeScreen { path.append(.profile) }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .profile:
                        ProfileScreen(profile: $profile, back: { path.removeLast() }) { path.append(.success) }
                    case .success:
                        SuccessScreen(profile: $profile, back: { path.removeLast() }) { path.removeAll() }
                    case .details:
                        DetailsScreen(profile: $profile) { path.removeLast() }
                    }
                }
        }
        .textFieldStyle(.roundedBorder)
    }
}

private struct WelcomeScreen: View {
    let start: () -> Void
    @State private var showAbout = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "hand.wave.fill").font(.largeTitle).foregroundStyle(.tint)
            Text("Welcome to the demo").font(.title.bold())
            Text("Explore an interactive SwiftUI fixture with synthetic data.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Get started", action: start)
                    .buttonStyle(.borderedProminent)
                Button("About this demo") { showAbout = true }
            }
        }
        .screenLayout()
        .navigationTitle("Welcome")
        .sheet(isPresented: $showAbout) {
            VStack(alignment: .leading, spacing: 14) {
                Label("About this demo", systemImage: "info.circle").font(.title3.bold())
                Text("Three pushed screens, a sheet, an alert, and a confirmation dialog. Everything you change lives in view state and disappears on Reset.")
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("Close") { showAbout = false }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
            .frame(width: 380)
        }
    }
}

private struct ProfileScreen: View {
    @Binding var profile: Profile
    let back: () -> Void
    let finish: () -> Void
    @State private var simulateError = false
    @State private var validationError: String?
    @State private var showPreferences = false
    @State private var showSimulatedError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Create a demo profile").font(.title2.bold())
            TextField("Name", text: $profile.name)
            TextField("Email", text: $profile.email)
            Picker("Plan", selection: $profile.plan.animation()) {
                ForEach(Plan.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Stepper("Seats: \(profile.seats)", value: $profile.seats.animation(), in: 1...20)
                Spacer()
                Text(profile.monthlyCost, format: .currency(code: "USD"))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("per month").foregroundStyle(.secondary)
            }
            Button("Notification preferences…") { showPreferences = true }
            Toggle("Simulate an error", isOn: $simulateError)
            if let validationError { Text(validationError).foregroundStyle(.red) }
            Spacer(minLength: 0)
            HStack {
                Button("Back") { validationError = nil; back() }
                Spacer()
                Button("Continue", action: submit)
                    .buttonStyle(.borderedProminent)
            }
        }
        .screenLayout()
        .navigationTitle("Profile")
        .sheet(isPresented: $showPreferences) {
            PreferencesSheet(profile: $profile) { showPreferences = false }
        }
        .alert("Demo error", isPresented: $showSimulatedError) {
            Button("Turn off and continue") {
                simulateError = false
                finish()
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("This failure is simulated. Nothing was sent anywhere.")
        }
    }

    private func submit() {
        if profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !profile.email.contains("@") {
            validationError = "Enter a name and an email containing @."
        } else if simulateError {
            validationError = nil
            showSimulatedError = true
        } else {
            validationError = nil
            finish()
        }
    }
}

private struct PreferencesSheet: View {
    @Binding var profile: Profile
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Notification preferences").font(.title3.bold())
            Toggle("Product newsletter", isOn: $profile.newsletter)
            Picker("Activity digest", selection: $profile.digest) {
                ForEach(Digest.allCases) { Text($0.rawValue).tag($0) }
            }
            .fixedSize()
            HStack {
                Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                Slider(value: $profile.volume, in: 0...100, step: 10)
                Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                Text("\(Int(profile.volume))%").monospacedDigit().frame(width: 44, alignment: .trailing)
            }
            HStack {
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

private struct SuccessScreen: View {
    @Binding var profile: Profile
    let back: () -> Void
    let startOver: () -> Void
    @State private var confirmStartOver = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "checkmark.circle.fill").font(.largeTitle).foregroundStyle(.green)
            Text("You're ready, \(profile.name)").font(.title2.bold())
            Text("The demo profile for \(profile.email) exists only in this fixture.")
                .foregroundStyle(.secondary)
            Text(12345.67, format: .number.precision(.fractionLength(2)))
                .help("This number follows the selected preview locale")
            NavigationLink("View details", value: Route.details)
            Spacer(minLength: 0)
            HStack {
                Button("Back", action: back)
                Spacer()
                Button("Start over", role: .destructive) { confirmStartOver = true }
            }
        }
        .screenLayout()
        .navigationTitle("Done")
        .confirmationDialog("Return to the welcome screen?", isPresented: $confirmStartOver) {
            Button("Start over", role: .destructive, action: startOver)
            Button("Stay here", role: .cancel) {}
        } message: {
            Text("Your entries stay in the fixture until Reset.")
        }
    }
}

private struct DetailsScreen: View {
    @Binding var profile: Profile
    let back: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Profile details").font(.title2.bold())
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                row("Name", profile.name)
                row("Email", profile.email)
                row("Plan", "\(profile.plan.rawValue), \(profile.seats) seats")
                row("Monthly", profile.monthlyCost.formatted(.currency(code: "USD")))
                row("Newsletter", profile.newsletter ? "On" : "Off")
                row("Digest", profile.digest.rawValue)
                row("Volume", "\(Int(profile.volume))%")
            }
            Spacer(minLength: 0)
            Button("Back", action: back)
        }
        .screenLayout()
        .navigationTitle("Details")
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}

private extension View {
    func screenLayout() -> some View {
        padding(32).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
