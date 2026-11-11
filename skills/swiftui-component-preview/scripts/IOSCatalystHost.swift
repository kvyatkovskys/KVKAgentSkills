import Foundation
import SwiftUI
import UIKit

// Live host for an iOS fixture in an ordinary Mac window (Mac Catalyst, iPad idiom).
// It is an iPad interface running on the Mac, not an iPhone and not a simulator device.

private let controlsHeight: CGFloat = 52

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
        WindowGroup {
            LivePreview(configuration: configuration)
        }
    }
}

private enum PreviewTheme: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }
    var style: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
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
    @State private var viewport = CGSize.zero
    @State private var didInitialSize = false

    init(configuration: PreviewConfiguration) {
        self.configuration = configuration
        _locale = State(initialValue: configuration.locale)
    }

    var body: some View {
        VStack(spacing: 0) {
            // The fixture is laid out again at every window size the user drags to.
            GeometryReader { proxy in
                PreviewFixture.makeView()
                    .id(generation)
                    .environment(\.locale, Locale(identifier: locale))
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .onChange(of: proxy.size, initial: true) { _, size in
                        viewport = size
                        // For whoever started the executable directly; `open` discards it.
                        print("viewport \(Int(size.width))x\(Int(size.height))")
                        fflush(stdout)
                    }
            }
            Divider()
            PreviewControls(theme: $theme, locale: $locale, initialLocale: configuration.locale,
                            viewport: viewport) {
                generation = UUID()
            }
            .frame(maxWidth: .infinity)
            .frame(height: controlsHeight)
            .background(.bar)
        }
        .task { await openAtConfiguredSize() }
        // Override the windows themselves so sheets and alerts follow the choice too.
        .onChange(of: theme, initial: true) { _, theme in
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                for window in windowScene.windows { window.overrideUserInterfaceStyle = theme.style }
            }
        }
    }
}

private extension LivePreview {
    /// A Catalyst scene ignores a default size, so pin the window to a size for a moment,
    /// correct it by what the title bar and safe area took from the viewport, then let
    /// the user resize it freely.
    func openAtConfiguredSize() async {
        guard !didInitialSize else { return }
        didInitialSize = true
        let wanted = CGSize(width: CGFloat(configuration.width), height: CGFloat(configuration.height))
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var size = CGSize(width: wanted.width, height: wanted.height + controlsHeight + 1)
        for _ in 0..<3 {
            for scene in scenes {
                scene.sizeRestrictions?.minimumSize = size
                scene.sizeRestrictions?.maximumSize = size
            }
            try? await Task.sleep(for: .milliseconds(350))
            let missing = CGSize(width: wanted.width - viewport.width, height: wanted.height - viewport.height)
            // Catalyst scales scene points to the screen, so sizes land within a point or two.
            if abs(missing.width) < 2, abs(missing.height) < 2 { break }
            size.width += missing.width
            size.height += missing.height
        }
        for scene in scenes {
            scene.sizeRestrictions?.minimumSize = CGSize(width: 320, height: 160)
            scene.sizeRestrictions?.maximumSize = CGSize(width: 8192, height: 8192)
        }
    }
}

private struct PreviewControls: View {
    @Binding var theme: PreviewTheme
    @Binding var locale: String
    let initialLocale: String
    let viewport: CGSize
    let reset: () -> Void

    private var locales: [String] {
        [initialLocale] + ["en_US", "ru_RU"].filter { $0 != initialLocale }
    }

    var body: some View {
        HStack(spacing: 14) {
            Picker("Appearance", selection: $theme) {
                ForEach(PreviewTheme.allCases) { option in
                    Image(systemName: option.symbol)
                        .accessibilityLabel(option.rawValue)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Menu {
                // Inline, so the choices sit directly in the menu instead of a "Locale" submenu.
                Picker("Locale", selection: $locale) {
                    ForEach(locales, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label(locale, systemImage: "globe")
            }
            .fixedSize()

            Text("\(Int(viewport.width)) × \(Int(viewport.height))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .help("Content viewport in points; drag the window edge to resize")

            Button(action: reset) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .labelStyle(.iconOnly)
            }
            .help("Recreate the fixture and its view-local state")
        }
        .padding(.horizontal, 14)
    }
}
