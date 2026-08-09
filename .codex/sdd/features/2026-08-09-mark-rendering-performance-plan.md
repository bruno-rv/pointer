# Mark-Rendering Prototype Performance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a real-path release benchmark to `MarkRenderingPrototype`, capture a reproducible baseline, remove per-sample inspector publication from freehand drags, and report measured prototype-only before/after latency.

**Architecture:** Keep the existing SwiftPM executable target. Extract the current event-handler bodies into internal point-based `CanvasView` gesture methods used by AppKit, tests, and a headless benchmark. Add one test target; do not create a production module or copy gesture/model logic into a separate benchmark implementation.

**Tech Stack:** Swift 6.2+, SwiftPM, AppKit, XCTest, `ContinuousClock`, `JSONEncoder`, macOS 14+.

## Global Constraints

- Scope is only `/Users/bruno/Dev/pointer/.scratch/pointer-mvp/prototypes/mark-rendering`.
- Results are prototype event-handler measurements, not production, renderer, frame-rate, compositor, launch, or multi-display claims.
- Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for every Swift build/test command.
- Benchmark an optimized release artifact; do not report debug `swift run` timings.
- The benchmark must call the exact `CanvasView` gesture methods used by AppKit. Do not duplicate mark mutation, inject accessibility events, or synthesize GUI input.
- Use a real `NSTextView` state sink. Keep `needsDisplay = true` in every continuation call, but do not include `draw(_:)`, the prototype grid, event dispatch, or WindowServer composition in timed scopes.
- Standard fixture: 12 pre-existing basic marks, then one freehand gesture with 240 continuation samples and 241 total points.
- Standard run: five discarded warmups, 30 measured trials, 20 fresh gestures per trial.
- Output raw machine-readable trial data plus median, p95, and median absolute deviation for whole-gesture and continuation-loop time.
- Add no dependency and no production Pointer target.
- This workspace has no Git repository. Do not invent commits; preserve checkpoints as source hashes, release binaries, raw benchmark JSON, and a Markdown result under `.codex/sdd/reports/mark-rendering-performance/`.

---

### Task 1: Add the real gesture seam and capture the unoptimized baseline

**Files:**

- Modify: `.scratch/pointer-mvp/prototypes/mark-rendering/Package.swift`
- Modify: `.scratch/pointer-mvp/prototypes/mark-rendering/Sources/MarkRenderingPrototype/main.swift`
- Create: `.scratch/pointer-mvp/prototypes/mark-rendering/Tests/MarkRenderingPrototypeTests/CanvasViewTests.swift`
- Create at runtime: `.codex/sdd/reports/mark-rendering-performance/MarkRenderingPrototype-before`
- Create at runtime: `.codex/sdd/reports/mark-rendering-performance/before-source.sha256`
- Create at runtime: `.codex/sdd/reports/mark-rendering-performance/before-initial.json`

**Interfaces:**

- Produces: `CanvasView.beginGesture(at:)`, `CanvasView.continueGesture(to:)`, and `CanvasView.endGesture()` as internal `@MainActor` methods.
- Produces: `DragBenchmarkConfiguration.standard` and `.smoke`.
- Produces: `DragPublicationBenchmark.run(configuration:label:) -> DragBenchmarkReport`.
- Produces: CLI `MarkRenderingPrototype --benchmark-drag --label <label> --format json` that exits without creating a window or entering `app.run()`.

- [ ] **Step 1: Register the XCTest target**

Add the test target to `Package.swift` without changing the executable product:

```swift
.testTarget(
    name: "MarkRenderingPrototypeTests",
    dependencies: ["MarkRenderingPrototype"]
)
```

This is test scaffolding only; it is required before the first failing test can compile.

- [ ] **Step 2: Write the failing shared-gesture API test**

Create `CanvasViewTests.swift` with the existing AppKit module and a test that names the break: if the shared methods omit a mutation, final geometry or undo will differ from the current event path.

