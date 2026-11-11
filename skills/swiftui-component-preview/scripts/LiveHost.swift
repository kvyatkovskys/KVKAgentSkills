import Foundation
import SwiftUI

private struct PreviewConfiguration: Decodable {
    let width: Int
    let height: Int
    let locale: String

    static func load() throws -> Self {
        guard let url = Bundle.main.url(forResource: "PreviewConfiguration", withExtension: "plist") else {
            throw ConfigurationError.missingResource
        }
        let configuration = try PropertyListDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard (1...4096).contains(configuration.width), (1...4096).contains(configuration.height),
              !configuration.locale.isEmpty else { throw ConfigurationError.invalidValues }
        return configuration
    }

    private enum ConfigurationError: Error { case missingResource, invalidValues }
}

@main
@MainActor
private struct ComponentPreviewApp: App {
    private let configuration: PreviewConfiguration

    init() {
        do { configuration = try PreviewConfiguration.load() }
        catch { fatalError("Unable to load preview configuration: \(error)") }
    }

    var body: some Scene {
        Window("SwiftUI Component Preview", id: "component-preview") {
            LivePreview(configuration: configuration)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}

private enum PreviewTheme: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: Self { self }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct LivePreview: View {
    let configuration: PreviewConfiguration
    @State private var theme = PreviewTheme.system
    @State private var locale: String
    @State private var generation = UUID()

    init(configuration: PreviewConfiguration) {
        self.configuration = configuration
        _locale = State(initialValue: configuration.locale)
    }

    var body: some View {
        VStack(spacing: 0) {
            PreviewControls(theme: $theme, locale: $locale, initialLocale: configuration.locale) {
                generation = UUID()
            }
            Divider()
            PreviewFixture.makeView()
                .id(generation)
                .environment(\.locale, Locale(identifier: locale))
                .frame(width: CGFloat(configuration.width), height: CGFloat(configuration.height))
                .clipped()
        }
        .preferredColorScheme(theme.colorScheme)
    }
}

private struct PreviewControls: View {
    @Binding var theme: PreviewTheme
    @Binding var locale: String
    let initialLocale: String
    let reset: () -> Void

    private var locales: [String] {
        [initialLocale] + ["en_US", "ru_RU"].filter { $0 != initialLocale }
    }

    var body: some View {
        HStack(spacing: 16) {
            Picker("Theme", selection: $theme) {
                ForEach(PreviewTheme.allCases) { Text($0.rawValue).tag($0) }
            }
            .frame(width: 185)
            Picker("Locale", selection: $locale) {
                ForEach(locales, id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 190)
            Spacer(minLength: 0)
            Button("Reset", action: reset)
                .help("Recreate the fixture and its view-local state")
        }
        .padding(12)
        .frame(minWidth: 520)
    }
}
