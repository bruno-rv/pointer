# Stable source-built Pointer app design

Date: August 9, 2026

Status: Approved for implementation planning

## Outcome

The GitHub repository must contain a production Pointer app that a developer
can clone, build, and launch with one command. The build must require only an
Apple silicon Mac, macOS 14 or later, and Xcode 15.4 or later. It must not
require an Apple Developer account, package manager, project generator,
third-party dependency, secret, or machine-specific path.

The public quick-start command is:

```sh
./scripts/run-app.sh
```

That command builds a Release app bundle, ad-hoc-signs it, and opens it. The
output is `build/Pointer.app`.

## Scope

The first stable source build includes:

- A menu-bar application with a floating tool palette.
- One transparent, always-on-top annotation overlay per physical display.
- Annotation and click-through standby modes.
- A configurable Carbon global shortcut with a working default.
- Select, arrow, rectangle, ellipse, pen, eraser, emoji, and spotlight tools.
- Color, stroke width, opacity, spotlight radius, and spotlight dimness.
- Move, resize, delete, undo, clear, and clear-all behavior.
- In-memory, display-local canvases that survive mode, application, Space, and
  temporary display changes during the current process.
- Unit, integration, bundle, launch, and clean-clone verification.
- GitHub Actions verification on pushes and pull requests.

## Out of scope

This source-build milestone does not include:

- Saved canvases or restoration after the app exits.
- Screenshots, exports, text annotations, or mark rotation.
- Intel Mac support.
- Developer ID signing, notarization, a disk image, an installer, automatic
  updates, or a downloadable public release.
- Guarantees over DRM-protected video, secure system UI, the lock screen, or
  future WindowServer policy.

## Package and module structure

The repository will use one root Swift package with Swift tools version 5.10
and a macOS 14 deployment target.

The package will expose these production targets:

- `PointerCore`: value models, geometry, normalized coordinates, hit testing,
  undo state, tool state, mode transitions, palette placement, and display
  ownership rules. It will not import AppKit.
- `PointerAppKit`: AppKit windows, views, app lifecycle, menu-bar state, screen
  observation, and Carbon shortcut registration. It depends on `PointerCore`.
- `Pointer`: a minimal executable target that starts `PointerAppKit`.
- `PointerCoreTests`: deterministic model and behavior tests.
- `PointerAppKitTests`: focused coordinator tests behind explicit test
  seams.

Prototype packages remain isolated under `.scratch/`. Production targets may
port their proven behavior, but must not depend on or import prototype code.

## Application architecture

All AppKit coordination runs on the main actor.

### App lifecycle

`AppDelegate` creates the status item, display coordinator, palette controller,
shortcut controller, and shared session state. `LSUIElement` keeps Pointer out
of the Dock while the menu-bar item remains available as a control fallback.

Pointer launches in standby mode and shows the palette on the display that
contains the pointer. Launching the app never blocks clicks in another app.
Arrow launches as the selected tool with red, four-point, fully opaque styling.

### Session state

`PointerSession` owns:

- The current annotation or standby mode.
- The selected tool and its style.
- A canvas dictionary keyed by stable display UUID.
- The current shortcut setting and last registration error.

Display canvases use ordered value-type marks with stable UUIDs. A canvas stores
normalized display-local coordinates so resolution, scale, rotation, and
display arrangement changes do not rewrite mark geometry.

Each completed gesture creates one undo snapshot. An eraser drag is one undoable
gesture. Clearing the pointer display is undoable. Clearing all displays uses a
confirmation alert and creates one restorable session snapshot. The menu-bar
**Undo Clear All** command restores every canvas and its prior undo history. It
remains available until the next canvas mutation.

### Interaction contract

Pointer uses these exact pointer interactions in annotation mode:

- Arrow, Rectangle, and Ellipse create a mark from mouse-down to mouse-up.
- Pen appends normalized points during a drag and commits one freehand mark on
  mouse-up.
- Emoji stamps the selected preset at a click. Dragging while stamping sets its
  initial size.
- Spotlight creates or replaces the display spotlight. Drag distance sets its
  radius; a click uses the current default radius.
- Eraser removes every mark hit during a click or drag and groups those removals
  into one undo operation.
- Select chooses the topmost mark under a click. Dragging inside a selected mark
  moves it. Dragging a visible handle resizes it. Clicking empty canvas clears
  selection.
- Delete and Backspace remove the selected mark while an overlay owns keyboard
  focus.

Arrow exposes start and end handles. Rectangle and ellipse expose eight bounds
handles. Freehand and emoji expose four corner handles with aspect ratio
preserved. Spotlight exposes a center handle and one radius handle. Rotation is
never offered.

The emoji presets are:

- `👉` (default)
- `⭐️`
- `✅`
- `❗️`
- `❤️`
- `🎯`

Choosing a preset updates the selected emoji mark, when present, and the default
for future stamps.

