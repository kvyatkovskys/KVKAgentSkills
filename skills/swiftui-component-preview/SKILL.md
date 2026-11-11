---
name: swiftui-component-preview
description: Use when the user wants to see, preview, render, or screenshot a SwiftUI view or component without opening Xcode Canvas - checking layout, light/dark appearance, locale, fixture states, or local interaction of a macOS-compatible SwiftUI component. Produces PNG renders, an offline HTML theme gallery, or an interactive native macOS window from a fixture adapted from the project's real component.
argument-hint: "[png|gallery|live] <component>"
license: MIT
metadata:
  version: "1.1.0"
---

# SwiftUI Component Preview

Create a component render from a small, deterministic SwiftUI fixture. Requires macOS 14 or later and Xcode 15 or later (Swift 5.9+); Swift 6 is not required. Project onboarding, the HTML gallery, and live builder also require Python 3.8 or later (standard library only). Choose PNGs for static inspection, the gallery for image comparisons, or a native window for real fixture interactions. These helpers do not provide Xcode Canvas or hot reload.

## Choose the output

Decide the output before building anything, in this order:

1. **Explicit word.** If the request or the skill arguments start with or name `png`, `gallery`, or `live` (also "screenshot", "render" for PNG; "window", "interactive" for live), use that.
2. **Intent of the request.**

   | The user wants to | Output |
   | --- | --- |
   | see how it looks, check layout, spacing, text, a state, a locale | PNG |
   | compare light and dark, or framed and unframed, side by side or by toggling | Gallery |
   | click, type, toggle, navigate, open a sheet or alert, check a flow | Live window |

   When a request matches more than one row, interaction wins: anything that only appears after a click or input needs the live window.
3. **Whole screen or flow, no signal.** If the target is an entire screen or a multi-step flow and neither rule above applies, as in "preview the checkout screen", ask one question offering PNG, gallery, and live window.
4. **Default.** For a single component with no signal, produce one light PNG, sized with `fit`. It is the fastest output and the only one you can inspect yourself. Then add one line offering the other two outputs.

Rules 1, 2, and 4 proceed without asking. When several outputs are requested, produce all of them from the same configuration. Do not store the choice in `.swiftui-preview/config.json`: it belongs to the request, not the project.

## First use in a project

`<skill-directory>` in the commands below is the directory containing this `SKILL.md`; resolve it from the installed location. Claude Code states it as the skill's base directory when the skill loads (`${CLAUDE_SKILL_DIR}`); in Codex and other agents use the path this file was read from. No developer-specific paths or settings are needed. Use the user's current project root and run read-only discovery:

```bash
python3 "<skill-directory>/scripts/bootstrap.py" discover --root "<project-root>"
```

Discovery reports SwiftPM manifests, Xcode projects/workspaces, SwiftUI sources, `#Preview` presence, and textual platform evidence. It never evaluates manifests, runs plugins, builds, or modifies the project. Nested dependency/build directories and symlinks are skipped. Missing platform metadata means unknown, not unsupported. Use the request and discovered paths to choose the intended project and component. Ask only for selection that remains genuinely ambiguous; multiple markers alone need not force a question when the requested source is clear.

Read the chosen **actual source**, its existing `#Preview` construction, and necessary local definitions before creating a fixture. The skill agent performs this adaptation as part of the first preview request; do not stop at instructions telling the user to adapt it manually when you can do so safely. Keep the component's real view hierarchy, controls, styles, and inputs. Extract its value view and include required local definitions, replacing service dependencies with synthetic values and local actions. Do not substitute a lookalike screen, generic demo, or the bundled example for the requested component. The examples illustrate the fixture API only.

Save the adapted fixture inside the user's project, for example `.swiftui-preview/fixtures/StatusCard.swift`. Never copy project source into the shared installed skill. Include no `@main`, app delegate, production composition root, `#Preview` macro, or production services. `configure`, `run`, and `refresh` scan the fixture as text and reject it when `@main`, `#Preview`, or `import UIKit` appears anywhere, comments included; keep those strings out of comments too. The error names the matched token and its line. Inspect the whole fixture before executing it: executable Swift runs with normal caller permissions; this helper is not a sandbox. Configuration hashes cannot establish visual fidelity or absence of side effects.

If explicit UIKit or iOS-only APIs make the component incompatible with macOS, use an available iOS Simulator/Xcode Canvas workflow or report the precise unsupported dependency. The generic macOS host does not run UIKit. If modules, assets, or String Catalogs cannot be safely adapted into the single-file contract, use an available project-specific workflow or state the concrete limitation. Do not silently link the production app, execute its lifecycle, or change its build configuration.

