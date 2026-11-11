import AppKit
import Foundation
import SwiftUI

private let controlsHeight: CGFloat = 48
private let minimumWidth: CGFloat = 380
private let minimumHeight: CGFloat = 40

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
        // Resizable down to the content minimum; opens at the configured viewport.
        .windowResizability(.contentMinSize)
        .defaultSize(width: max(CGFloat(configuration.width), minimumWidth),
                     height: max(CGFloat(configuration.height), minimumHeight) + controlsHeight + 1)
        .defaultPosition(.center)
        .commands { CommandGroup(replacing: .newItem) {} }
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
    /// nil follows the system setting.
    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

private struct LivePreview: View {
    let configuration: PreviewConfiguration
    @State private var theme = PreviewTheme.system
    @State private var locale: String
    @State private var generation = UUID()
    @State private var viewport: CGSize
    @State private var didInitialFit = false

    init(configuration: PreviewConfiguration) {
        self.configuration = configuration
        _locale = State(initialValue: configuration.locale)
        _viewport = State(initialValue: CGSize(width: configuration.width, height: configuration.height))
    }

    private var configuredSize: CGSize {
        CGSize(width: max(CGFloat(configuration.width), minimumWidth),
               height: max(CGFloat(configuration.height), minimumHeight))
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
                        // A fixture's navigation toolbar takes height from the default window size;
                        // correct once so the viewport opens at exactly the configured size.
                        if !didInitialFit {
                            didInitialFit = true
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(200))
                                restoreSize(animated: false)
                            }
                        }
                    }
            }
            .frame(minWidth: minimumWidth, idealWidth: configuredSize.width, maxWidth: .infinity,
                   minHeight: minimumHeight, idealHeight: configuredSize.height, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            PreviewControls(theme: $theme, locale: $locale, initialLocale: configuration.locale,
                            viewport: viewport, isConfiguredSize: viewport == configuredSize,
                            restoreSize: { restoreSize() }) {
                generation = UUID()
            }
            .frame(maxWidth: .infinity)
            .frame(height: controlsHeight)
            .background(BehindWindowGlass())
        }
        // preferredColorScheme(nil) does not return a window to the system appearance,
        // so drive the application appearance directly; sheets and alerts follow it too.
        .onChange(of: theme, initial: true) { _, theme in NSApp.appearance = theme.appearance }
    }

    /// Grows or shrinks the window by the difference between the live and configured viewport.
    private func restoreSize(animated: Bool = true) {
        guard viewport != configuredSize,
              let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) else { return }
        var frame = window.frame
        let extraHeight = configuredSize.height - viewport.height
        frame.size.width += configuredSize.width - viewport.width
        frame.size.height += extraHeight
        frame.origin.y -= extraHeight
        window.setFrame(frame, display: true, animate: animated)
    }
}

/// Translucent bar: blurs whatever is behind the window, like a glass sheet.
private struct BehindWindowGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

private struct PreviewControls: View {
    @Binding var theme: PreviewTheme
    @Binding var locale: String
    let initialLocale: String
    let viewport: CGSize
    let isConfiguredSize: Bool
    let restoreSize: () -> Void
    let reset: () -> Void

    private var locales: [String] {
        [initialLocale] + ["en_US", "ru_RU"].filter { $0 != initialLocale }
    }

    var body: some View {
        HStack(spacing: 12) {
            Picker("Appearance", selection: $theme) {
                ForEach(PreviewTheme.allCases) { option in
                    Image(systemName: option.symbol)
                        .accessibilityLabel(option.rawValue)
                        .help(option.rawValue + " appearance")
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Menu {
                Picker("Locale", selection: $locale) {
                    ForEach(locales, id: \.self) { Text($0).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Label(locale, systemImage: "globe")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Locale injected into the fixture environment")

            Button(action: restoreSize) {
                Text("\(Int(viewport.width)) × \(Int(viewport.height))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isConfiguredSize ? .secondary : .primary)
            }
            .buttonStyle(.borderless)
            .disabled(isConfiguredSize)
            .help(isConfiguredSize ? "Content viewport in points; drag the window edge to resize"
                                   : "Restore the configured viewport size")

            Button(action: reset) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Recreate the fixture and its view-local state")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .modifier(GlassCapsule())
    }
}

/// Groups the controls: Liquid Glass where the SDK and OS provide it, a material capsule elsewhere.
private struct GlassCapsule: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            material(content)
        }
        #else
        material(content)
        #endif
    }

    private func material(_ content: Content) -> some View {
        content
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.primary.opacity(0.12)))
            .shadow(color: .black.opacity(0.1), radius: 6, y: 1)
    }
}