```swift
import AppKit
import XCTest
@testable import MarkRenderingPrototype

@MainActor
final class CanvasViewTests: XCTestCase {
    func testSharedGestureMethodsPreserveFreehandGeometryAndUndo() {
        _ = NSApplication.shared
        let canvas = CanvasView(
            frame: NSRect(x: 0, y: 0, width: 800, height: 600)
        )
        canvas.tool = .freehand

        var states: [String] = []
        canvas.onStateChange = { states.append($0) }

        canvas.beginGesture(at: NSPoint(x: 10, y: 10))
        canvas.continueGesture(to: NSPoint(x: 20, y: 20))
        canvas.continueGesture(to: NSPoint(x: 40, y: 35))
        canvas.endGesture()

        XCTAssertEqual(canvas.marks.count, 1)
        XCTAssertTrue(states.last!.contains("marks: 1"))
        XCTAssertTrue(
            states.last!.contains("freehand 3 points, bounds [10, 10, 30×25]")
        )

        canvas.undo()
        XCTAssertEqual(canvas.marks.count, 0)
        XCTAssertTrue(states.last!.contains("marks: 0"))
        XCTAssertTrue(states.last!.contains("  (none)"))
    }
}
```

- [ ] **Step 3: Run the focused test and verify RED**

Run:

```sh
cd /Users/bruno/Dev/pointer/.scratch/pointer-mvp/prototypes/mark-rendering
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter CanvasViewTests.testSharedGestureMethodsPreserveFreehandGeometryAndUndo
```

Expected: compilation fails because `beginGesture(at:)`, `continueGesture(to:)`, and `endGesture()` do not exist. A failure for a different reason must be corrected before proceeding.

- [ ] **Step 4: Extract the point-based gesture methods without changing behavior**

In the pre-edit source, extract the statement sequence after coordinate conversion from `mouseDown` (currently lines 246–285) into `func beginGesture(at point: NSPoint)`. Extract the corresponding sequence from `mouseDragged` (currently lines 294–334) into `func continueGesture(to point: NSPoint)`. Extract the complete `mouseUp` sequence into `func endGesture()`. The extracted methods use their `point` parameter directly; the overrides retain the only event-to-view coordinate conversion.

Keep the `publishState()` call immediately before `needsDisplay = true` in `continueGesture(to:)` for the baseline. Do not reorder or otherwise change a switch branch, assignment, snapshot call, publication, or invalidation.

Reduce the AppKit overrides to coordinate conversion plus delegation:

```swift
override func mouseDown(with event: NSEvent) {
    beginGesture(at: convert(event.locationInWindow, from: nil))
}

override func mouseDragged(with event: NSEvent) {
    continueGesture(to: convert(event.locationInWindow, from: nil))
}

override func mouseUp(with event: NSEvent) {
    endGesture()
}
```

Do not alter mark mutation, selection/erase branches, undo snapshot timing, publication calls, or invalidation in this step.

- [ ] **Step 5: Run the focused test and verify GREEN**

Run the Step 3 command again. Expected: one test passes, with no unexpected warnings or failures.

- [ ] **Step 6: Write a failing smoke test for the benchmark runner**

Append this test before adding benchmark implementation:

```swift
func testDragBenchmarkSmokeRunExercisesRealGesturePath() throws {
    let report = DragPublicationBenchmark.run(
        configuration: .smoke,
        label: "test"
    )

    XCTAssertEqual(report.label, "test")
    XCTAssertEqual(report.fixtureID, "freehand-12-basic-240-drag")
    XCTAssertEqual(report.trials.count, 1)
    XCTAssertEqual(report.samplesPerGesture, 240)
    XCTAssertEqual(report.gesturesPerTrial, 1)
    XCTAssertFalse(report.renderTimed)
    XCTAssertFalse(report.gridTimed)
    XCTAssertFalse(report.eventDispatchTimed)
    XCTAssertTrue(report.finalStateValid)
    XCTAssertFalse(report.modelChecksum.isEmpty)
    XCTAssertFalse(report.inspectorChecksum.isEmpty)
}
```

Define `.smoke` to use zero warmups, one measured trial, one fresh gesture, and the same 240-sample fixture as the standard run. This keeps semantic coverage identical without adding a second fixture.

