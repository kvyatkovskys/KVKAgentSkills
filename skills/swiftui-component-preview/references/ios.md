# iOS and iPadOS previews

Read this before producing any output for a project configured with `--platform ios`. `<skill-directory>` is the directory containing `SKILL.md`.

The iOS path compiles the fixture for the iOS Simulator, wraps it in a minimal app, and runs it on a simulator device. Renders therefore use real iOS controls, fonts, metrics, and the device's idiom and size classes. It needs a full Xcode with an iOS 17 or later simulator runtime, and Python 3.8 or later. Fixtures may `import UIKit`; the rest of the fixture contract is unchanged.

## Choosing the platform

The platform is settled once, at `configure`, in this order:

1. **The user's words.** A request for an iPhone or iPad preview is `--platform ios`; a request about the Mac app is `--platform macos`. An explicit `--platform` always wins.
2. **The component.** Without `--platform`, `configure` reads the selected source: `import UIKit` means `ios`, `import AppKit` or `import Cocoa` means `macos`. `#if os(...)` conditionals decide nothing, because they mark shared code.
3. **The project.** Otherwise it reads the selected project: `platforms:` in `Package.swift`, or `SDKROOT`, `SUPPORTED_PLATFORMS`, and the deployment targets in an `.xcodeproj` (for an `.xcworkspace`, in the projects it lists inside the root). Only iOS evidence means `ios`, only macOS evidence means `macos`.
4. **Ask.** A project that targets both, or declares neither, makes `configure` stop with `Cannot choose a platform ...`. Ask the user one question, iOS/iPadOS or macOS, and rerun with the answer. Do not guess, and do not ask when steps 1 to 3 already answered.

`configure` prints the saved `platform` and its `platform_source` (`explicit`, `source`, or `project`); tell the user which platform is used and why. `discover` shows the same reading in advance as `suggested_platform`. The platform is saved in `.swiftui-preview/config.json`, so later previews do not ask again; change it with `configure --replace --platform ...` when the user wants the other one.

```bash
python3 "<skill-directory>/scripts/bootstrap.py" configure --root "<project-root>" \
  --project "App.xcodeproj" --source "Sources/StatusCard.swift" \
  --fixture ".swiftui-preview/fixtures/StatusCard.swift" --component StatusCard
```

Add `--platform ios` or `--platform macos` when the user named the platform or `configure` asked for it.

## Device

`--device` on `run` and `refresh` takes a simulator name or UDID, such as `--device "iPad Air 11-inch (M3)"`. List them with `xcrun simctl list devices available`. Without it the helpers use a simulator that is already booted, otherwise the newest iPhone. The device is part of the request, like theme and locale, and is not saved. Use an iPad device for iPadOS: idiom, size classes, and screen size come from the device.

A simulator that is not running is booted without opening the Simulator application, which takes some seconds the first time, and **stays booted** so later previews are fast. The helper prints the `xcrun simctl shutdown` command for it; tell the user a simulator was started, and shut it down when they ask. Do not erase, delete, or create simulators.

## PNG and gallery

```bash
python3 "<skill-directory>/scripts/bootstrap.py" run --root "<project-root>" \
  --mode render --output "/absolute/task-output/card.png" \
  --width 390 --height fit --theme light --device "iPhone 17"
```

Sizes are in points. Three kinds of viewport:

- **Numbers**, such as `--width 390 --height 300`: the component alone in that box, without safe-area insets.
- **`fit`** on either axis (render only): the fixture's ideal size. Lists, forms, and scroll views have no ideal height on iOS and are rejected with a message; give them a number or `screen`.
- **`screen`** for both width and height (render and gallery): the fixture fills the device as the root view, with its safe areas, navigation bars, and tab bars. Use it for whole screens. The system status bar is not part of the image.

Images are written at 2 pixels per point; `--scale 1`, `2`, or `3` changes that. The helper reports the device, the content size in points, and the scale on stderr, for example `render: iPhone 17 (iOS 26.0), content 390x300 pt at 2x`; reuse the reported size when a gallery should match a fitted or screen render. `--frame` adds a decorative rounded bezel with a drawn status bar: 48 points wider and 88 points taller than the content. It is not the system status bar or a real device frame.

