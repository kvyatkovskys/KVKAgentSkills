#!/usr/bin/env python3
"""Exercise gallery output and failure cleanup using the actual Swift renderer."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import unittest

SKILL = (Path(__file__).resolve().parents[2] / 'skills' / 'swiftui-component-preview')


class GalleryTests(unittest.TestCase):
    def test_rendered_variants_and_rejected_inputs(self):
        with tempfile.TemporaryDirectory(prefix="gallery-test-") as directory:
            root = Path(directory)
            temporary = root / "compiler temporary files"
            temporary.mkdir()
            work = root / "path with spaces and 'quotes'"
            work.mkdir()
            fixture = work / "Fixture.swift"
            fixture.write_bytes((SKILL / "assets/ExampleFixture.swift").read_bytes())
            output = work / "gallery 'quoted'.html"
            environment = dict(os.environ, TMPDIR=str(temporary))

            def run(*arguments, success=False):
                result = subprocess.run(
                    ["bash", str(SKILL / "scripts/gallery.sh"), *map(str, arguments)],
                    cwd=work, env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                self.assertEqual(result.returncode == 0, success, result.stderr)
                self.assertEqual(list(temporary.glob("swiftui-component-gallery.*")), [])
                return result

            title = "Preview </title><script>alert('x')</script> & \"quote\" $(touch INJECTED)"
            run(fixture, output, 480, 320, "en_US", title, success=True)
            page = output.read_text()
            self.assertNotIn("<script>alert", page)
            self.assertNotIn("<title>Preview </title>", page)
            self.assertIn("&lt;script&gt;", page)
            self.assertFalse((work / "INJECTED").exists())
            variants = json.loads(re.search(r'<script id="variants" type="application/json">(.*?)</script>', page).group(1))
            self.assertEqual(set(variants), {"light-raw", "light-framed", "dark-raw", "dark-framed"})
            self.assertEqual(page.count("data:image/png;base64,"), 4)
            initial_src = re.search(r'<img id="preview"[^>]*src="(data:image/png;base64,[A-Za-z0-9+/=]+)"', page).group(1)
            variants["light-framed"]["src"] = initial_src
            hashes = {}
            for name, variant in variants.items():
                theme, frame = name.split("-")
                png = base64.b64decode(variant["src"][len("data:image/png;base64,"): ], validate=True)
                self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")
                dimensions = struct.unpack(">II", png[16:24])
                self.assertEqual(dimensions, (528, 408) if frame == "framed" else (480, 320))
                hashes[theme, frame] = hashlib.sha256(png).hexdigest()
            self.assertNotEqual(hashes["light", "raw"], hashes["dark", "raw"])
            original = output.read_bytes()
            for width in ("0", "-1", "nan", "4097", "999999999999999999"):
                run(fixture, output, width, 320, "en_US")
            run(fixture, output, 480, "0", "en_US")
            run(fixture, output, 480, 320, "bad locale")
            run(fixture, output, 480, 320, "en_US", "title", "--unknown")
            run(root / "missing.swift", output, 480, 320, "en_US")
            run(fixture, root / "missing/gallery.html", 480, 320, "en_US")
            run(fixture, work / "wrong.txt", 480, 320, "en_US")
            link = work / "symlink.html"
            link.symlink_to(output)
            run(fixture, link, 480, 320, "en_US")
            hardlink = work / "fixture.html"
            os.link(fixture, hardlink)
            run(fixture, hardlink, 480, 320, "en_US")
            broken = work / "Broken.swift"
            broken.write_text("This is not Swift.\n")
            run(broken, output, 480, 320, "en_US")
            runtime_failure = work / "RuntimeFailure.swift"
            runtime_failure.write_text(fixture.read_text().replace(
                "static func makeView() -> some View { ExampleSettings() }",
                'static func makeView() -> some View { if CommandLine.arguments[4] == "dark" { fatalError("Intentional render failure") }; return ExampleSettings() }'))
            run(runtime_failure, output, 480, 320, "en_US")
            self.assertEqual(output.read_bytes(), original)
            self.assertEqual(list(work.glob(".swiftui-gallery-*")), [])


if __name__ == "__main__":
    unittest.main()