- [ ] **Step 7: Run the smoke test and verify RED**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter CanvasViewTests.testDragBenchmarkSmokeRunExercisesRealGesturePath
```

Expected: compilation fails because the benchmark configuration, runner, and report do not exist.

- [ ] **Step 8: Implement the minimal benchmark runner in the executable module**

Add internal `Codable` value types in `main.swift`:

```swift
struct DragBenchmarkConfiguration: Sendable {
    let warmupGestures: Int
    let trialCount: Int
    let gesturesPerTrial: Int
    let samplesPerGesture: Int

    static let standard = DragBenchmarkConfiguration(
        warmupGestures: 5,
        trialCount: 30,
        gesturesPerTrial: 20,
        samplesPerGesture: 240
    )
    static let smoke = DragBenchmarkConfiguration(
        warmupGestures: 0,
        trialCount: 1,
        gesturesPerTrial: 1,
        samplesPerGesture: 240
    )
}

struct DragBenchmarkTrial: Codable {
    let wholeGestureNanoseconds: Double
    let continuationLoopNanoseconds: Double
    let nanosecondsPerDragSample: Double
    let publicationsPerGesture: Int
}

struct DragBenchmarkReport: Codable {
    let label: String
    let fixtureID: String
    let buildConfiguration: String
    let warmupGestures: Int
    let trialCount: Int
    let gesturesPerTrial: Int
    let samplesPerGesture: Int
    let trials: [DragBenchmarkTrial]
    let wholeGestureMedianNanoseconds: Double
    let wholeGestureP95Nanoseconds: Double
    let wholeGestureMADNanoseconds: Double
    let continuationMedianNanoseconds: Double
    let continuationP95Nanoseconds: Double
    let continuationMADNanoseconds: Double
    let modelChecksum: String
    let inspectorChecksum: String
    let finalStateValid: Bool
    let renderTimed: Bool
    let gridTimed: Bool
    let eventDispatchTimed: Bool
}
```

Implement `@MainActor enum DragPublicationBenchmark` with `run(configuration:label:)`. For each fresh gesture, construct a `CanvasView`. Outside the timed scopes, create 12 basic marks with tools cycling through `.arrow`, `.rectangle`, and `.ellipse`; use a four-column grid whose gesture `index` starts at `(20 + 80 * (index % 4), 40 + 80 * (index / 4))` and ends 40 points right and 30 points up. Attach an `NSTextView` sink, reset the publication counter, and switch to `.freehand`.

Use start point `(20, 100)`. Drive continuation sample `i` from 1 through 240 at `(20 + 2 * i, 100 + 20 * (i % 2))`, producing 241 points and bounds `[20, 100, 480×20]`. For each measured gesture, record a timestamp immediately before `beginGesture`, another immediately before the continuation loop, a third immediately after the loop, and a fourth immediately after `endGesture`. The first-to-fourth interval is whole-gesture time; the second-to-third interval is continuation-loop time. Validate 13 final marks, 241 freehand points, the exact bounds above, and one undo restoring the 12-mark scene.

Convert `ContinuousClock.Duration` to nanoseconds as `seconds * 1_000_000_000 + attoseconds / 1_000_000_000`. Compute median by averaging the two middle sorted values for an even count, p95 by nearest rank (`ceil(0.95 * count) - 1`), and MAD as the median absolute deviation from the median.

Use 64-bit FNV-1a for checksums:

```swift
func fnv1a64(_ value: String) -> String {
    var hash: UInt64 = 14_695_981_039_346_656_037
    for byte in value.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return String(format: "%016llx", hash)
}
```

Build the semantic model checksum from tool, opacity, color components, line width, and geometry/point coordinates, deliberately excluding random mark UUIDs. Build the inspector checksum after normalizing only each six-character UUID prefix from mark lines; preserve every other character. Consume and emit both checksums after timing. Baseline and candidate checksums must match because their semantic final state and normalized inspector content are identical.

Do not time fixture creation, statistics, JSON encoding, or `draw(_:)`. Do not call `display()`, create a window, post events, or enter the application run loop.

- [ ] **Step 9: Add the headless CLI branch**

Before normal activation/window setup, parse only these benchmark arguments:

```text
--benchmark-drag --label <non-empty label> --format json
```

When present, initialize `NSApplication.shared`, run `.standard`, encode one `DragBenchmarkReport` with sorted JSON keys, write it to standard output, and exit successfully. Invalid/missing benchmark arguments must print a concise error to standard error and exit nonzero. Normal prototype launch behavior must remain unchanged.

- [ ] **Step 10: Verify the benchmark smoke test and full suite**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter CanvasViewTests.testDragBenchmarkSmokeRunExercisesRealGesturePath
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: both focused tests and the full suite pass with zero failures.

- [ ] **Step 11: Build and preserve the unoptimized release artifact**

Run:

```sh
mkdir -p /Users/bruno/Dev/pointer/.codex/sdd/reports/mark-rendering-performance
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build -c release --product MarkRenderingPrototype
cp .build/release/MarkRenderingPrototype \
  /Users/bruno/Dev/pointer/.codex/sdd/reports/mark-rendering-performance/MarkRenderingPrototype-before