Text in a `SecureField` is blank in renders: iOS withholds secure text from snapshots.

Direct helpers take the same arguments as on macOS with `PREVIEW_PLATFORM=ios`, and read `PREVIEW_IOS_DEVICE`, `PREVIEW_IOS_SCALE`, and `PREVIEW_IOS_TIMEOUT` (seconds to wait for a render, default 90):

```bash
PREVIEW_PLATFORM=ios PREVIEW_IOS_DEVICE="iPad (A16)" bash "<skill-directory>/scripts/render.sh" \
  "/absolute/path/Fixture.swift" "/absolute/path/card.png" screen screen dark en_US
```

Each render builds a throwaway app, installs it on the simulator, and removes it afterward. A fixture that crashes is reported at once; one that never finishes laying out fails at the timeout.

## Live preview in the simulator

By default `run --mode live` builds a simulator `.app` at a new output path and does not install or launch it. The fixture always fills the device screen, so `--width` and `--height` are not used. There is no control bar: the app is the fixture alone, with the configured locale injected.

Install and launch it with the launcher when that is within the request:

```bash
PREVIEW_IOS_DEVICE="iPhone 17" bash "<skill-directory>/scripts/ios-launch.sh" "/absolute/path/StatusCard Preview.app"
```

It boots the device if needed, installs the app, launches it, and opens the simulator's own window so the user can see and use it (the Simulator application, or Device Hub in Xcode versions that ship it instead); set `PREVIEW_IOS_HEADLESS=1` to leave it closed, for example when the agent shows the simulator in its own panel. It only installs bundles this skill built. `refresh` does all of it in one step: it records hashes, rebuilds, replaces the app at the same path, reinstalls, and relaunches; `--no-launch` rebuilds only. One output path is one installed app on the simulator, so repeated refreshes replace it instead of piling up. Remove it when the user is done with `xcrun simctl uninstall <device> <bundle id>`; the launcher prints both.

Switch appearance on the device rather than in the app: `xcrun simctl ui <device> appearance dark` (or `light`), or the simulator's own Features menu. This changes the whole simulator, so restore it when you changed it. Verify interaction only through a tool that can drive the simulator; otherwise ask the user to try it and report interaction as unverified.

## Live preview in a Mac window

`--live-host catalyst` on `run --mode live` and `refresh` builds the same fixture as a Mac Catalyst app instead: an ordinary Mac window that opens at `--width` by `--height` points, with a control bar under the content for System/Light/Dark, the locale, the live viewport size, and Reset. No simulator is involved, so it starts quickly and `--device` does not apply.

```bash
python3 "<skill-directory>/scripts/bootstrap.py" refresh --root "<project-root>" \
  --output ".swiftui-preview/artifacts/StatusCard Preview.app" --width 430 --height 700 --live-host catalyst
```

It is handled like the macOS live app: `run` builds only, `open "/absolute/path/StatusCard Preview.app"` launches it, and `refresh` rebuilds at the same path, closes the old window, and reopens. The direct helper takes `PREVIEW_IOS_LIVE_HOST=catalyst` together with `PREVIEW_PLATFORM=ios`.

Choose it when the user wants a separate window with controls, or quick iteration without a simulator. Say what it is: an **iPad interface running on the Mac**. There is no iPhone idiom, the window has no device safe areas or home indicator, fonts and control metrics are close to iPadOS but not identical, and the window may open a point or two off the requested size because Catalyst scales its points to the screen. For device-accurate layout, or anything iPhone-specific, use the simulator host. APIs unavailable on Mac Catalyst fail to compile; report the API and fall back to the simulator.

## Limits

- The simulator is not a device: performance, haptics, camera, and hardware-backed features differ.
- Project modules, asset catalogs, and String Catalogs are not linked, exactly as on macOS; adapt a self-contained fixture.
- Fixture code runs inside the simulator with the user's normal file access. It is trusted code, not a sandbox.