Style controls update a compatible selected mark and the default for future
marks. Opacity applies to every mark type. Color and stroke width apply to
arrows, rectangles, ellipses, and pen strokes. Spotlight radius and dimness
apply to the selected spotlight and future spotlights.

Undo in the palette affects the pointer display. Clear removes every mark on
the pointer display as one undoable operation. Clear All Displays is available
only from the menu bar, requires confirmation, and enables **Undo Clear All**.

### Display coordination

`DisplayCoordinator` observes screen-parameter changes and maintains one
`OverlayPanel` and `CanvasView` per connected `NSScreen`.

The display key comes from `CGDisplayCreateUUIDFromDisplayID`, not the transient
display ID alone. A disconnected display's canvas remains in the session. When
the same display returns, Pointer reconnects it to that canvas.

Each overlay is a transparent, borderless, non-activating `NSPanel` at the
screen-saver window level. Its collection behavior joins all Spaces and
full-screen applications. Standby sets `ignoresMouseEvents`; annotation mode
accepts pointer input.

### Mark rendering and editing

`CanvasView` draws directly with AppKit from the ordered mark values. Reverse
hit testing selects the topmost mark.

The mark geometries are:

- Arrow from start to end.
- Rectangle and ellipse from normalized bounds.
- Freehand stroke from normalized points.
- Emoji stamp with normalized center and size.
- Spotlight with normalized center, radius, and dimness.

A display can contain at most one spotlight. Creating another replaces it in
one undoable operation. The spotlight leaves its focus circle visible and dims
the rest of that display.

Select moves or resizes a mark. Delete removes the selected mark. Eraser removes
every hit mark during a drag and commits one undo snapshot at drag end.

### Palette and menu bar

`PaletteController` owns one draggable, non-activating palette panel. Explicitly
showing it places it near the top center of the pointer's display and clamps it
to that display. Manual dragging is preserved until the next explicit show.

The palette exposes:

- Select, Arrow, Rectangle, Ellipse, Pen, Eraser, Emoji, and Spotlight.
- A compact emoji preset picker with the six defined presets.
- Color, stroke width, opacity, spotlight radius, and spotlight dimness.
- Undo and Clear for the pointer display.
- A visible annotation or standby state.
- An accessible label and keyboard focus behavior for every control.

The menu-bar item exposes Show Palette, Enter or Exit Annotation, shortcut
selection, Clear All Displays, Undo Clear All when available, and Quit.

The palette uses a native `NSVisualEffectView` with system HUD material, a
12-point corner radius, and two compact control rows. The first row contains the
mode indicator and eight tool buttons. The second contains style controls,
contextual emoji or spotlight controls, Undo, and Clear. Its width is the lesser
of 760 points or the current display's visible width minus 32 points. Shortcut
errors appear in an additional status row and never resize an overlay.

### Shortcut behavior

`HotKeyController` uses non-exclusive Carbon `RegisterEventHotKey`. It does not
use global AppKit event monitors, Quartz event taps, accessibility operations,
input synthesis, or screen-capture APIs.

The default `Control-Option-Command-P` shortcut toggles annotation and standby.
Choosing a drawing tool enters annotation. Escape always returns to standby
without hiding marks or the palette.

The first build offers `Control-Option-Command-P` and
`Control-Option-Command-O`. When the user changes the preset, Pointer registers
the candidate provisionally and starts a five-second delivery test. The palette
instructs the user to focus another app and press the candidate chord. Pointer
persists it only after receiving the Carbon event. A registration error or
delivery timeout restores the previous working shortcut and shows an actionable
error. Menu-bar mode control remains usable without the shortcut.

The successful preset is stored in standard `UserDefaults` under the app bundle
identifier. On launch, Pointer attempts the stored preset first. If registration
fails, it attempts `Control-Option-Command-P`. If both fail, Pointer starts with
the shortcut disabled, reports the error in the menu and palette, and preserves
all non-shortcut controls.

## Build and bundle contract

`scripts/build-app.sh` will:

1. Confirm that the host is macOS on Apple silicon.
2. Discover the active developer directory through `xcode-select` unless the
   caller supplies `DEVELOPER_DIR`.
3. Confirm Xcode 15.4 or later and the required native tools.
4. Run a Release Swift build for the `Pointer` executable.
5. Create `build/Pointer.app` from tracked bundle metadata and resources.
6. Copy the Release executable into `Contents/MacOS`.
7. Ad-hoc-sign the bundle with `/usr/bin/codesign --sign -`.
8. Validate the property list, executable, and signature.

The script must be idempotent and must never rely on `/Users/...`, a fixed Xcode
installation path, shell profile state, Homebrew, or untracked files.

`scripts/run-app.sh` invokes the build script and then opens the resulting app.
Any failure exits nonzero and prints the failed prerequisite or command.

## Verification strategy

### Automated behavior tests

Tests will cover:

