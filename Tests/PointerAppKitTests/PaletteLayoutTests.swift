import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class PaletteLayoutTests: XCTestCase {
    func testNarrowLayoutKeepsAllEightToolsReachableThroughOverflow() {
        let plan = PaletteLayout.plan(availableWidth: 220)

        let visibleTools = Set(plan.rows.flatMap { row in
            row.compactMap { item -> PointerTool? in
                guard case let .tool(tool) = item else { return nil }
                return tool
            }
        })
        let reachableTools = visibleTools.union(plan.overflowTools)

        XCTAssertTrue(plan.usesOverflow)
        XCTAssertEqual(reachableTools, Set(PointerTool.allCases))
        XCTAssertFalse(plan.overflowTools.isEmpty)
    }

    func testNarrowPaletteKeepsModeAndReachableToolsWithNamedOverflow() throws {
        let plan = PaletteLayout.plan(availableWidth: 420)

        XCTAssertTrue(plan.usesOverflow)
        XCTAssertFalse(plan.overflowTools.isEmpty)
        XCTAssertTrue(plan.rows.flatMap { $0 }.contains(.overflow))

        let visibleTools = plan.rows.flatMap { row in
            row.compactMap { item -> PointerTool? in
                guard case let .tool(tool) = item else { return nil }
                return tool
            }
        }
        XCTAssertFalse(visibleTools.isEmpty)
        XCTAssertEqual(Set(visibleTools).union(plan.overflowTools), Set(PointerTool.allCases))
        XCTAssertEqual(
            visibleTools.count + plan.overflowTools.count,
            PointerTool.allCases.count
        )

        let controller = PaletteViewController(router: makeRouter())
        controller.loadViewIfNeeded()
        controller.applyLayout(for: 420)
        let overflow = try XCTUnwrap(
            controller.control(identifier: "palette.tools.overflow") as? NSPopUpButton
        )
        XCTAssertEqual(overflow.title, "More Tools")
        let overflowValue = try XCTUnwrap(overflow.accessibilityValue() as? String)
        XCTAssertTrue(overflowValue.contains("Eraser"))
        XCTAssertTrue(overflowValue.contains("Emoji"))
        XCTAssertTrue(overflowValue.contains("Spotlight"))
    }

    func testPathologicalWidthsNeverDuplicateOrDropTools() {
        for width in [0.0, -1.0, .nan, .infinity, -.infinity] {
            let plan = PaletteLayout.plan(
                availableWidth: width,
                toolWidth: .nan,
                spacing: .infinity
            )
            let visibleTools = plan.rows.flatMap { row in
                row.compactMap { item -> PointerTool? in
                    guard case let .tool(tool) = item else { return nil }
                    return tool
                }
            }
            let reachable = visibleTools + plan.overflowTools
            XCTAssertEqual(Set(reachable), Set(PointerTool.allCases), "width \(width)")
            XCTAssertEqual(reachable.count, PointerTool.allCases.count, "width \(width)")
            XCTAssertTrue(reachable.allSatisfy { PointerTool.allCases.contains($0) })
        }
    }

    func testWideLayoutUsesOneToolRowWithNamedOverflow() {
        let plan = PaletteLayout.plan(availableWidth: 760)

        XCTAssertEqual(plan.rows.count, 1)
        XCTAssertTrue(plan.usesOverflow)
        XCTAssertTrue(plan.rows.flatMap { $0 }.contains(.overflow))
        XCTAssertEqual(
            Set(plan.rows.flatMap { $0 }.compactMap { item -> PointerTool? in
                guard case let .tool(tool) = item else { return nil }
                return tool
            }).union(plan.overflowTools),
            Set(PointerTool.allCases)
        )
    }

    func testUltraWideLayoutUsesOneToolRowWithoutOverflow() {
        let plan = PaletteLayout.plan(availableWidth: 1_020)

        XCTAssertEqual(plan.rows.count, 1)
        XCTAssertFalse(plan.usesOverflow)
        XCTAssertEqual(
            Set(plan.rows.flatMap { $0 }.compactMap { item -> PointerTool? in
                guard case let .tool(tool) = item else { return nil }
                return tool
            }),
            Set(PointerTool.allCases)
        )
    }

    @MainActor
    func testRenderedPaletteKeepsToolAndActionHitTargetsAtSupportedWidths() throws {
        for (displayWidth, expectedContentWidth) in [
            (452.0, 420.0),
            (792.0, 760.0),
            (PaletteLayout.minimumAllToolsWidth + 32, PaletteLayout.minimumAllToolsWidth),
        ] {
            let display = DisplayDescriptor(
                uuid: DisplayUUID(rawValue: "display-\(Int(displayWidth))"),
                frame: DisplayFrame(x: 0, y: 0, width: displayWidth, height: 1_080),
                visibleFrame: DisplayFrame(x: 0, y: 24, width: displayWidth, height: 1_056),
                scaleFactor: 2
            )
            let provider = PaletteTestScreenProvider(displays: [display])
            let coordinator = DisplayCoordinator(
                screenProvider: provider,
                overlayFactory: { PaletteTestOverlay(display: $0) }
            )
            let router = CommandRouter(coordinator: coordinator, screenProvider: provider)
            _ = coordinator.synchronize()
            let mark = Mark(
                geometry: .arrow(
                    start: NormalizedPoint(x: 0.2, y: 0.2),
                    end: NormalizedPoint(x: 0.8, y: 0.8)
                ),
                style: .default
            )
            coordinator.apply(.append(mark, to: display.uuid))
            var selectedSession = coordinator.session
            selectedSession.apply(.setMode(.annotation))
            selectedSession.apply(.setTool(.select))
            _ = selectedSession.beginGesture(
                tool: .select,
                at: NormalizedPoint(x: 0.5, y: 0.5),
                on: display.uuid
            )
            _ = selectedSession.commitGesture()
            let palette = PalettePanel(
                router: router,
                guidePlacementProvider: GuidePlacementProvider()
            )
            defer { palette.close() }

            guard case .shown = palette.show(on: display) else {
                return XCTFail("Expected supported width \(displayWidth)")
            }
            palette.refresh(session: selectedSession)
            palette.window.contentView?.layoutSubtreeIfNeeded()
            let controller = palette.paletteViewController
            XCTAssertEqual(palette.frame.width, expectedContentWidth, accuracy: 1)

            let planTools = Set(controller.layoutPlan.rows.flatMap { row in
                row.compactMap { item -> PointerTool? in
                    guard case let .tool(tool) = item else { return nil }
                    return tool
                }
            })
            let visibleToolIDs = Set(controller.controls.compactMap { control -> String? in
                guard let identifier = control.identifier?.rawValue,
                      identifier.hasPrefix("palette.tool."),
                      !control.isHidden
                else { return nil }
                return identifier
            })
            XCTAssertEqual(
                visibleToolIDs,
                Set(planTools.map { "palette.tool.\(identifier(for: $0))" })
            )
            let hiddenToolIDs = Set(controller.controls.compactMap { control -> String? in
                guard let identifier = control.identifier?.rawValue,
                      identifier.hasPrefix("palette.tool."),
                      control.isHidden
                else { return nil }
                return identifier
            })
            XCTAssertEqual(
                hiddenToolIDs,
                Set(controller.layoutPlan.overflowTools.map { "palette.tool.\(identifier(for: $0))" })
            )

            let firstRowControls = controller.controls.filter { control in
                guard let identifier = control.identifier?.rawValue else { return false }
                return identifier == "palette.mode"
                    || (identifier == "palette.tools.overflow" && !control.isHidden)
                    || (identifier.hasPrefix("palette.tool.") && !control.isHidden)
            }
            let firstRowRects = firstRowControls.map { control in
                control.convert(control.bounds, to: controller.view)
            }
            for (control, rect) in zip(firstRowControls, firstRowRects) {
                if let button = control as? NSButton {
                    XCTAssertGreaterThanOrEqual(
                        rect.width,
                        max(44, button.intrinsicContentSize.width),
                        button.identifier?.rawValue ?? "first-row width"
                    )
                    XCTAssertFalse(button.title.isEmpty)
                } else {
                    XCTAssertGreaterThanOrEqual(rect.width, 44)
                }
                XCTAssertGreaterThanOrEqual(rect.height, 28)
            }
            for index in firstRowRects.indices {
                for otherIndex in firstRowRects.indices where otherIndex > index {
                    XCTAssertFalse(firstRowRects[index].intersects(firstRowRects[otherIndex]))
                }
            }

            for identifier in [
                "palette.style.stroke-width",
                "palette.style.opacity",
                "palette.spotlight.radius",
                "palette.spotlight.dimness",
            ] {
                let slider = try XCTUnwrap(controller.control(identifier: identifier) as? NSSlider)
                XCTAssertGreaterThanOrEqual(slider.frame.width, 120, identifier)
                XCTAssertGreaterThan(slider.frame.height, 0, identifier)
            }
            for identifier in ["palette.undo", "palette.clear"] {
                let button = try XCTUnwrap(controller.control(identifier: identifier) as? NSButton)
                XCTAssertFalse(button.isHidden, identifier)
                XCTAssertTrue(button.isEnabled, identifier)
                XCTAssertGreaterThanOrEqual(button.frame.width, 44, identifier)
                XCTAssertGreaterThanOrEqual(button.frame.height, 28, identifier)
                XCTAssertFalse(hasAncestor(button, of: NSScrollView.self), identifier)
            }
            let delete = try XCTUnwrap(controller.control(identifier: "palette.delete") as? NSButton)
            XCTAssertFalse(delete.isHidden)
            XCTAssertTrue(delete.isEnabled)
            XCTAssertGreaterThanOrEqual(delete.frame.width, 44)
            XCTAssertGreaterThanOrEqual(delete.frame.height, 28)
            XCTAssertFalse(hasAncestor(delete, of: NSScrollView.self))
        }
    }

    func testEveryPaletteControlHasLabelHelpIdentifierAndEnabledState() {
        let router = makeRouter()
        let viewController = PaletteViewController(router: router)
        viewController.loadViewIfNeeded()

        XCTAssertFalse(viewController.controls.isEmpty)
        for control in viewController.controls {
            XCTAssertTrue(control.isAccessibilityElement())
            XCTAssertFalse((control.accessibilityLabel() ?? "").isEmpty)
            XCTAssertFalse((control.accessibilityHelp() ?? "").isEmpty)
            XCTAssertFalse(control.identifier?.rawValue.isEmpty ?? true)
            _ = control.isEnabled
        }
    }

    func testPaletteControlsHaveStableNamesHelpValuesAndFocusOrder() {
        let controller = PaletteViewController(router: makeRouter())
        controller.loadViewIfNeeded()
        let controls = controller.controls

        XCTAssertEqual(Set(controls.compactMap { $0.identifier?.rawValue }).count, controls.count)
        XCTAssertTrue(controls.allSatisfy {
            $0.isAccessibilityElement() && !($0.accessibilityLabel() ?? "").isEmpty
        })
        XCTAssertTrue(controls.allSatisfy { $0.focusRingType != .none })
        XCTAssertEqual(controls.first?.identifier?.rawValue, "palette.mode")
        XCTAssertEqual(controller.control(identifier: "palette.status").identifier?.rawValue, "palette.status")
    }

    func testToolControlsUseCanonicalTitlesAndNativeSymbols() throws {
        let controller = PaletteViewController(router: makeRouter())
        controller.loadViewIfNeeded()

        let expected: [String: String] = [
            "select": "Select",
            "arrow": "Arrow",
            "rectangle": "Rectangle",
            "ellipse": "Ellipse",
            "pen": "Pen",
            "eraser": "Eraser",
            "emoji": "Emoji",
            "spotlight": "Spotlight",
        ]
        for (identifier, title) in expected {
            let button = try XCTUnwrap(
                controller.control(identifier: "palette.tool.\(identifier)") as? NSButton,
                identifier
            )
            XCTAssertEqual(button.title, title, identifier)
            XCTAssertEqual(button.accessibilityLabel(), title, identifier)
            XCTAssertNotNil(button.image, identifier)
        }
    }

    func testUndoAndClearAreMomentaryCommandButtons() {
        let viewController = PaletteViewController(router: makeRouter())
        viewController.loadViewIfNeeded()

        for identifier in ["palette.undo", "palette.clear"] {
            let button = viewController.controls
                .compactMap { $0 as? NSButton }
                .first { $0.identifier?.rawValue == identifier }
            XCTAssertNotNil(button, identifier)
            XCTAssertEqual(viewController.buttonType(for: identifier), .momentaryPushIn, identifier)
            XCTAssertEqual(button?.accessibilityLabel(), identifier == "palette.undo"
                ? "Undo last pointer-display change"
                : "Clear pointer display", identifier)
        }
    }

    @MainActor
    func testPaletteRecomputesLayoutAfterNarrowContentWidth() {
        let router = makeRouter()
        let placementProvider = GuidePlacementProvider()
        let palette = PalettePanel(
            router: router,
            guidePlacementProvider: placementProvider
        )
        XCTAssertTrue(palette.guidePlacementProvider === placementProvider)
        let descriptor = DisplayDescriptor(
            uuid: DisplayUUID(rawValue: "display-a"),
            frame: DisplayFrame(x: 0, y: 0, width: 220, height: 600),
            visibleFrame: DisplayFrame(x: 0, y: 24, width: 220, height: 576),
            scaleFactor: 2
        )

        palette.show(on: descriptor)
        palette.window.contentView?.layoutSubtreeIfNeeded()

        let plan = palette.paletteViewController.layoutPlan
        let visibleTools = plan.rows.flatMap { $0 }.compactMap { item -> PointerTool? in
            guard case let .tool(tool) = item else { return nil }
            return tool
        }
        XCTAssertTrue(plan.usesOverflow)
        XCTAssertEqual(Set(visibleTools).union(plan.overflowTools), Set(PointerTool.allCases))
    }

    func testPaletteWindowStaysAboveInteractiveOverlayAfterBothAreShown() {
        let descriptor = DisplayDescriptor(
            uuid: DisplayUUID(rawValue: "display-a"),
            frame: DisplayFrame(x: 0, y: 0, width: 1_920, height: 1_080),
            visibleFrame: DisplayFrame(x: 0, y: 24, width: 1_920, height: 1_056),
            scaleFactor: 2
        )
        let overlay = OverlayPanel(descriptor: descriptor)
        let placementProvider = GuidePlacementProvider()
        let palette = PalettePanel(
            router: makeRouter(),
            guidePlacementProvider: placementProvider
        )
        XCTAssertTrue(palette.guidePlacementProvider === placementProvider)
        defer {
            palette.close()
            overlay.close()
        }

        overlay.show()
        palette.show(on: descriptor)

        XCTAssertGreaterThan(palette.level.rawValue, overlay.level.rawValue)
    }

    private func makeRouter() -> CommandRouter {
        let uuid = DisplayUUID(rawValue: "display-a")
        let descriptor = DisplayDescriptor(
            uuid: uuid,
            frame: DisplayFrame(x: 0, y: 0, width: 1_920, height: 1_080),
            visibleFrame: DisplayFrame(x: 0, y: 24, width: 1_920, height: 1_056),
            scaleFactor: 2
        )
        let provider = PaletteTestScreenProvider(displays: [descriptor])
        let coordinator = DisplayCoordinator(
            screenProvider: provider,
            overlayFactory: { PaletteTestOverlay(display: $0) }
        )
        return CommandRouter(coordinator: coordinator, screenProvider: provider)
    }

    private func identifier(for tool: PointerTool) -> String {
        switch tool {
        case .select: return "select"
        case .arrow: return "arrow"
        case .rectangle: return "rectangle"
        case .ellipse: return "ellipse"
        case .pen: return "pen"
        case .eraser: return "eraser"
        case .emoji: return "emoji"
        case .spotlight: return "spotlight"
        }
    }

    private func hasAncestor(_ view: NSView, of type: NSView.Type) -> Bool {
        var ancestor = view.superview
        while let current = ancestor {
            if current.isKind(of: type) { return true }
            ancestor = current.superview
        }
        return false
    }
}

@MainActor
private final class PaletteTestScreenProvider: ScreenProviding {
    let displays: [DisplayDescriptor]

    init(displays: [DisplayDescriptor]) {
        self.displays = displays
    }

    func currentDisplays() -> [DisplayDescriptor] { displays }
    func pointerDisplay() -> DisplayUUID? { displays.first?.uuid }
}

@MainActor
private final class PaletteTestOverlay: OverlayPresenting {
    var display: DisplayDescriptor

    init(display: DisplayDescriptor) {
        self.display = display
    }

    func update(display: DisplayDescriptor) { self.display = display }
    func update(session: PointerSession) {}
    func setMode(_ mode: PointerMode) {}
    func setEventHandlers(
        onSessionUpdate: @escaping (PointerSession) -> Void,
        onBoundaryEvent: @escaping (GestureBoundaryEvent) -> Void
    ) {}
    func close() {}
}
