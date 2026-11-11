import SwiftUI
import UIKit

// Renders PreviewFixture inside a real UIKit window on an iOS Simulator, then exits.
// Launch arguments: output directory, width|fit|screen, height|fit|screen, locale, scale,
// then one "light|dark:raw|framed" variant per PNG. Each variant is written as
// "<theme>-<raw|framed>.png"; "status.txt" appears last and reports the outcome.

private enum RenderError: Error {
    case invalidArguments
    case contentHasNoFittingSize(String)
    case pngEncodingFailed
}

private struct RenderRequest {
    struct Variant {
        let dark: Bool
        let framed: Bool
        var name: String { (dark ? "dark" : "light") + (framed ? "-framed" : "-raw") }
    }

    let directory: URL
    /// nil is a fitted axis. Ignored when `screen` is set.
    let width: Int?
    let height: Int?
    let screen: Bool
    let locale: Locale
    let scale: CGFloat
    let variants: [Variant]

    init(arguments: [String]) throws {
        guard arguments.count >= 7, let scale = Int(arguments[5]), (1...3).contains(scale) else {
            throw RenderError.invalidArguments
        }
        func dimension(_ value: String) throws -> Int? {
            if value == "fit" || value == "screen" { return nil }
            guard let number = Int(value), (1...4096).contains(number) else { throw RenderError.invalidArguments }
            return number
        }
        // The whole device screen is one unit: both axes or neither.
        guard (arguments[2] == "screen") == (arguments[3] == "screen") else { throw RenderError.invalidArguments }
        directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
        screen = arguments[2] == "screen"
        width = try dimension(arguments[2])
        height = try dimension(arguments[3])
        locale = Locale(identifier: arguments[4])
        self.scale = CGFloat(scale)
        variants = try arguments[6...].map { value in
            let parts = value.split(separator: ":").map(String.init)
            guard parts.count == 2, ["light", "dark"].contains(parts[0]),
                  ["raw", "framed"].contains(parts[1]) else { throw RenderError.invalidArguments }
            return Variant(dark: parts[0] == "dark", framed: parts[1] == "framed")
        }
    }
}

@main
final class PreviewRendererApplication: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = PreviewRendererScene.self
        return configuration
    }
}

final class PreviewRendererScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        UIView.setAnimationsEnabled(false)
        Task { @MainActor in
            var status: String
            do {
                let request = try RenderRequest(arguments: CommandLine.arguments)
                status = try await Renderer(window: window, request: request).run()
            } catch {
                status = "error: \(error)\n"
            }
            let directory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory()
            try? Data(status.utf8).write(to: URL(fileURLWithPath: directory).appendingPathComponent("status.txt"),
                                         options: .atomic)
            exit(status.hasPrefix("error") ? 1 : 0)
        }
    }
}

@MainActor
private struct Renderer {
    let window: UIWindow
    let request: RenderRequest

    func run() async throws -> String {
        var status = ""
        var size = window.bounds.size
        if !request.screen {
            var width = request.width ?? 0
            var height = request.height ?? 0
            if request.width == nil || request.height == nil {
                // A fitted axis takes the fixture's ideal size; a numeric axis stays fixed.
                let probe = UIHostingController(rootView: PreviewFixture.makeView()
                    .frame(width: request.width.map { CGFloat($0) },
                           height: request.height.map { CGFloat($0) })
                    .fixedSize(horizontal: request.width == nil, vertical: request.height == nil)
                    .environment(\.locale, request.locale))
                probe.safeAreaRegions = []
                let fitted = probe.sizeThatFits(in: CGSize(width: 4096, height: 4096))
                width = request.width ?? Int(fitted.width.rounded(.up))
                height = request.height ?? Int(fitted.height.rounded(.up))
                guard (1...4096).contains(width), (1...4096).contains(height) else {
                    throw RenderError.contentHasNoFittingSize("\(fitted.width)x\(fitted.height)")
                }
                status += "fitted \(width)x\(height)\n"
            }
            size = CGSize(width: width, height: height)
        }
        status += "size \(Int(size.width))x\(Int(size.height))\n"
        for variant in request.variants {
            window.overrideUserInterfaceStyle = variant.dark ? .dark : .light
            var image = request.screen ? try await screenImage() : try await componentImage(size: size, variant: variant)
            if request.screen && variant.framed {
                image = try await surfaceImage(Image(uiImage: image).resizable(), size: size, variant: variant)
            }
            guard let png = image.pngData() else { throw RenderError.pngEncodingFailed }
            try png.write(to: request.directory.appendingPathComponent(variant.name + ".png"), options: .atomic)
        }
        return status + "ok\n"
    }

    /// The fixture as the window's root: safe areas, bars, and size classes of the device apply.
    private func screenImage() async throws -> UIImage {
        let host = UIHostingController(rootView: PreviewFixture.makeView()
            .environment(\.locale, request.locale)
            .transaction { $0.disablesAnimations = true })
        window.rootViewController = host
        return try await snapshot(window, size: window.bounds.size)
    }

    /// The fixture in a fixed viewport without safe-area insets, as a detached component.
    private func componentImage(size: CGSize, variant: RenderRequest.Variant) async throws -> UIImage {
        try await surfaceImage(PreviewFixture.makeView().environment(\.locale, request.locale),
                               size: size, variant: variant)
    }

    private func surfaceImage(_ content: some View, size: CGSize,
                              variant: RenderRequest.Variant) async throws -> UIImage {
        let imageSize = CGSize(width: size.width + (variant.framed ? 48 : 0),
                               height: size.height + (variant.framed ? 88 : 0))
        let host = UIHostingController(rootView: ComponentSurface(content: content, size: size, framed: variant.framed)
            .transaction { $0.disablesAnimations = true })
        host.safeAreaRegions = []
        let container = UIViewController()
        window.rootViewController = container
        container.addChild(host)
        host.view.frame = CGRect(origin: .zero, size: imageSize)
        container.view.addSubview(host.view)
        host.didMove(toParent: container)
        return try await snapshot(host.view, size: imageSize)
    }

    private func snapshot(_ view: UIView, size: CGSize) async throws -> UIImage {
        view.setNeedsLayout()
        view.layoutIfNeeded()
        // Let SwiftUI commit its first frame (lists, bars and symbols resolve asynchronously).
        try await Task.sleep(for: .milliseconds(250))
        let format = UIGraphicsImageRendererFormat()
        format.scale = request.scale
        format.opaque = false
        // 8-bit sRGB on every device; wide-gamut displays would otherwise yield 16-bit PNGs.
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
    }
}

private struct ComponentSurface<Content: View>: View {
    let content: Content
    let size: CGSize
    let framed: Bool

    var body: some View {
        if framed {
            VStack(spacing: 0) {
                DecorativeStatusBar()
                contentViewport
            }
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.primary.opacity(0.18), lineWidth: 2))
            .padding(24)
            .background(Color(uiColor: .secondarySystemBackground))
        } else {
            contentViewport
        }
    }

    private var contentViewport: some View {
        content
            .frame(width: size.width, height: size.height)
            .clipped()
            .background(Color(uiColor: .systemBackground))
    }
}

/// Drawn shapes only: it is not the system status bar.
private struct DecorativeStatusBar: View {
    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: "9:41").font(.system(size: 15, weight: .semibold))
            Spacer()
            Image(systemName: "wifi")
            Image(systemName: "battery.100percent")
        }
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 22)
        .frame(height: 40)
    }
}
