import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class ChromeFrictionTests: XCTestCase {
    func testCandidatePersistentChromeDoesNotIncreaseAcrossRealDisplayWidths() {
        let baselineStandard = BaselineChromeEvidence.standard
        let baselineClamped = BaselineChromeEvidence.clamped
        let standard = candidateInventory(for: ChromeInventoryScreenProvider.standardDisplay)
        let clamped = candidateInventory(for: ChromeInventoryScreenProvider.clampedDisplay)

        XCTAssertEqual(standard, ChromeInventory(
            contentWidth: 822,
            alwaysVisibleControls: 17,
            actualToolRows: 1,
            visibleStatusElements: 1,
            focusStops: 12
        ))
        XCTAssertEqual(clamped, ChromeInventory(
            contentWidth: 760,
            alwaysVisibleControls: 15,
            actualToolRows: 1,
            visibleStatusElements: 1,
            focusStops: 10
        ))

        for (label, candidate, expectedBaseline) in [
            ("standard", standard, baselineStandard),
            ("clamped", clamped, baselineClamped),
        ] {
            XCTAssertLessThanOrEqual(
                candidate.alwaysVisibleControls,
                expectedBaseline.alwaysVisibleControls,
                label
            )
            XCTAssertLessThanOrEqual(candidate.actualToolRows, expectedBaseline.actualToolRows, label)
            XCTAssertLessThanOrEqual(
                candidate.visibleStatusElements,
                expectedBaseline.visibleStatusElements,
                label
            )
            XCTAssertLessThanOrEqual(candidate.focusStops, expectedBaseline.focusStops, label)
            let reductionMessage = "Candidate must reduce at least one persistent dimension at "
                + "\(label) width: baseline=\(expectedBaseline), candidate=\(candidate)"
            XCTAssertTrue(
                candidate.alwaysVisibleControls < expectedBaseline.alwaysVisibleControls
                    || candidate.actualToolRows < expectedBaseline.actualToolRows
                    || candidate.visibleStatusElements < expectedBaseline.visibleStatusElements
                    || candidate.focusStops < expectedBaseline.focusStops,
                reductionMessage
            )
        }
    }

    func testFreshLaunchArrowDrawStandbyPathNeedsNoAdditionalClickOrKey() throws {
        let baseline = CommonPathInventory(requiredClicks: 1, requiredKeys: 1, semanticSteps: 3)
        let candidate = try candidateCommonPathInventory()

        XCTAssertLessThanOrEqual(candidate.requiredClicks, baseline.requiredClicks)
        XCTAssertLessThanOrEqual(candidate.requiredKeys, baseline.requiredKeys)
        XCTAssertLessThanOrEqual(candidate.semanticSteps, baseline.semanticSteps)
        XCTAssertEqual(candidate, baseline)
    }
}

private struct ChromeInventory: Equatable, CustomStringConvertible {
    let contentWidth: Int
    let alwaysVisibleControls: Int
    let actualToolRows: Int
    let visibleStatusElements: Int
    let focusStops: Int

    var description: String {
        "width=\(contentWidth), controls=\(alwaysVisibleControls), rows=\(actualToolRows), "
            + "status=\(visibleStatusElements), focus=\(focusStops)"
    }
}

private enum BaselineChromeEvidence {
    static let commit = "caa2bd0212c617ba6d4d599ede55be3624e525f4"
    static let palettePanelSourceSHA256 = "94d350cbc58e3f9e909c87a4888253b89ba078b4909c738f1819c4984d8b1163"
    static let paletteViewControllerSourceSHA256 = "faaf563522dfe4c4b658bc4efdb1001d79b240c478a8e8c113c9734171e27c52"
    static let paletteLayoutSourceSHA256 = "06d061e3b54e150ded44efb082c3a6f3e1faa43d77430f1f68d8092200bb20c0"

    static let standard = ChromeInventory(
        contentWidth: 760,
        alwaysVisibleControls: 17,
        actualToolRows: 1,
        visibleStatusElements: 1,
        focusStops: 17
    )
    static let clamped = ChromeInventory(
        contentWidth: 760,
        alwaysVisibleControls: 17,
        actualToolRows: 1,
        visibleStatusElements: 1,
        focusStops: 17
    )
}

private struct CommonPathInventory: Equatable {
    let requiredClicks: Int
    let requiredKeys: Int
    let semanticSteps: Int
}

private let comparisonWidth = 760.0