shasum -a 256 Package.swift Sources/MarkRenderingPrototype/main.swift \
  > /Users/bruno/Dev/pointer/.codex/sdd/reports/mark-rendering-performance/before-source.sha256
/Users/bruno/Dev/pointer/.codex/sdd/reports/mark-rendering-performance/MarkRenderingPrototype-before \
  --benchmark-drag --label before-initial --format json \
  > /Users/bruno/Dev/pointer/.codex/sdd/reports/mark-rendering-performance/before-initial.json
```

Inspect the JSON. Required baseline evidence: `finalStateValid` is true, all three timed-scope flags are false, every trial reports 242 publications per gesture, and all 30 trial values are finite and positive. Do not proceed to Task 2 if the baseline does not satisfy these checks.

---

### Task 2: Remove per-sample publication and measure the candidate

**Files:**

- Modify: `.scratch/pointer-mvp/prototypes/mark-rendering/Tests/MarkRenderingPrototypeTests/CanvasViewTests.swift`
- Modify: `.scratch/pointer-mvp/prototypes/mark-rendering/Sources/MarkRenderingPrototype/main.swift`
- Modify: `.scratch/pointer-mvp/prototypes/mark-rendering/README.md`
- Create at runtime: `.codex/sdd/reports/mark-rendering-performance/MarkRenderingPrototype-after`
- Create at runtime: `.codex/sdd/reports/mark-rendering-performance/after-source.sha256`
- Create at runtime: four raw A-B-B-A JSON result files
- Create: `.codex/sdd/reports/mark-rendering-performance/results.md`

**Interfaces:**

- Changes: `continueGesture(to:)` no longer invokes `publishState()`.
- Preserves: `beginGesture(at:)` and `endGesture()` publication, every geometry mutation, `needsDisplay` invalidation, final inspector content, selection/erase/move/resize behavior, and one undo snapshot per gesture.

- [ ] **Step 1: Write the failing publication-boundary regression test**

Append this test:

```swift
func testFreehandGesturePublishesInspectorOnlyAtBoundaries() {
    _ = NSApplication.shared
    let canvas = CanvasView(
        frame: NSRect(x: 0, y: 0, width: 800, height: 600)
    )
    canvas.tool = .freehand

    var states: [String] = []
    canvas.onStateChange = { states.append($0) }

    canvas.beginGesture(at: NSPoint(x: 10, y: 10))
    let publicationsAfterBegin = states.count

    canvas.needsDisplay = false
    canvas.continueGesture(to: NSPoint(x: 20, y: 20))
    XCTAssertEqual(states.count, publicationsAfterBegin)
    XCTAssertTrue(canvas.needsDisplay)

    canvas.needsDisplay = false
    canvas.continueGesture(to: NSPoint(x: 40, y: 35))
    XCTAssertEqual(states.count, publicationsAfterBegin)
    XCTAssertTrue(canvas.needsDisplay)

    canvas.endGesture()

    XCTAssertEqual(states.count, publicationsAfterBegin + 1)
    XCTAssertEqual(canvas.marks.count, 1)
    XCTAssertTrue(states.last!.contains("marks: 1"))
    XCTAssertTrue(
        states.last!.contains("freehand 3 points, bounds [10, 10, 30×25]")
    )

    canvas.undo()
    XCTAssertEqual(canvas.marks.count, 0)
    XCTAssertTrue(states.last!.contains("marks: 0"))
}
```

This test catches reintroduction of inspector work into the continuation path while independently checking redraw and final model behavior.

- [ ] **Step 2: Run the focused test and verify RED**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter CanvasViewTests.testFreehandGesturePublishesInspectorOnlyAtBoundaries
```