After preparing and reviewing the genuine fixture, save the selected paths (relative to the project root):

```bash
python3 "<skill-directory>/scripts/bootstrap.py" configure --root "<project-root>" \
  --project "Package.swift" --source "Sources/StatusCard.swift" \
  --fixture ".swiftui-preview/fixtures/StatusCard.swift" --component StatusCard
```

`--project` also accepts a relative `.xcodeproj` or `.xcworkspace` directory; `init` aliases `configure`. Add `--live-fixture "<relative path>"` to register a separate stateful fixture for live builds (see [references/live.md](references/live.md)). The versioned `.swiftui-preview/config.json` stores only relative paths, component name, platform `macos`, and SHA-256 hashes of the selected source and adapted fixture. It relocates with the project and may be committed by the user; perform no Git actions unless requested. Existing configuration is preserved unless explicitly replaced with `configure --replace` after inspection and adaptation. Selected paths and configuration must exist within the root, without symlinks or path traversal.

After `configure` succeeds, produce the first preview with `run` as described next. The direct helpers in later sections are for one-off fixtures that have no saved configuration.

## Subsequent previews

When configuration exists, inspect it and use `run`. It validates the schema, paths, and hashes before dispatching a known helper with fixed argument positions:

```bash
python3 "<skill-directory>/scripts/bootstrap.py" run --root "<project-root>" \
  --mode render --output "/absolute/task-output/card.png" \
  --width 480 --height 320 --locale en_US --theme light --frame
```

Use `--mode gallery` with an `.html` output or `--mode live` with a new `.app` output. `--theme` and `--frame` apply only to render; galleries include all variants and live previews have native controls. The output parent must exist; bootstrap rejects existing outputs rather than replacing them, unlike the direct `render.sh` and `gallery.sh` helpers; to re-render, choose a new filename or remove the old task-owned artifact first. Relative output paths resolve from the project root. `--mode live` builds only; launching and inspection rules are in [references/live.md](references/live.md).

Changed source or fixture hashes stop execution. Reinspect the actual component, update the fixture, then run `configure --replace` with the selected paths, or `refresh` when a live window is being iterated. Also inspect changes to supporting definitions/resources: hashes cover the primary source and self-contained fixture, not the entire dependency graph. Switching components follows the first-use adaptation workflow before replacing configuration. Preserve user edits to existing fixtures.

## Fixture contract and direct helpers

The renderer compiles one self-contained Swift file together with its helper. Its entry point is:

```swift
import SwiftUI

@MainActor
enum PreviewFixture {
    static func makeView() -> some View {
        Text("Example")
    }
}
```

The helpers compile in Swift 6 language mode with strict concurrency when the compiler supports it, and in Swift 5 mode otherwise. When a fixture adapted from a Swift 5 project fails only on concurrency diagnostics (`Sendable`, actor isolation), do not rewrite the component to satisfy them: pass `--swift-version 5` to `run` or `refresh`, or set `PREVIEW_SWIFT_VERSION=5` for the direct helpers, and say the preview was built in Swift 5 mode.

Use synthetic data and fixed initial state. Use inert actions for static renders; live fixtures can implement view-local state changes, validation, and navigation. Include the component's required local view types in the fixture; preserve real SwiftUI controls such as `Form`, `TextField`, `SecureField`, and `Toggle`. Keep credential stores, network calls, persistence, and work that outlives the view out of the fixture; a live fixture may simulate a service with a short in-memory delay.

When the project already has `#Preview` fixtures, reuse their view construction and inputs. Do not compile the `#Preview` macro or an `@main App` in this standalone fixture. Do not rewrite project configuration just to render a component.

The same fixture contract works across projects for SwiftUI components that compile for macOS. UIKit-only components require an iOS simulator workflow. The helpers do not automatically link arbitrary project modules or compile/copy assets and String Catalogs. Extract a self-contained value view where practical. If the component needs project modules or bundles, explain that this standalone command needs an explicitly adapted build; do not claim locale injection supplies missing translations or resources.

## Render and inspect

Use paths appropriate to the current task. Resolve the skill directory from this skill's location, quote every path, and create the output parent directory first. Invoke:

```bash
bash "<skill-directory>/scripts/render.sh" \
  "/absolute/path/Fixture.swift" "/absolute/path/component-light.png" \
  480 320 light en_US
```

Arguments are fixture, output PNG, content width, content height, appearance (`light` or `dark`), and locale identifier. Width and height are integers from 1 to 4096, rendered at one pixel per point, or `fit`. An existing output file is replaced atomically; choose task-owned paths. Repeat with `dark` and a distinct filename when appearance comparison is useful. The locale sets SwiftUI's environment only; select RTL layout direction explicitly in a fixture if that is part of the test.