- Normalized coordinate conversion and display resize behavior.
- Mark creation, topmost hit testing, move, resize, and delete.
- Gesture-scoped undo, erase, clear, and clear-all restoration.
- Single-spotlight replacement and spotlight style changes.
- Annotation and standby transitions, including Escape behavior.
- Pointer-display palette placement and clamping.
- Stable display ownership across disconnect and reconnect.
- Shortcut candidate persistence and failure rollback.
- Stored-shortcut startup fallback and relaunch behavior.

Core tests use real values and behavior. AppKit coordinators receive narrow
interfaces for screen descriptions and shortcut registration so tests do not
mock global framework state.

### Repository verification

`scripts/verify.sh` will:

1. Run all Swift tests.
2. Build the Release app bundle.
3. Lint the property list.
4. Verify the bundle signature and executable architecture.
5. Run a deterministic non-interactive app smoke mode.
6. On an interactive local host, launch the real app and confirm its process
   and expected Pointer-owned windows appear.

GitHub Actions invokes the same script with `CI=1` on the standard `macos-15`
arm64 runner. It asserts `uname -m` is `arm64`. CI uses the non-interactive
smoke mode because hosted runners do not guarantee an interactive desktop
session.

### Runtime validation matrix

Implementation will add a tracked
`.codex/sdd/reports/stable-source-build/validation.md` report. Every run records
the date, commit, macOS and Xcode versions, architecture, connected displays,
test steps, pass or fail result, and evidence path.

Automated gates are:

- Unit and coordinator tests on the pinned `macos-15` arm64 runner.
- Release build, property-list lint, ad-hoc signature verification, and arm64
  executable verification.
- Non-interactive smoke output containing one palette, one overlay per reported
  display, standby mode, and a valid default shortcut candidate.
- Fresh-clone execution of the README commands.

The physical-host manual matrix is:

- Launch with one palette and one click-through overlay per connected display.
- Toggle annotation from another app with the default shortcut, then return to
  standby with Escape.
- Draw, select, move, resize, delete, erase, undo, and clear every mark type.
- Create and replace a spotlight; change its radius and dimness.
- Show the palette on each pointer display and drag it across displays without
  disabling any overlay.
- Keep marks visible through application changes, Space changes, and a native
  full-screen video window.
- Disconnect and reconnect a secondary display without moving or losing its
  in-process canvas.
- Change and relaunch with the alternate shortcut, reject an invalid candidate,
  and recover from a chord held exclusively by another process.
- Run with Accessibility, Input Monitoring, and Screen Recording denied; record
  any privacy prompt or matching TCC log activity.

While GitHub still provides its standard `macos-14` arm64 image, CI also runs a
temporary compatibility job there. The durable required lane is `macos-15`
because GitHub has announced retirement of the macOS 14 image. Continuing
runtime coverage on macOS 14 after that retirement requires a self-hosted Sonoma
runner; it must not make the normal public build depend on private
infrastructure. The physical matrix runs on the current Apple silicon host.
README support claims distinguish the macOS 14 deployment target, automated
runner coverage, and the exact physical runtime used for manual verification.

### Portability and clean-clone gate

Before publication, the branch must pass all of these checks:

- No machine-specific absolute paths or undocumented environment assumptions.
- Every repository-relative path referenced by source, scripts, bundle metadata,
  workflows, and README exists and is tracked. Absolute Apple system-tool paths
  are validated prerequisites.
- All imports are provided by Apple frameworks or the Swift standard library.
- Internal links, commands, versions, target names, and entry points are
  current.
- A fresh clone of the candidate remote branch can follow the README literally,
  run `./scripts/run-app.sh`, produce `build/Pointer.app`, and launch it.
- The fresh clone can run `./scripts/verify.sh` with no local repository state,
  secret, or manual file copy.

## Remote publication gate

The branch may be pushed only after fresh verification confirms:

- All tests pass with zero failures.
- The production app builds without warnings that affect correctness.
- Bundle property-list and signature validation pass.
- The real local app launches and exposes its palette and overlays.
- The documented shortcut, annotation, standby, drawing, editing, undo, clear,
  spotlight, and multi-display flows have current runtime evidence.
- Shortcut relaunch, conflict, fallback, and denied-permission cases have
  current runtime evidence.
- The portability audit and fresh-clone run pass.
- `git diff --check` passes and only intended files are included.

After the push, clone the GitHub repository by its public URL and repeat the
documented build and verification commands. The remote is complete only when
that post-push clone succeeds.

## Resolved design decisions

- The public contract is source build, not a downloadable signed release.
- SwiftPM and native shell tools are the only build dependencies.
- The full approved MVP toolset is in scope.
- The app starts in safe click-through standby with a visible palette.
- The default shortcut toggles annotation and standby.
- Canvases are in-memory and display-local for the current process.
- A menu-bar fallback remains available when shortcut registration fails.
- Production code is separated from disposable prototypes.
