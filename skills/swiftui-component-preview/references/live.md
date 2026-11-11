# Live native window

Read this before building or launching a live preview. `<skill-directory>` is the directory containing `SKILL.md`.

For real buttons, text input, focus, and next/back transitions, use the same `PreviewFixture.makeView()` entry point with stateful local actions. [../assets/LiveExampleFixture.swift](../assets/LiveExampleFixture.swift) demonstrates a `NavigationStack` with pushed screens (welcome → editable profile → success → details), a sheet, an alert for a simulated error, a confirmation dialog, and common controls (text fields, segmented picker, stepper, slider, toggles), all without services or persistence. Sheets, alerts, and navigation chrome need the real window; do not judge them from a detached PNG render.

Build a standalone app at a **new** output path:

```bash
bash "<skill-directory>/scripts/live.sh" \
  "/absolute/path/LiveFixture.swift" "/absolute/path/SwiftUI Preview.app" \
  640 480 en_US
```

Arguments are fixture, output app, content width, content height, and initial locale. Dimensions and locale validation match the renderer. The parent directory must exist; existing files, directories and symlinks are rejected. A failed compile leaves no partial app. The build uses Swift 6 strict concurrency and macOS 14 as its minimum target. It compiles only the supplied fixture and `scripts/LiveHost.swift`, with a unique generic bundle identifier and no project app delegate, entitlements, services, or production entry point.

The command **builds only**. When launching a local preview is within the user's request and permitted by the environment, open that exact generated `.app` through the available native-app tooling or Finder. Respect a launch denial; report the limitation and leave the built artifact available for review. The native window is a separate macOS window, not part of the agent's file, image, or browser panel. Do not claim interaction was tested until you have exercised it in the actual window.

Developer controls are grouped in a capsule on a translucent glass bar beneath the content viewport: a System/Light/Dark appearance switch, a locale menu with the initial locale plus `en_US` and `ru_RU`, the current viewport size, and Reset. The window opens at the configured size and is resizable; the fixture is laid out again at each size, the bar shows the live size in points, and clicking that size restores the configured one. Use this to check how a component adapts, and report sizes other than the configured one as such. Theme and locale selections are ephemeral. Locale changes inject SwiftUI's environment; they do not create translations, link missing bundles, or automatically set RTL layout. Reset changes fixture identity to recreate its view-local state. It does not roll back globals, files, stores or any effects outside the fixture. Changes to Swift source never appear in an open window; rebuild with `refresh` (below) or build again at a new output path.

This is a trusted-code helper, not a sandbox. Supplied fixtures execute with normal user permissions when launched; review them and keep their dependencies synthetic and local. For project dependencies, assets, or String Catalogs, explicitly adapt and review the build rather than silently linking the production app or its lifecycle.

## Iterating after code changes

There is no hot reload: the window is a compiled snapshot of the fixture, not of the project source. After the component changes, first carry the change into the fixture (and the live fixture, when one is registered), then run:

```bash
python3 "<skill-directory>/scripts/bootstrap.py" refresh --root "<project-root>" \
  --output ".swiftui-preview/artifacts/StatusCard Preview.app" --width 640 --height 480
```

`refresh` records the current source and fixture hashes, builds to a staging path, closes any window running from that exact output app, replaces the app, and opens it. Keep one stable output path per component so each refresh replaces the previous window. It only replaces a bundle this skill built and refuses any other existing path. A failed build leaves the old app, its window, and the saved configuration untouched. Add `--no-launch` when launching is outside the request.

It starts a new process, so typed text, navigation position, and other view-local state are lost; tell the user. Running it is your statement that the fixture now matches the source: do not use it to silence a stale-hash error without readapting.

## One fixture or two

A single fixture serves render, gallery, and live when its actions are view-local and visible, such as toggles, text fields, and navigation. Add a separate live fixture when the static one uses inert actions that would leave nothing to observe in the window, for example a button whose real effect goes through a service. In the live fixture, replace the service with a synthetic in-memory stand-in that produces a visible result: a state change, a simulated error, or a short `Task.sleep` before completing. Keep network, persistence, credential stores, and work that outlives the view out of both fixtures.

Register it with `configure ... --live-fixture ".swiftui-preview/fixtures/StatusCardLive.swift"`. `run --mode live` then builds the live fixture while render and gallery keep the static one. The live fixture follows the same contract and text checks, its hash is recorded, and editing it requires `configure --replace` with every path again. Omitting `--live-fixture` on a replace removes it.

## Viewport

The live build needs numeric dimensions and the window is never narrower than 380 points or shorter than 40, so a smaller configured viewport opens at that minimum. For small components, render with `fit` first and pass a width of at least 380 with a height that leaves room around the reported size.
