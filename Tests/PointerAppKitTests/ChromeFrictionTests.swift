import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class ChromeFrictionTests: XCTestCase {
    func testCandidatePersistentChromeDoesNotIncreaseAndOneDimensionDecreases() {
        let baseline = ChromeInventory(
            alwaysVisibleControls: 17,
            paletteRows: 2,
            visibleStatusElements: 1,
            focusStops: 17
        )
        let candidate = candidateInventory()
        XCTAssertEqual(
            candidate,
            ChromeInventory(
                alwaysVisibleControls: 15,
                paletteRows: 1,
                visibleStatusElements: 1,
                focusStops: 10
            )
        )

        XCTAssertLessThanOrEqual(
            candidate.alwaysVisibleControls,
            baseline.alwaysVisibleControls
        )
        XCTAssertLessThanOrEqual(candidate.paletteRows, baseline.paletteRows)
        XCTAssertLessThanOrEqual(
            candidate.visibleStatusElements,
            baseline.visibleStatusElements
        )
        XCTAssertLessThanOrEqual(candidate.focusStops, baseline.focusStops)
        XCTAssertTrue(
            candidate.alwaysVisibleControls < baseline.alwaysVisibleControls
                || candidate.paletteRows < baseline.paletteRows
                || candidate.visibleStatusElements < baseline.visibleStatusElements
                || candidate.focusStops < baseline.focusStops,
            "Candidate must reduce at least one persistent dimension: baseline=\(baseline), candidate=\(candidate)"
        )
    }

    func testFreshLaunchArrowDrawStandbyPathNeedsNoAdditionalClickOrKey() {
        let baseline = CommonPathInventory(requiredClicks: 1, requiredKeys: 1, semanticSteps: 3)
        let candidate = candidateCommonPathInventory()

        XCTAssertLessThanOrEqual(candidate.requiredClicks, baseline.requiredClicks)
        XCTAssertLessThanOrEqual(candidate.requiredKeys, baseline.requiredKeys)
        XCTAssertLessThanOrEqual(candidate.semanticSteps, baseline.semanticSteps)
        XCTAssertEqual(candidate, baseline)
    }
}

private struct ChromeInventory: Equatable, CustomStringConvertible {
    let alwaysVisibleControls: Int
    let paletteRows: Int
    let visibleStatusElements: Int
    let focusStops: Int

    var description: String {
        "controls=\(alwaysVisibleControls), rows=\(paletteRows), "
            + "status=\(visibleStatusElements), focus=\(focusStops)"
    }
}

private struct CommonPathInventory: Equatable {
    let requiredClicks: Int
    let requiredKeys: Int
    let semanticSteps: Int
}

private let comparisonWidth = 760.0

@MainActor
private func candidateInventory() -> ChromeInventory {
    let provider = ChromeFrictionScreenProvider()
    let coordinator = DisplayCoordinator(
        screenProvider: provider,
        overlayFactory: { ChromeFrictionOverlay(display: $0) }
    )
    let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
    _ = coordinator.synchronize()

    let controller = PaletteViewController(router: router)
    controller.loadViewIfNeeded()
    controller.refresh(session: router.session)
    controller.applyLayout(for: comparisonWidth)
    controller.view.layoutSubtreeIfNeeded()

    let controls = controller.controls
    let identifier: (NSControl) -> String? = {
        $0.identifier?.rawValue
    }
    let visibleControls = controls.filter {
        !$0.isHidden && identifier($0) != "palette.status"
    }
    let visibleStatusElements = controls.filter {
        !$0.isHidden && identifier($0) == "palette.status"
    }.count
    let focusStops = visibleControls.filter {
        $0.isEnabled && $0.acceptsFirstResponder
    }.count

    let visibleIDs = Set(visibleControls.compactMap(identifier))
    XCTAssertEqual(
        visibleIDs,
        Set([
            "palette.mode",
            "palette.tool.select",
            "palette.tool.arrow",
            "palette.tool.rectangle",
            "palette.tool.ellipse",
            "palette.tool.pen",
            "palette.tools.overflow",
            "palette.emoji",
            "palette.style.color",
            "palette.style.stroke-width",
            "palette.style.opacity",
            "palette.spotlight.radius",
            "palette.spotlight.dimness",
            "palette.undo",
            "palette.clear",
        ])
    )
    let arrow = controls.first { identifier($0) == "palette.tool.arrow" }
    XCTAssertTrue(arrow?.isAccessibilityElement() == true)
    XCTAssertFalse((arrow?.accessibilityLabel() ?? "").isEmpty)
    XCTAssertTrue(arrow?.acceptsFirstResponder == true)
    XCTAssertTrue(controls.first { identifier($0) == "palette.delete" }?.isHidden == true)
    XCTAssertEqual(visibleStatusElements, 1)

    return ChromeInventory(
        alwaysVisibleControls: visibleControls.count,
        paletteRows: controller.layoutPlan.rows.count,
        visibleStatusElements: visibleStatusElements,
        focusStops: focusStops
    )
}

