import Foundation
import SwiftUI

// Full-screen host for a live fixture in an iOS Simulator. The device supplies the
// viewport, safe areas and size classes; appearance is switched on the simulator itself.

private struct PreviewConfiguration: Decodable {
    let locale: String

    static func load() throws -> Self {
        guard let url = Bundle.main.url(forResource: "PreviewConfiguration", withExtension: "plist") else {
            throw ConfigurationError.missingResource
        }
        let configuration = try PropertyListDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard !configuration.locale.isEmpty else { throw ConfigurationError.invalidValues }
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
            PreviewFixture.makeView()
                .environment(\.locale, Locale(identifier: configuration.locale))
        }
    }
}