**Choosing the viewport.** Size it to the component, not to the example numbers. For a full screen use the target window or device size in points. For a row, card, or control, pass the width of its real container and `fit` for the height, such as `390 fit`; the renderer measures the fixture's ideal size on each fitted axis and prints `render: fitted content size WxH` to stderr. `fit fit` suits intrinsically sized controls, but views built around `Spacer`, `maxWidth: .infinity`, or `ScrollView` collapse to their minimum on a fitted axis, so give those a number. `run --mode render` accepts `--width fit` and `--height fit`; gallery and live need numbers, so reuse the reported size there.

Append `--frame` only when requested or useful for presentation. It adds a decorative title bar and surrounding padding outside the fixed content viewport: output dimensions become width + 48 by height + 88. Its traffic lights are drawn shapes. It does not create a real window or validate native window chrome.

Inspect the generated image with the available local-image viewer before reporting visual results. If content is absent or clipped, first check the fixture's layout and viewport. Stop and explain components that need a window, app lifecycle, or unavailable resources rather than quietly launching the production app.

## Gallery and live window

Two further outputs use the same fixture contract. Read the linked reference in full before producing either; each has rules on output paths, launching, and what counts as verified.

- **HTML theme gallery**, when the user wants to compare light/dark or toggle the decorative frame: `run --mode gallery`, or `scripts/gallery.sh` directly. See [references/gallery.md](references/gallery.md).
- **Live native window**, for real buttons, text input, focus, and navigation: `run --mode live`, or `scripts/live.sh` directly. It builds an `.app` and does not launch it. A static fixture with inert actions shows nothing when clicked; [references/live.md](references/live.md) explains when to add a separate stateful fixture with `configure --live-fixture`. An open window never picks up code changes: after updating the fixture, `refresh` rebuilds the app at the same path, closes the old window, and reopens it (same reference).

## Present the result

Inspect every artifact yourself before showing it, then present it with whatever the current agent offers. Use the tools actually available in the session; do not assume one from this list exists.

**Output location.** Use a task-owned directory. When the client can only display files inside the project, write to `<project-root>/.swiftui-preview/artifacts/` (create it first) and perform no Git actions on it unless requested.

**Claude Code.**

- PNG: read the file with the Read tool to inspect the image. To show it, use the session's file-presenting or preview tool when one exists; otherwise give the absolute path as a link, and run `open "/absolute/path/component-light.png"` when the user asked to see it. Inline Markdown images do not render in a terminal.
- HTML gallery: open it in an available browser or preview tool using its `file://` URL, or run `open "/absolute/path/component-gallery.html"`. Exercise the theme and frame controls through a browser tool before reporting them verified; without one, say the controls were not exercised.
- Live app: run `open "/absolute/path/SwiftUI Preview.app"` when launching is within the request; `refresh` opens the app itself unless given `--no-launch`. Verify interaction only through a tool that can drive the native window; otherwise ask the user to try it and report interaction as unverified.
- If a sandboxed shell blocks `swiftc` or its temporary files, request permission to rerun the same helper. Do not edit the helpers or move their temporary directories into the project.

**Codex.** For HTML, discover `open_in_codex` and its current schema. Open the gallery using `target: "browser"`, `placement: "right"`, and the supported absolute `file` path or `url`. For PNGs, use the same tool with `placement: "right"` and an absolute `file` path. If it only reports a queued request, say that the preview was queued; do not claim the user has already seen an opened panel. If unavailable, use an inline Markdown image with the absolute image path, such as `![Component render](/absolute/path/component-light.png)`.

**Any agent.** Browser support for local files varies. If a file cannot open, use an available, permitted local web preview flow or explain the limitation and link the HTML. A local preview server, when supported, should bind to `127.0.0.1` and serve only the task's artifact directory; do not expose the project or home directory. Check the current browser runtime's documented navigation support rather than assuming all localhost previews are prohibited.

Label the artifact a component render, name its appearance/locale/viewport, and identify the frame as decorative when used. Detached rendering is useful for static layout and styles; it does not validate focus, accessibility behavior, interaction, animations, window-dependent materials, or asynchronous lifecycle state. OS and toolchain versions can change native control appearance.

Every output is a macOS rendering. When discovery shows iOS platform evidence for the project or source, tell the user that controls, fonts, and metrics follow macOS conventions and differ on iOS (a `.destructive` button is not tinted red, lists and navigation chrome look different), and that device fidelity needs a Simulator or Xcode Canvas.