@MainActor
private func candidateCommonPathInventory() -> CommonPathInventory {
    let provider = ChromeFrictionScreenProvider()
    let coordinator = DisplayCoordinator(
        screenProvider: provider,
        overlayFactory: { ChromeFrictionOverlay(display: $0) }
    )
    let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
    _ = coordinator.synchronize()

    let controller = PaletteViewController(router: router)
    controller.loadViewIfNeeded()
    controller.refresh(session: router.session)
    controller.applyLayout(for: comparisonWidth)
    controller.view.layoutSubtreeIfNeeded()
    let arrow = controller.control(identifier: "palette.tool.arrow") as! NSButton

    var events: [CommonPathEvent] = []
    XCTAssertEqual(router.session.mode, .standby)
    XCTAssertEqual(router.session.toolState.tool, .arrow)
    XCTAssertFalse(arrow.isHidden)
    events.append(.semantic)
    events.append(.click)
    arrow.performClick(nil)
    XCTAssertEqual(router.session.mode, .annotation)

    var drawingSession = router.session
    _ = drawingSession.beginGesture(
        tool: .arrow,
        at: NormalizedPoint(x: 0.2, y: 0.2),
        on: ChromeFrictionScreenProvider.display.uuid
    )
    _ = drawingSession.advanceGesture(to: NormalizedPoint(x: 0.8, y: 0.8))
    let commit = drawingSession.commitGesture()
    XCTAssertTrue(commit.didMutate)
    events.append(.semantic)
    XCTAssertTrue(router.routeLocalKeyEvent(keyCode: 53))
    XCTAssertEqual(router.session.mode, .standby)
    events.append(.key)
    events.append(.semantic)

    return CommonPathInventory(
        requiredClicks: events.filter { $0 == .click }.count,
        requiredKeys: events.filter { $0 == .key }.count,
        semanticSteps: events.filter { $0 == .semantic }.count
    )
}

private enum CommonPathEvent: Equatable {
    case click
    case key
    case semantic
}

@MainActor
private final class ChromeFrictionScreenProvider: ScreenProviding {
    static let display = DisplayDescriptor(
        uuid: DisplayUUID(rawValue: "chrome-friction-display"),
        frame: DisplayFrame(x: 0, y: 0, width: 1_920, height: 1_080),
        visibleFrame: DisplayFrame(x: 0, y: 24, width: 1_920, height: 1_056),
        scaleFactor: 2
    )

    func currentDisplays() -> [DisplayDescriptor] { [Self.display] }
    func pointerDisplay() -> DisplayUUID? { Self.display.uuid }
}

@MainActor
private final class ChromeFrictionOverlay: OverlayPresenting {
    var display: DisplayDescriptor

    init(display: DisplayDescriptor) {
        self.display = display
    }

    func update(display: DisplayDescriptor) {
        self.display = display
    }

    func update(session: PointerSession) {}
    func setMode(_ mode: PointerMode) {}
    func close() {}
}
