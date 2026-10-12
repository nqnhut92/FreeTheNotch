# Working on FreeTheNotch

Rules for coding agents (and people) changing this repo. What the app does: [README.md](README.md). How it is built: [docs/TECHNICAL_DESIGN.md](docs/TECHNICAL_DESIGN.md). Keep both up to date when behaviour or architecture changes; there is no separate changelog (git history is the log). Whenever you edit either doc, also update its header: README's **Version** line and TECHNICAL_DESIGN's **Last updated** line (date and version). Don't write build numbers in the docs; the About page shows the build of the running copy.

## Workflow

- **After a code change:** build from the shell (below), then stop the running app and press **⌘R** in Xcode.
- **Xcode reload:** if Xcode reports a missing file after `project.pbxproj` changed, quit Xcode, reopen the project, Clean Build Folder (⇧⌘K), then ⌘R.
- **Commits:** ask before committing.
- **Unconfirmed changes:** state plainly what was built and verified, and what still has to be checked on screen.
- **After visual approval:** once the user confirms the interface is correct, stop the app running from Xcode and quit Xcode. Keep it running while visual checks are pending. Do not automatically launch another copy of the app.

## Reference source first

For notch, HUD, lock screen, media, Bluetooth and calendar behaviour, read [Atoll](https://github.com/Ebullioscopic/Atoll) first. For the menu bar panel, read [Vorssaint](https://github.com/vorssaint/vorssaint-utils) first. Follow their approach rather than inventing one.

- **Get the source:** clone with `git clone --depth 1` into the scratchpad (`gh` is not installed).
- **Why:** new behaviour is compared with Atoll's. Both projects are GPL-3.0-or-later, like this repo, so their code can be reused with attribution. Their assets cannot (see Licensing).
- **Attribution:** keep a header comment in each ported file naming the project and the source file.
- **When reporting a fix:** say which file it mirrors, or say up front that there is no reference equivalent.

## Licensing

The repo is GPL-3.0-or-later ([LICENSE](LICENSE)) and public. Notices for everything adapted from elsewhere are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

- **Code from a new project:** check its license first. GPL-compatible only (GPL, MIT, BSD, Apache-2.0). For anything but GPL, add its license text to THIRD_PARTY_NOTICES.md, and add the project to README Credits and the About page's Acknowledgements.
- **Assets (Lottie files, sounds, images):** never take them from Atoll or another repo. Atoll's assets are "Copyright Atoll Contributors" (its COPYRIGHT_ASSETS), not GPL. Bundle only files downloaded from their original source with a free license you can point to (for example a LottieFiles free animation whose page says "Lottie Simple License"), then credit the author and page in THIRD_PARTY_NOTICES.md and README Credits.
- **Lottie files:** vector only. Files with image assets do not load from a bare `.json`.
- **No copyrighted characters** (for example Pikachu), even when LottieFiles lists them as free: the uploader cannot license the character. Users import those themselves as Custom pets.

## Build

```sh
xcodebuild -project FreeTheNotch.xcodeproj -scheme FreeTheNotch -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

This build is only a compile check. The unsigned copy does not match a signed one run from Xcode.

## Before you hand a change back

All of these must pass. A change that fails any of them is not done.

```sh
xcodebuild -project FreeTheNotch.xcodeproj -scheme FreeTheNotch -configuration Debug test CODE_SIGNING_ALLOWED=NO
xcodebuild -project FreeTheNotch.xcodeproj -scheme FreeTheNotch -configuration Release build CODE_SIGNING_ALLOWED=NO
swift format lint -r Sources Tests
```

- **No compiler warnings.** Treat a new warning as an error.
- **Release build too:** the everyday copy is an archived Release build, so behaviour must not depend on `#if DEBUG` code.
- **Formatting** follows `.swift-format` (4 spaces, 120 columns). Run `swift format -i <file>` on every file you edit; the lint must print nothing.

## Tests

Code comes with tests. `Tests/` is a Swift Testing bundle (⌘U in Xcode).

- **What needs a test:**
  - New logic: parsers, formatters, geometry and layout maths, calendar and date rules, settings, file operations.
  - Every bug fix: add a regression test that fails before the fix.
  - Changing behaviour that already has tests: update them in the same change, and say why.
- **What is checked on screen instead:** windows, animations, hover and click handling, and the lock screen. Say in your report exactly what the owner should look at.
- **How the target works:** `FreeTheNotchTests` is non-hosted. It compiles the app sources it needs directly; the app never launches during tests, because launching it can rewrite the user's wallpaper.
  - Put testable logic in a file that compiles without `AppDelegate`, SwiftUI views or Lottie, and add that file to the test target's Sources phase as well.
  - Inject what the logic reads: `UserDefaults(suiteName:)`, a clock or `now`, a `Calendar`, directories, `URLSession`.
- **Writing tests:**
  - Use `import Testing`, `@Test` and `#expect` / `#require`; not XCTest.
  - Use parameterized tests (`@Test(arguments:)`) for tables of cases.
  - Name a test after the behaviour (`tetFallsOnTheFirstDayOfTheFirstMonth`).
  - Assert values you worked out independently (a reference, a worked example, hand arithmetic), never whatever the code currently returns.
  - Tests never touch the real `~/Library`, `UserDefaults.standard`, the network or the user's wallpaper. Use temporary directories and throwaway defaults suites, and clean up.
  - Keep them fast: the whole suite runs in about a second.

## Swift conventions

Follow the [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/). The code is public; write it the way an experienced Swift developer would expect to read it.

- **Naming:**
  - Clear names at the call site, with no abbreviations.
  - Types are `UpperCamelCase`; everything else is `lowerCamelCase`.
  - Booleans read as assertions (`isPlaying`, `hasPrincipalTerm`).
  - Method names say what they do (`restoreBackup()`, not `handle()`).
- **Types and files:**
  - One main type per file, named after it. Split a file before it reaches about 500 lines.
  - Keep pure logic (models, parsers, formatters, layout maths) in Foundation-only files, separate from views and controllers.
- **Access control:** `private` by default, `private(set)` for state that others only read, and `final` on classes that are not subclassed. No global mutable state; caches belong to their owner.
- **Types over strings:**
  - Use enums for closed sets: tabs, keypad keys, sources, settings choices.
  - Raw strings are only for persistence and for APIs that need them.
- **Constants:** no magic numbers. Name sizes, timings and thresholds (`static let`). Keep shared values (animations, colours) in one place, such as `NotchStyle`.
- **Safety:**
  - No force unwraps, `try!` or `as!`, except on literals that cannot fail (`URL(string: "https://…")!` as a `static let`).
  - Use `guard` for early exits.
  - Don't ignore errors with `try?` when the user is told something succeeded.
- **Concurrency:**
  - Mark main-thread-only classes `@MainActor`.
  - Prefer `async`/`await` and `Task` (with `Task.sleep`) over new `DispatchQueue.asyncAfter` chains and `Timer`s.
  - Callbacks from background threads hop to the main actor before touching published state.
- **SwiftUI:**
  - Small views. Use `@ViewBuilder` rather than `AnyView`; `AnyView` is only for the root view handed to an AppKit hosting view or popover.
  - `foregroundStyle`, not `foregroundColor` (the one exception is an optional colour that should fall back to the inherited style).
  - No deprecated APIs.
  - Don't do work in `body` or in a view's `init`: no formatters created per render, no CoreAudio or IOKit calls.
- **User-visible text:** numbers with decimals, dates and units follow the user's locale (decimal comma). Use `FormatStyle` / `.formatted(...)`, or `String(format:locale:)` with a locale; a bare `String(format:)` is fine only for zero-padded integers such as `%02d`.
- **Shared helpers:** reuse them instead of copying:
  - `Subprocess` for command-line tools;
  - `SystemSettings.open(_:)` for System Settings panes;
  - `DurationFormat`, `PanelFormat` and `PlaybackClock` for formatting and playback time;
  - `Logger` (`Sources/Core/Log.swift`) for logs; never `print` or `NSLog`.
- **Comments:**
  - English only.
  - Explain *why*, or a non-obvious constraint. Don't restate the code.
  - No history in code: no dates, no "used to", no "tried … reverted", and no references to the owner or a conversation. History goes in commit messages and TECHNICAL_DESIGN.
  - Doc comments (`///`) on types and on non-obvious members.
  - Keep the attribution header in ported files (see "Reference source first").

## Project file (`FreeTheNotch.xcodeproj/project.pbxproj`)

The project does not use synchronized folders. A new source or resource file needs four entries:

1. `PBXFileReference`
2. `PBXBuildFile`
3. its group's `children`
4. the Sources or Resources phase

- **IDs:** additions use `F1E2D3C4B5A6978877665Xxx` (24 hex digits). Pick an unused one: `grep` the project file for it first.
- **Test target:** a file the tests compile also goes in the `FreeTheNotchTests` Sources phase, with its own second `PBXBuildFile`.
- **Folders:** each folder (for example `Sources/Notch/Calendar`) is a group with `path =`; put the file in the group that matches its folder.
- Quote `$(...)` values: `PRODUCT_NAME = "$(TARGET_NAME)";`.
- Every group that maps to a folder needs `path = Folder;`.
- **Check the result:** run `plutil -lint` on the project file after editing it.

## Code conventions

- **Settings:**
  - Add a `@Published` property with its default, plus one `PersistedSetting` line in the `persisted` table, in `Sources/Core/SettingsStore.swift` (keys `ftn.*`; never rename a key or change its stored type). Saving is automatic. An enum setting stores its raw value and gets a typed accessor; bind the UI to the accessor.
  - Add a row on the section's page, `Sources/Core/SettingsView+<Section>.swift` (`SettingsToggleRow` for a switch, else `SettingsRow`).
  - Features that cannot be triggered on demand get a test button (see HUD → HUD Tests).
- **Notch height:** the only source is `NotchPage.bodyHeight(for:…)`. If a new input changes it, add a sink in `NotchWindowController` so the hit area follows.
- **Popovers opened from the notch:** they must set `NotchPopoverTracker.shared.isOpen`. Use `FittingScrollView`, not a bare `ScrollView`.
- **Main thread:** never run subprocesses (`system_profiler`, `pmset`, `nettop`) or blocking I/O on it. Read a subprocess pipe before waiting on it, and add a timeout.
- **Layout loops:** never measure a container and feed the size back into its children (`onGeometryChange` hung the app).
- **Render cost:** no `drawingGroup()` over large or screen-sized views, and pause `TimelineView` animations when their window is not in front. A screen-sized `drawingGroup` redrawn at 30 fps stalled the whole Mac.
- **New `NSWindow`s created in code:** set `isReleasedWhenClosed = false` if they may be closed and reopened.
- **Menu bar panel text:** use `.panelSecondary` / `.panelTertiary` there. Hierarchical `.secondary` is ignored in the glass panel.

## Do not regress

- No click-to-pin.
- Home is always visible and first in the notch. It cannot be hidden or reordered.
- Do not round the notch's top corners.
- The notch window never resizes; only the SwiftUI shape morphs.
- No battery percentage or charging row in the idle notch.
- Lock screen: no second clock, no full-screen overlay, no delayed hide after unlock. One exception: `LockWallpaperTransition`, a click-through cover while WallpaperAgent restarts for the artwork wallpaper: about 1 s going to the artwork; going back on the lock screen, a still of the user's wallpaper until macOS has swapped it in (see TECHNICAL_DESIGN §3.7).
- Don't snap the seek bar to every bridge sample.
- No screen recording, system-audio capture or microphone use (the purple indicator was rejected).
- Skins stay fixed combos (decoration + pet) on their own Settings page: None, Jungle, Cozy Cat, Christmas, Sakura, Custom. Mix-and-match and the Winter, Autumn, Night, Ocean and Valentine skins were tried and rejected (2026-10-12).
- The Side Notch system panel closes on a click in the Settings window (by design; Vorssaint keeps it open unless the two overlap).
- The old "Preview lock screen" tool (menu bar panel, separate window) was removed. Don't re-add it. The inline preview at the top of Settings → Lock Screen (2026-10-11) replaced it and stays.
- Keyboards without battery reporting (Keychron) have no level. Don't fake one.
- Artwork wallpaper rewrites the user's wallpaper plist. Keep the Application Support backup, the restore at launch and on quit, and never back up over an existing backup.
- Artwork wallpaper, way back on the lock screen: don't lift the cover on a timer. loginwindow keeps showing the artwork after the agent restart; the cover shows the saved still of the user's wallpaper and lifts when macOS re-exports it (TECHNICAL_DESIGN §3.7). No separate button to leave artwork mode: a click on the artwork does it.

## Diagnostics

- **Logs:** `/usr/bin/log show --last 1h --predicate 'subsystem == "com.freethenotch.app"'` (or the older `'process == "FreeTheNotch" AND eventMessage CONTAINS "[FreeTheNotch]"'`, which still works). Use the full path, because `log` is a zsh builtin. Log with `Logger` (`Sources/Core/Log.swift`, one category per area), keep the "[FreeTheNotch]" prefix, and mark values `privacy: .public` only when they are not personal.
- **Hangs:** debug builds write `~/Library/Logs/FreeTheNotch/hang-*.txt` after a 3 s main-thread stall. If the app is hung right now, run `sample <pid> 3` before it is killed.
- **Crashes:** `~/Library/Logs/DiagnosticReports/FreeTheNotch-*.ips`.
- **Permissions:** for TCC problems, look for tccd lines containing "requires entitlement" (for Location, locationd lines containing "doesn't have the entitlement"). A permission prompt that never appears usually means a missing entitlement in `FreeTheNotch.entitlements`. Reset a permission with `tccutil reset <Service> com.freethenotch.app`.
- **Window layering:** check the window layer with `CGWindowListCopyWindowInfo` before guessing.

## Environment

- Test with a locale that uses a decimal comma too (for example Vietnamese), not only English.
- Keep application code under `Sources/` and tests under `Tests/`. Assets, configuration and the Xcode project stay at the root. Never create a nested `FreeTheNotch/` folder.