@MainActor
private func candidateInventory(for display: DisplayDescriptor) -> ChromeInventory {
    let provider = ChromeInventoryScreenProvider(display: display)
    let coordinator = DisplayCoordinator(
        screenProvider: provider,
        overlayFactory: { ChromeFrictionOverlay(display: $0) }
    )
    let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
    _ = coordinator.synchronize()

    let palette = PalettePanel(
        router: router,
        guidePlacementProvider: GuidePlacementProvider()
    )
    defer { palette.close() }
    guard case .shown = palette.show(on: display) else {
        XCTFail("Expected palette to show for display visible width \(display.visibleFrame.width)")
        return ChromeInventory(
            contentWidth: -1,
            alwaysVisibleControls: -1,
            actualToolRows: -1,
            visibleStatusElements: -1,
            focusStops: -1
        )
    }

    let controller = palette.paletteViewController
    palette.refresh(session: router.session)
    palette.window.contentView?.layoutSubtreeIfNeeded()
    let expectedContentWidth = display.visibleFrame.width >= PaletteLayout.minimumAllToolsWidth
        ? Int(PaletteLayout.minimumAllToolsWidth.rounded())
        : Int((display.visibleFrame.width - 32).rounded())
    XCTAssertEqual(palette.frame.width, CGFloat(expectedContentWidth), accuracy: 1)

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
    let expectedVisibleIDs: Set<String> = expectedContentWidth == 822
        ? Set([
            "palette.mode",
            "palette.tool.select",
            "palette.tool.arrow",
            "palette.tool.rectangle",
            "palette.tool.ellipse",
            "palette.tool.pen",
            "palette.tool.eraser",
            "palette.tool.emoji",
            "palette.tool.spotlight",
            "palette.emoji",
            "palette.style.color",
            "palette.style.stroke-width",
            "palette.style.opacity",
            "palette.spotlight.radius",
            "palette.spotlight.dimness",
            "palette.undo",
            "palette.clear",
        ])
        : Set([
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
    XCTAssertEqual(visibleIDs, expectedVisibleIDs)
    let arrow = controls.first { identifier($0) == "palette.tool.arrow" }
    XCTAssertTrue(arrow?.isAccessibilityElement() == true)
    XCTAssertFalse((arrow?.accessibilityLabel() ?? "").isEmpty)
    XCTAssertTrue(arrow?.acceptsFirstResponder == true)
    XCTAssertTrue(controls.first { identifier($0) == "palette.delete" }?.isHidden == true)
    XCTAssertEqual(visibleStatusElements, 1)

    let actualToolRows = renderedToolRows(in: controller)
    assertCandidateTextTaxonomy(in: controller, controls: controls)

    return ChromeInventory(
        contentWidth: expectedContentWidth,
        alwaysVisibleControls: visibleControls.count,
        actualToolRows: actualToolRows,
        visibleStatusElements: visibleStatusElements,
        focusStops: focusStops
    )
}

@MainActor
private func renderedToolRows(in controller: PaletteViewController) -> Int {
    let requiredIDs = Set([
        "palette.mode",
        "palette.tool.select",
        "palette.tool.arrow",
        "palette.tool.rectangle",
        "palette.tool.ellipse",
        "palette.tool.pen",
        "palette.tool.eraser",
        "palette.tool.emoji",
        "palette.tool.spotlight",
        "palette.tools.overflow",
    ])
    let firstRow = allDescendants(of: controller.view)
        .compactMap { $0 as? NSStackView }
        .first { stack in
            let arrangedIDs = Set(stack.arrangedSubviews.compactMap { view in
                (view as? NSControl)?.identifier?.rawValue
            })
            return arrangedIDs.isSuperset(of: requiredIDs)
        }
    guard let firstRow else {
        XCTFail("Expected a rendered first-row stack containing every tool control")
        return 0
    }

    let centers = firstRow.arrangedSubviews
        .filter { !$0.isHidden }
        .map { $0.convert($0.bounds, to: controller.view).midY }
        .sorted()
    guard !centers.isEmpty else {
        XCTFail("Expected visible controls in the rendered first-row stack")
        return 0
    }
    var rowCenters: [CGFloat] = []
    for center in centers {
        if let previous = rowCenters.last, abs(center - previous) <= 1 {
            continue
        }
        rowCenters.append(center)
    }
    return rowCenters.count
}

@MainActor
private func assertCandidateTextTaxonomy(
    in controller: PaletteViewController,
    controls: [NSControl]
) {
    let textFields = allDescendants(of: controller.view)
        .compactMap { $0 as? NSTextField }
        .filter { !$0.isHidden && !isButtonTitle($0) }
    let statusFields = textFields.filter {
        $0.identifier?.rawValue == "palette.status"
    }
    let valueCaptions = textFields.filter {
        ["4", "100%", "15%", "50%"].contains($0.stringValue)
    }
    let contextLabels = textFields.filter {
        ["Color", "Emoji", "Stroke", "Opacity", "Radius", "Dimness"].contains($0.stringValue)
    }

    XCTAssertEqual(statusFields.count, 1)
    XCTAssertEqual(Set(statusFields.compactMap { $0.identifier?.rawValue }), ["palette.status"])
    XCTAssertEqual(valueCaptions.map(\.stringValue).sorted(), ["100%", "15%", "4", "50%"])
    XCTAssertEqual(contextLabels.map(\.stringValue).sorted(), ["Color", "Dimness", "Emoji", "Opacity", "Radius", "Stroke"])
    let classifiedFields = Set(
        (statusFields + valueCaptions + contextLabels).map(ObjectIdentifier.init)
    )
    XCTAssertEqual(Set(textFields.map(ObjectIdentifier.init)), classifiedFields)

    let focusControls = controls.filter {
        $0.isEnabled && !$0.isHidden && $0.acceptsFirstResponder
    }
    for field in valueCaptions + contextLabels {
        XCTAssertFalse(controls.contains { $0 === field }, "Text caption must not be a palette control")
        XCTAssertFalse(field.acceptsFirstResponder, "Text caption must not be a focus stop")
        XCTAssertFalse(focusControls.contains { $0 === field }, "Text caption must not enter the focus loop")
        XCTAssertNotEqual(field.identifier?.rawValue, "palette.status")
    }
}

private func isButtonTitle(_ field: NSTextField) -> Bool {
    var ancestor = field.superview
    while let view = ancestor {
        if view is NSButton || view is NSPopUpButton {
            return true
        }
        ancestor = view.superview
    }
    return false
}

private func allDescendants(of view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + allDescendants(of: $0) }
}

@MainActor
private func candidateCommonPathInventory() throws -> CommonPathInventory {
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

    let overlay = try XCTUnwrap(
        coordinator.overlays[ChromeFrictionScreenProvider.display.uuid]
            as? ChromeFrictionOverlay
    )
    overlay.canvasView.beginGesture(at: NSPoint(x: 384, y: 216))
    overlay.canvasView.continueGesture(to: NSPoint(x: 1_536, y: 864))
    overlay.canvasView.endGesture()
    let committedMarks = router.session.canvas(
        for: ChromeFrictionScreenProvider.display.uuid
    ).marks
    XCTAssertEqual(committedMarks.count, 1)
    let committedMark = try XCTUnwrap(committedMarks.first)
    guard case let .arrow(start, end) = committedMark.geometry else {
        XCTFail("The CanvasView gesture must commit an arrow")
        throw ChromeFrictionError.expectedArrow
    }
    XCTAssertEqual(start.x, 0.2, accuracy: 0.000_001)
    XCTAssertEqual(start.y, 0.2, accuracy: 0.000_001)
    XCTAssertEqual(end.x, 0.8, accuracy: 0.000_001)
    XCTAssertEqual(end.y, 0.8, accuracy: 0.000_001)
    events.append(.semantic)
    XCTAssertTrue(router.routeLocalKeyEvent(keyCode: 53))
    XCTAssertEqual(router.session.mode, .standby)
    XCTAssertEqual(
        router.session.canvas(for: ChromeFrictionScreenProvider.display.uuid).marks.count,
        1
    )
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

private enum ChromeFrictionError: Error {
    case expectedArrow
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
private final class ChromeInventoryScreenProvider: ScreenProviding {
    static let standardDisplay = DisplayDescriptor(
        uuid: DisplayUUID(rawValue: "chrome-inventory-standard"),
        frame: DisplayFrame(x: 0, y: 0, width: 1_920, height: 1_080),
        visibleFrame: DisplayFrame(x: 0, y: 24, width: 1_920, height: 1_056),
        scaleFactor: 2
    )
    static let clampedDisplay = DisplayDescriptor(
        uuid: DisplayUUID(rawValue: "chrome-inventory-clamped"),
        frame: DisplayFrame(x: 0, y: 0, width: 792, height: 1_080),
        visibleFrame: DisplayFrame(x: 0, y: 24, width: 792, height: 1_056),
        scaleFactor: 2
    )

    let display: DisplayDescriptor

    init(display: DisplayDescriptor) {
        self.display = display
    }

    func currentDisplays() -> [DisplayDescriptor] { [display] }
    func pointerDisplay() -> DisplayUUID? { display.uuid }
}

@MainActor
private final class ChromeFrictionOverlay: OverlayPresenting {
    var display: DisplayDescriptor
    let canvasView: CanvasView

    init(display: DisplayDescriptor) {
        self.display = display
        canvasView = CanvasView(
            frame: NSRect(origin: .zero, size: display.frame.cgRect.size),
            display: display.uuid
        )
    }

    func update(display: DisplayDescriptor) {
        self.display = display
        canvasView.setFrameSize(display.frame.cgRect.size)
    }

    func update(session: PointerSession) {
        canvasView.update(session: session)
        canvasView.tool = session.toolState.tool
    }

    func setMode(_ mode: PointerMode) {
        guard canvasView.session.mode != mode else { return }
        var session = canvasView.session
        session.apply(.setMode(mode))
        canvasView.update(session: session)
    }

    func cancelActiveGesture() {
        canvasView.cancelGesture()
    }

    func setEventHandlers(
        onSessionUpdate: @escaping (PointerSession) -> Void,
        onBoundaryEvent: @escaping (GestureBoundaryEvent) -> Void
    ) {
        canvasView.onSessionUpdate = onSessionUpdate
        canvasView.onBoundaryEvent = onBoundaryEvent
    }

    func close() {}
}
