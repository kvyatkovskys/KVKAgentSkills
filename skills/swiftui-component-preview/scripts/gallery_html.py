#!/usr/bin/env python3
"""Package completed renderer PNGs as an offline, self-contained gallery.

When `cwebp` is installed, each PNG is embedded as lossless WebP if that is smaller.
Set PREVIEW_GALLERY_WEBP=0 to always embed the PNGs.
"""
import base64
import hashlib
from html import escape
import json
import os
import signal
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

SCRIPT = """const variants = JSON.parse(document.getElementById('variants').textContent);
const image = document.getElementById('preview');
variants['light-framed'].src = image.getAttribute('src');
const frame = document.getElementById('frame');
const status = document.getElementById('status');
const pixels = document.getElementById('pixels');
const scale = Number(image.dataset.scale);
function updatePreview() {
  const theme = document.querySelector('input[name="theme"]:checked').value;
  const framed = frame.checked;
  const variant = variants[theme + (framed ? '-framed' : '-raw')];
  image.src = variant.src;
  image.width = variant.width;
  image.height = variant.height;
  image.alt = image.dataset.title + ': ' + theme + ' SwiftUI component render' + (framed ? ' with decorative frame' : ' without frame');
  document.documentElement.dataset.theme = theme;
  pixels.textContent = variant.width * scale + ' × ' + variant.height * scale + ' px';
  status.textContent = (theme === 'light' ? 'Light' : 'Dark') + ' appearance · ' + (framed ? 'Decorative frame' : 'No frame');
}
document.getElementById('controls').addEventListener('change', updatePreview);
updatePreview();"""

STYLE = """*{box-sizing:border-box} :root{font-family:ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color-scheme:light;--bg:#f5f5f3;--surface:#fff;--ink:#222522;--muted:#666d66;--line:#dedfdb;--well:#e9eae6;--selected:#252b27;--on-selected:#fff;--focus:#3978c8}
:root[data-theme=dark]{color-scheme:dark;--bg:#191c1a;--surface:#242825;--ink:#f1f3ef;--muted:#a9b1aa;--line:#414741;--well:#121613;--selected:#e4eae2;--on-selected:#202820;--focus:#90baff}
body{margin:0;background:var(--bg);color:var(--ink)} main{max-width:1120px;margin:0 auto;padding:clamp(20px,5vw,52px)}
.eyebrow{font-size:11px;font-weight:650;letter-spacing:.12em;text-transform:uppercase;color:var(--muted);margin:0 0 12px} h1{font-size:clamp(23px,4vw,32px);line-height:1.18;letter-spacing:-.035em;margin:0;overflow-wrap:anywhere} .intro{font-size:14px;line-height:1.6;color:var(--muted);margin:12px 0 24px;max-width:55ch}
.gallery{border:1px solid var(--line);border-radius:18px;overflow:hidden;background:var(--surface)} form{display:flex;align-items:center;justify-content:space-between;gap:18px;flex-wrap:wrap;padding:16px 20px;border-bottom:1px solid var(--line)} fieldset{border:0;padding:0;margin:0;min-width:0;display:flex;align-items:center;gap:12px} legend{float:left;padding:0;font-size:12px;color:var(--muted);margin-right:12px;line-height:34px}
.segment{display:flex;gap:3px;border:1px solid var(--line);padding:3px;border-radius:9px} .choice{position:relative} .choice input{position:absolute;opacity:0;width:100%;height:100%;margin:0;cursor:pointer} .choice span{display:block;border-radius:5px;padding:6px 15px;font-size:12px;font-weight:600} .choice input:checked+span{background:var(--selected);color:var(--on-selected)} .choice input:focus-visible+span{outline:3px solid var(--focus);outline-offset:3px}
.frame-label{display:flex;align-items:center;gap:8px;font-size:12px;cursor:pointer} input[type=checkbox]{width:16px;height:16px;margin:0;accent-color:var(--selected)} input[type=checkbox]:focus-visible{outline:3px solid var(--focus);outline-offset:3px}
figure{margin:0} .stage{display:flex;justify-content:center;align-items:center;min-height:280px;padding:clamp(12px,3vw,32px);background:var(--well)} #preview{display:block;max-width:100%;height:auto;object-fit:contain;border-radius:4px} figcaption{display:flex;justify-content:space-between;align-items:center;flex-wrap:wrap;gap:8px;padding:15px 20px;font-size:11px;color:var(--muted);border-top:1px solid var(--line)} #status{font-weight:550;color:var(--ink)} .details{display:flex;flex-wrap:wrap;gap:8px 16px;margin:20px 0 0;color:var(--muted);font-size:11px;line-height:1.7}.note{color:var(--muted);font-size:11px;line-height:1.7;margin:9px 0 0} noscript p{margin:16px 20px;font-size:13px}
@media(max-width:440px){main{padding:20px 14px}form{padding:14px;gap:14px}.stage{padding:10px;min-height:180px}figcaption{padding:14px}.details{gap:4px 12px}}"""


