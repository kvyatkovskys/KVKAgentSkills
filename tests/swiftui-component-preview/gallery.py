#!/usr/bin/env python3
"""Exercise gallery output and failure cleanup using the actual Swift renderer."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
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
            # The main run embeds PNGs so the assertions do not depend on an installed cwebp.
            environment = dict(os.environ, TMPDIR=str(temporary), PREVIEW_GALLERY_WEBP="0")

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
            self.check_webp(root, fixture, {
                name: base64.b64decode(variant["src"].split(",", 1)[1]) for name, variant in variants.items()})
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

    def check_webp(self, root, fixture, pngs):
        """Repackage the rendered PNGs with stand-in encoders, then with cwebp if installed."""
        renders = root / "renders"
        renders.mkdir()
        tools = root / "tools"
        tools.mkdir()
        encoder = tools / "cwebp"
        output = root / "repackaged.html"

        def package(script=None, **extra):
            for name, png in pngs.items():
                (renders / f"{name}.png").write_bytes(png)
            for stale in renders.glob("*.webp"):
                stale.unlink()
            environment = dict(os.environ, **extra)
            environment.pop("PREVIEW_GALLERY_WEBP", None)
            environment.update(extra)
            if script is not None:
                encoder.write_text("#!/bin/bash\n" + script + "\n")
                encoder.chmod(0o755)
                environment["PATH"] = f"{tools}:/usr/bin:/bin"
            subprocess.run(
                ["python3", str(SKILL / "scripts/gallery_html.py"), renders, output, "480", "320", "en_US", "Title", fixture],
                env=environment, check=True, stdout=subprocess.DEVNULL)
            page = output.read_text()
            sources = re.findall(r'data:image/(png|webp);base64,([A-Za-z0-9+/=]+)', page)
            self.assertEqual(len(sources), 4)
            self.assertIn("img-src data:", page)
            return [(kind, base64.b64decode(data, validate=True)) for kind, data in sources]

        # A smaller, well-formed result replaces the PNG; the last argument is the output path.
        small = package("printf 'RIFF\\004\\000\\000\\000WEBP' > \"${@: -1}\"")
        self.assertEqual([kind for kind, _ in small], ["webp"] * 4)
        self.assertTrue(all(data == b"RIFF\x04\x00\x00\x00WEBP" for _, data in small))
        # Encoder failures, malformed output, larger output and the opt-out all keep the PNGs.
        for script, extra in (
            ("exit 1", {}),
            ("printf 'not a webp file' > \"${@: -1}\"", {}),
            ("{ printf 'RIFF\\004\\000\\000\\000WEBP'; head -c 4000000 /dev/zero; } > \"${@: -1}\"", {}),
            ("printf 'RIFF\\004\\000\\000\\000WEBP' > \"${@: -1}\"", {"PREVIEW_GALLERY_WEBP": "0"}),
        ):
            kept = package(script, **extra)
            self.assertEqual([kind for kind, _ in kept], ["png"] * 4, script)
            self.assertEqual(sorted(data for _, data in kept), sorted(pngs.values()), script)
        if shutil.which("cwebp"):
            for kind, data in package():
                if kind == "webp":
                    # Lossless WebP: a VP8L chunk whose header packs width-1 and height-1 in 14 bits each.
                    self.assertEqual((data[:4], data[8:16], data[20]), (b"RIFF", b"WEBPVP8L", 0x2F))
                    bits = struct.unpack("<I", data[21:25])[0]
                    self.assertIn(((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1), {(480, 320), (528, 408)})


if __name__ == "__main__":
    unittest.main()