Expected: the first continuation assertion fails because the baseline increments the publication count. Confirm it is an assertion failure caused by `publishState()` in `continueGesture(to:)`, not an AppKit setup error.

- [ ] **Step 3: Apply the single root-cause change**

Delete only the continuation-path publication immediately before invalidation:

```diff
-        publishState()
         needsDisplay = true
```

Do not add a timer, debounce, cache, background task, or new publication policy abstraction.

- [ ] **Step 4: Verify GREEN and run the full suite**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --filter CanvasViewTests.testFreehandGesturePublishesInspectorOnlyAtBoundaries
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: all tests pass with zero failures and no unexpected warnings.

- [ ] **Step 5: Document the intentional prototype behavior and benchmark command**

Update `README.md` so its inspector description states that diagnostic state is refreshed on committed actions and at drag boundaries, rather than every drag sample. Add the exact release benchmark command and state explicitly that it measures the gesture event-handler path only and excludes drawing, event dispatch, and compositing.

- [ ] **Step 6: Build and preserve the optimized release artifact**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build -c release --product MarkRenderingPrototype
cp .build/release/MarkRenderingPrototype \
  /Users/bruno/Dev/pointer/.codex/sdd/reports/mark-rendering-performance/MarkRenderingPrototype-after
shasum -a 256 Package.swift Sources/MarkRenderingPrototype/main.swift \
  > /Users/bruno/Dev/pointer/.codex/sdd/reports/mark-rendering-performance/after-source.sha256
```

- [ ] **Step 7: Run the preserved A-B-B-A comparison**

Use the two preserved release binaries, alternating order to expose drift:

```sh
report_dir=/Users/bruno/Dev/pointer/.codex/sdd/reports/mark-rendering-performance
"$report_dir/MarkRenderingPrototype-before" \
  --benchmark-drag --label before-a1 --format json > "$report_dir/before-a1.json"
"$report_dir/MarkRenderingPrototype-after" \
  --benchmark-drag --label after-b1 --format json > "$report_dir/after-b1.json"
"$report_dir/MarkRenderingPrototype-after" \
  --benchmark-drag --label after-b2 --format json > "$report_dir/after-b2.json"
"$report_dir/MarkRenderingPrototype-before" \
  --benchmark-drag --label before-a2 --format json > "$report_dir/before-a2.json"
```

Every run must report valid state/checksums, finite positive timings, baseline publication count 242, and candidate publication count 2. If the direction of the continuation median is not reproduced in both A/B pairs, stop and treat the hypothesis as unconfirmed.

- [ ] **Step 8: Write the measured result artifact**

Create `.codex/sdd/reports/mark-rendering-performance/results.md` with:

- host/date/toolchain and release-build conditions;
- exact fixture, warmups, trials, gestures, and timed/excluded scopes;
- each A-B-B-A run's whole-gesture and continuation median, p95, and MAD;
- paired median absolute and percentage deltas;
- publication count change from 242 to 2;
- confirmation that final model and inspector checksums/validity matched their expected values;
- the narrow causal conclusion supported by the measurements;
- explicit residual bottlenecks: rendering/path rebuilds, grid, WindowServer composition, array growth/remapping, eraser traversal, and undo retention.

Do not write projected numbers or characterize the result as production/UI frame-rate performance.

- [ ] **Step 9: Run fresh final verification**

Run after all source, test, and README changes:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift build -c release --product MarkRenderingPrototype
.build/release/MarkRenderingPrototype \
  --benchmark-drag --label final-verification --format json \
  > /Users/bruno/Dev/pointer/.codex/sdd/reports/mark-rendering-performance/final-verification.json
```

Read every command's full output and verify exit status zero, zero test failures, a valid final benchmark state, two publications per gesture, and positive finite timings.
