# Interactive gallery

Read this before generating an HTML gallery. `<skill-directory>` is the directory containing `SKILL.md`.

When the user wants to choose a theme or frame, generate a self-contained HTML gallery:

```bash
bash "<skill-directory>/scripts/gallery.sh" \
  "/absolute/path/Fixture.swift" "/absolute/path/component-gallery.html" \
  480 320 en_US "Account preferences"
```

Arguments are fixture, output HTML, content width, content height, locale, and optional title. The dimension and locale rules match `render.sh`. The fixture is compiled once and rendered in four fresh processes: light/dark, each with/without the frame. Only after all renders succeed is the HTML replaced atomically. Use task-owned output paths; directory/symlink outputs and a path that aliases the fixture are rejected.

The file embeds all four renders and has no external assets or requests. When `cwebp` is on `PATH`, each render is embedded as lossless WebP if that is smaller than its PNG, which typically shrinks a large gallery about 2.5 times with identical pixels; otherwise, or with `PREVIEW_GALLERY_WEBP=0`, the PNGs are embedded. `cwebp` is optional (`brew install webp`); never install it without the user's consent. Its native radio buttons and checkbox switch the rendered image, caption and pixel dimensions; the viewport stays fixed. The component itself remains a static render, including its controls. Inspect at least one image and exercise the gallery controls in an available browser before reporting interaction as verified.

The gallery needs numeric dimensions. For a component whose size is unknown, render one PNG with `fit` first and reuse the reported size.