def stop(signum, _frame):
    raise SystemExit(128 + signum)


def payload(png, cwebp):
    """Return (media type, bytes) for one render: lossless WebP when smaller, else the PNG."""
    data = png.read_bytes()
    if cwebp:
        webp = png.with_suffix(".webp")
        try:
            subprocess.run([cwebp, "-quiet", "-lossless", "-exact", str(png), "-o", str(webp)],
                           check=True, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=120)
            compressed = webp.read_bytes()
        except (OSError, subprocess.SubprocessError):
            compressed = b""
        # Trust the encoder only for a well-formed, smaller file; otherwise keep the PNG.
        if compressed[:4] == b"RIFF" and compressed[8:12] == b"WEBP" and len(compressed) < len(data):
            return "image/webp", compressed
    return "image/png", data


def main():
    for signum in (signal.SIGINT, signal.SIGHUP, signal.SIGTERM):
        signal.signal(signum, stop)
    directory, destination, width, height, locale, title, fixture = sys.argv[1:8]
    # Optional pixels per point; the image is displayed at its size in points.
    scale = int(sys.argv[8]) if len(sys.argv) > 8 else 1
    width, height = int(width), int(height)
    cwebp = None if os.environ.get("PREVIEW_GALLERY_WEBP") == "0" else shutil.which("cwebp")
    variants = {}
    for theme in ("light", "dark"):
        for frame in ("raw", "framed"):
            media_type, data = payload(Path(directory) / f"{theme}-{frame}.png", cwebp)
            variants[f"{theme}-{frame}"] = {
                "src": f"data:{media_type};base64," + base64.b64encode(data).decode("ascii"),
                "width": width + (48 if frame == "framed" else 0),
                "height": height + (88 if frame == "framed" else 0),
            }
    initial = variants["light-framed"]
    # Keep the initial render in the image for no-JS viewing, and embed each payload once.
    variant_data = {
        name: {key: value for key, value in variant.items() if name != "light-framed" or key != "src"}
        for name, variant in variants.items()
    }
    safe_title = escape(title, quote=True)
    script_hash = base64.b64encode(hashlib.sha256(SCRIPT.encode()).digest()).decode()
    page = f'''<!doctype html>
<html lang="en" data-theme="light">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; script-src 'sha256-{script_hash}'; base-uri 'none'; form-action 'none'">
<title>{safe_title} · SwiftUI preview</title>
<style>{STYLE}</style>
</head>
<body><main>
<p class="eyebrow">SwiftUI component preview</p>
<h1>{safe_title}</h1>
<p class="intro">Explore the same component in two appearances. Every variant is rendered from the SwiftUI fixture.</p>
<section class="gallery" aria-label="Component gallery">
<form id="controls" aria-label="Preview options">
<fieldset><legend>Appearance</legend><div class="segment">
<label class="choice"><input type="radio" name="theme" value="light" checked><span>Light</span></label>
<label class="choice"><input type="radio" name="theme" value="dark"><span>Dark</span></label>
</div></fieldset>
<label class="frame-label"><input id="frame" type="checkbox" checked>Decorative frame</label>
</form>
<figure><div class="stage">
<img id="preview" data-title="{safe_title}" data-scale="{scale}" src="{initial['src']}" width="{initial['width']}" height="{initial['height']}" alt="{safe_title}: light SwiftUI component render with decorative frame">
</div><figcaption><span id="status" role="status" aria-live="polite">Light appearance · Decorative frame</span><span id="pixels">{initial['width'] * scale} × {initial['height'] * scale} px</span></figcaption></figure>
<noscript><p>Enable JavaScript to switch between the embedded appearance and frame variants.</p></noscript>
</section>
<p class="details"><span>Viewport {width} × {height} pt</span><span>{scale}× render</span><span>Locale {escape(locale)}</span></p>
<p class="note">Static SwiftUI render. Controls inside the image are not interactive. The frame is decorative.</p>
</main>
<script id="variants" type="application/json">{json.dumps(variant_data, separators=(',', ':'))}</script>
<script>{SCRIPT}</script>
</body></html>
'''
    output = Path(destination)
    # Recheck before replacement; never follow output symlinks or overwrite the fixture.
    if output.is_symlink() or (output.exists() and (not output.is_file() or os.path.samefile(output, fixture))):
        raise ValueError("Unsafe gallery output path")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", prefix=".swiftui-gallery-", dir=output.parent, delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(page)
        os.replace(temporary, output)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    print(output)


if __name__ == "__main__":
    main()
