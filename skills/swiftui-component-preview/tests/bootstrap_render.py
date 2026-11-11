#!/usr/bin/env python3
"""Render an adapter retaining a synthetic project's actual value view."""
from pathlib import Path
import struct
import subprocess
import sys
import tempfile

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/bootstrap.py'
SOURCE = '''import SwiftUI

struct SupplyStatus: Sendable {
    let count: Int
    let destination: String
}

struct SupplyCard: View {
    let status: SupplyStatus
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Supply dispatch", systemImage: "shippingbox.fill")
                .font(.title2.bold())
            Text("\\(status.count) parcels for \\(status.destination)")
            Toggle("Notify on arrival", isOn: .constant(true))
            Button("Prepare labels") {}
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.orange.opacity(0.15))
    }
}

#Preview {
    SupplyCard(status: SupplyStatus(count: 7, destination: "North depot"))
}
'''


def main():
    if sys.platform != 'darwin':
        print('SKIP: genuine SwiftUI rendering requires macOS.')
        return
    with tempfile.TemporaryDirectory(prefix='genuine source preview ') as temp:
        root = Path(temp)
        (root / 'Package.swift').write_text('// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: "Supply", platforms: [.macOS(.v14)])\n')
        (root / 'SupplyCard.swift').write_text(SOURCE)
        fixture = root / '.swiftui-preview/fixtures/SupplyCard.swift'
        fixture.parent.mkdir(parents=True)
        # Preserve the exact real component and its local value type, adapting
        # only the existing #Preview entry point to the standalone contract.
        view_definitions, preview = SOURCE.split('#Preview', 1)
        construction = preview.strip()[1:-1].strip()
        fixture.write_text(view_definitions + '@MainActor enum PreviewFixture {\n    static func makeView() -> some View {\n        ' + construction + '\n    }\n}\n')
        subprocess.run([sys.executable, str(SCRIPT), 'configure', '--root', str(root), '--project', 'Package.swift', '--source', 'SupplyCard.swift', '--fixture', '.swiftui-preview/fixtures/SupplyCard.swift', '--component', 'SupplyCard'], check=True)
        output = root / 'Supply card.png'
        subprocess.run([sys.executable, str(SCRIPT), 'run', '--root', str(root), '--mode', 'render', '--output', str(output), '--width', '480', '--height', '320', '--theme', 'light'], check=True)
        content = output.read_bytes()
        assert content[:8] == b'\x89PNG\r\n\x1a\n'
        assert struct.unpack('>II', content[16:24]) == (480, 320)
        assert len(content) > 4000, 'Expected rendered component detail.'
        print('PASS: real SupplyCard definitions and preview inputs rendered at 480 x 320.')


if __name__ == '__main__':
    main()
