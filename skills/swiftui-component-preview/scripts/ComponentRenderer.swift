import AppKit
import SwiftUI

private enum RenderError: Error {
    case invalidArguments
    case appearanceUnavailable
    case bitmapAllocationFailed
    case pngEncodingFailed
}

@main
private enum ComponentRenderer {
    @MainActor
    static func main() {
        do {
            try render()
        } catch {
            FileHandle.standardError.write(Data("render: \(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    private static func render() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 7,
              let width = Int(arguments[2]), (1...4096).contains(width),
              let height = Int(arguments[3]), (1...4096).contains(height),
              ["light", "dark"].contains(arguments[4]),
              ["true", "false"].contains(arguments[6]) else {
            throw RenderError.invalidArguments
        }
        let dark = arguments[4] == "dark"
        let framed = arguments[6] == "true"
        let contentSize = NSSize(width: width, height: height)
        let imageSize = NSSize(width: width + (framed ? 48 : 0),
                               height: height + (framed ? 88 : 0))
        guard let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) else {
            throw RenderError.appearanceUnavailable
        }
        let root = ComponentSurface(content: PreviewFixture.makeView(),
                                    size: contentSize, framed: framed)
            .environment(\.colorScheme, dark ? .dark : .light)
            .environment(\.locale, Locale(identifier: arguments[5]))
            .transaction { $0.disablesAnimations = true }

        // This hosting view is detached. No application or window is created.
        let host = NSHostingView(rootView: root)
        host.appearance = appearance
        host.frame = NSRect(origin: .zero, size: imageSize)
        host.bounds = NSRect(origin: .zero, size: imageSize)
        host.layoutSubtreeIfNeeded()
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(imageSize.width),
            pixelsHigh: Int(imageSize.height), bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw RenderError.bitmapAllocationFailed }
        bitmap.size = imageSize
        appearance.performAsCurrentDrawingAppearance {
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw RenderError.pngEncodingFailed
        }
        try png.write(to: URL(fileURLWithPath: arguments[1]), options: .atomic)
        print(arguments[1])
    }
}

private struct ComponentSurface<Content: View>: View {
    let content: Content
    let size: NSSize
    let framed: Bool

    var body: some View {
        if framed {
            VStack(spacing: 0) {
                DecorativeTitleBar()
                contentViewport
            }
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.12)))
            .padding(24)
            .background(Color(nsColor: .underPageBackgroundColor))
        } else {
            contentViewport
        }
    }

    private var contentViewport: some View {
        content
            .frame(width: size.width, height: size.height)
            .clipped()
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct DecorativeTitleBar: View {
    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(red: 1, green: 0.37, blue: 0.34))
            Circle().fill(Color(red: 1, green: 0.74, blue: 0.18))
            Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25))
            Spacer()
        }
        .frame(height: 12)
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}
