import AppKit
import PointerCore
import XCTest
@testable import PointerAppKit

@MainActor
final class ControlMetadataHarnessTests: XCTestCase {
    func testWideFixtureExposesCompleteStableMetadataWithoutOverflow() throws {
        let fixture = DeterministicInteractionFixture.standard()
        let harness = fixture.makeHarness()
        _ = harness.synchronizeDisplays()
        let display = try XCTUnwrap(fixture.screenProvider.displays.first)
        guard case .shown = fixture.palette.show(on: display) else {
            return XCTFail("Expected the standard display to show the palette")
        }
        fixture.menuBar.install()
        defer {
            fixture.menuBar.remove()
            fixture.palette.close()
            fixture.shortcutController.stop()
        }

        XCTAssertEqual(fixture.palette.frame.width, 822, accuracy: 0.5)
        let metadata = harness.metadata()
        let byID = assertCompleteMetadata(metadata)
        XCTAssertFalse(metadata.contains { $0.identifier.hasPrefix("palette.overflow.tool.") })
        XCTAssertEqual(
            metadata.map(\.identifier).filter { $0.hasPrefix("palette.tool.") },
            PointerTool.allCases.map { "palette.tool.\(toolIdentifier($0))" }
        )
        let wideMore = fixture.palette.paletteViewController.control(identifier: "palette.tools.overflow")
        XCTAssertTrue(wideMore.isHidden)
        XCTAssertFalse(byID["palette.tools.overflow"]?.isKeyboardReachable == true)
        XCTAssertEqual(
            fixture.palette.paletteViewController.control(identifier: "palette.mode")
                .accessibilityRoleDescription(),
            "button"
        )
        XCTAssertEqual(wideMore.accessibilityRoleDescription(), "popup button")
        XCTAssertEqual(
            fixture.palette.paletteViewController.control(identifier: "palette.emoji")
                .accessibilityRoleDescription(),
            "popup button"
        )
        XCTAssertEqual(
            fixture.palette.paletteViewController.control(identifier: "palette.style.color")
                .accessibilityRoleDescription(),
            "color well"
        )
        XCTAssertEqual(
            fixture.palette.paletteViewController.control(identifier: "palette.style.stroke-width")
                .accessibilityRoleDescription(),
            "slider"
        )
        XCTAssertEqual(
            fixture.palette.paletteViewController.control(identifier: "palette.status")
                .accessibilityRoleDescription(),
            "status"
        )
        let wideMenu = try XCTUnwrap(fixture.menuBar.menu)
        let wideMenuButton = try XCTUnwrap(fixture.menuBar.statusItem?.button)
        let wideShortcutParent = try XCTUnwrap(menuItem("menu.shortcut", in: wideMenu))
        XCTAssertEqual(wideMenuButton.accessibilityRoleDescription(), "menu bar item")
        XCTAssertEqual(wideShortcutParent.accessibilityRoleDescription(), "menu")
        XCTAssertEqual(byID["palette.mode"]?.role, "AXButton")
        XCTAssertEqual(byID["palette.tools.overflow"]?.role, "AXPopUpButton")
        XCTAssertEqual(byID["palette.emoji"]?.role, "AXPopUpButton")
        XCTAssertEqual(byID["palette.style.color"]?.role, "AXColorWell")
        XCTAssertEqual(byID["palette.style.stroke-width"]?.role, "AXSlider")
        XCTAssertEqual(byID["palette.status"]?.role, "AXStaticText")
        XCTAssertEqual(byID["pointer.menu-bar"]?.role, "AXButton")
        XCTAssertEqual(byID["menu.shortcut"]?.role, "AXMenuItem")

        XCTAssertEqual(
            byID["palette.mode"]?.value,
            "Off"
        )
        XCTAssertEqual(byID["palette.tool.arrow"]?.value, "Selected")
        XCTAssertEqual(byID["palette.tools.overflow"]?.value, "No hidden tools")
        for identifier in [
            "palette.style.color",
            "palette.style.stroke-width",
            "palette.style.opacity",
            "palette.emoji",
            "palette.spotlight.radius",
            "palette.spotlight.dimness",
            "palette.undo",
            "palette.clear",
            "palette.status",
        ] {
            XCTAssertNotNil(byID[identifier]?.value, identifier)
        }

        XCTAssertTrue(byID["palette.mode"]?.isEnabled == true)
        XCTAssertTrue(byID["palette.mode"]?.isKeyboardReachable == true)
        for tool in PointerTool.allCases {
            let identifier = "palette.tool.\(toolIdentifier(tool))"
            XCTAssertTrue(byID[identifier]?.isEnabled == true, identifier)
            XCTAssertTrue(byID[identifier]?.isKeyboardReachable == true, identifier)
        }
        for identifier in [
            "palette.style.color",
            "palette.style.stroke-width",
            "palette.style.opacity",
        ] {
            XCTAssertTrue(byID[identifier]?.isKeyboardReachable == true, identifier)
        }
        for identifier in [
            "palette.emoji",
            "palette.spotlight.radius",
            "palette.spotlight.dimness",
            "palette.undo",
            "palette.clear",
            "palette.delete",
        ] {
            XCTAssertFalse(byID[identifier]?.isEnabled == true, identifier)
            XCTAssertFalse(byID[identifier]?.isKeyboardReachable == true, identifier)
        }
        XCTAssertFalse(byID["palette.status"]?.isKeyboardReachable == true)

        for identifier in [
            "menu.show-palette",
            "menu.learn-pointer",
            "menu.toggle-mode",
            "menu.shortcut",
            "menu.shortcut.control-option-command-p",
            "menu.shortcut.control-option-command-o",
            "menu.quit",
        ] {
            XCTAssertTrue(byID[identifier]?.isEnabled == true, identifier)
            XCTAssertTrue(byID[identifier]?.isKeyboardReachable == true, identifier)
        }
        XCTAssertEqual(
            byID["menu.shortcut.control-option-command-p"]?.value,
            "Selected"
        )
        XCTAssertEqual(
            byID["menu.shortcut.control-option-command-o"]?.value,
            "Not selected"
        )
        XCTAssertEqual(
            byID["menu.shortcut"]?.value,
            "Active: Control-Option-Command-P"
        )
        XCTAssertFalse(byID["menu.clear-all"]?.isEnabled == true)
        XCTAssertFalse(byID["menu.undo-clear-all"]?.isEnabled == true)
        XCTAssertFalse(byID["menu.clear-all"]?.isKeyboardReachable == true)
        XCTAssertFalse(byID["menu.undo-clear-all"]?.isKeyboardReachable == true)

    }

    func testClampedFixtureReplacesHiddenToolsExactlyOnceWithOverflowMetadata() throws {
        let fixture = DeterministicInteractionFixture.clamped()
        let harness = fixture.makeHarness()
        _ = harness.synchronizeDisplays()
        let display = try XCTUnwrap(fixture.screenProvider.displays.first)
        guard case .shown = fixture.palette.show(on: display) else {
            return XCTFail("Expected the clamped display to show the palette")
        }
        defer {
            fixture.palette.close()
            fixture.shortcutController.stop()
        }

        XCTAssertEqual(fixture.palette.frame.width, 760, accuracy: 0.5)
        let clampedMore = fixture.palette.paletteViewController.control(identifier: "palette.tools.overflow")
        XCTAssertFalse(clampedMore.isHidden)
        harness.route(.setMode(.annotation))
        harness.route(.setTool(.eraser))

        let metadata = harness.metadata()
        let byID = assertCompleteMetadata(metadata)
        let directToolIDs = metadata
            .map(\.identifier)
            .filter { $0.hasPrefix("palette.tool.") }
        let overflowToolIDs = metadata
            .map(\.identifier)
            .filter { $0.hasPrefix("palette.overflow.tool.") }

        XCTAssertEqual(
            directToolIDs,
            [
                "palette.tool.select",
                "palette.tool.arrow",
                "palette.tool.rectangle",
                "palette.tool.ellipse",
                "palette.tool.pen",
            ]
        )
        XCTAssertEqual(
            overflowToolIDs,
            [
                "palette.overflow.tool.eraser",
                "palette.overflow.tool.emoji",
                "palette.overflow.tool.spotlight",
            ]
        )
        XCTAssertEqual(
            Set(directToolIDs + overflowToolIDs).count,
            PointerTool.allCases.count
        )
        XCTAssertEqual(
            Set(directToolIDs + overflowToolIDs),
            Set([
                "palette.tool.select",
                "palette.tool.arrow",
                "palette.tool.rectangle",
                "palette.tool.ellipse",
                "palette.tool.pen",
                "palette.overflow.tool.eraser",
                "palette.overflow.tool.emoji",
                "palette.overflow.tool.spotlight",
            ])
        )
        XCTAssertFalse(metadata.contains { $0.identifier == "palette.tool.eraser" })
        XCTAssertFalse(metadata.contains { $0.identifier == "palette.tool.emoji" })
        XCTAssertFalse(metadata.contains { $0.identifier == "palette.tool.spotlight" })
        XCTAssertEqual(byID["palette.tool.arrow"]?.value, "Not selected")
        XCTAssertEqual(byID["palette.overflow.tool.eraser"]?.value, "Selected")
        XCTAssertEqual(byID["palette.overflow.tool.emoji"]?.value, "Not selected")
        XCTAssertEqual(byID["palette.overflow.tool.spotlight"]?.value, "Not selected")
        XCTAssertTrue(byID["palette.tools.overflow"]?.value?.contains("Eraser") == true)
        XCTAssertTrue(byID["palette.tools.overflow"]?.isEnabled == true)
        XCTAssertTrue(byID["palette.tools.overflow"]?.isKeyboardReachable == true)

        let overflowParentIndex = try XCTUnwrap(
            metadata.firstIndex { $0.identifier == "palette.tools.overflow" }
        )
        let overflowSequence = Array(metadata[overflowParentIndex...].prefix(5))
            .map(\.identifier)
        XCTAssertEqual(
            overflowSequence,
            [
                "palette.tools.overflow",
                "palette.overflow.header",
                "palette.overflow.tool.eraser",
                "palette.overflow.tool.emoji",
                "palette.overflow.tool.spotlight",
            ]
        )
        let overflow = try XCTUnwrap(
            fixture.palette.paletteViewController.control(identifier: "palette.tools.overflow")
                as? NSPopUpButton
        )
        let menu = try XCTUnwrap(overflow.menu)
        XCTAssertFalse(byID["palette.overflow.header"]?.isEnabled == true)
        XCTAssertFalse(byID["palette.overflow.header"]?.isKeyboardReachable == true)
        XCTAssertEqual(
            byID["palette.overflow.header"]?.accessibleName,
            "More annotation tools; active tool Eraser"
        )
        XCTAssertEqual(
            byID["palette.overflow.header"]?.help,
            "Choose an annotation tool from the compact overflow menu"
        )
        XCTAssertEqual(byID["palette.overflow.header"]?.value, "Eraser")
        XCTAssertEqual(byID["palette.overflow.header"]?.role, "AXMenuItem")
        XCTAssertNotEqual(byID["palette.overflow.header"]?.role, "AXUnknown")
        XCTAssertEqual(
            try XCTUnwrap(menu.items.first { $0.identifier?.rawValue == "palette.overflow.header" })
                .accessibilityRoleDescription(),
            "menu item"
        )

        XCTAssertEqual(
            menu.items.filter { $0.identifier?.rawValue.hasPrefix("palette.overflow.tool.") == true }.count,
            3
        )
        for item in menu.items where item.identifier?.rawValue.hasPrefix("palette.overflow.tool.") == true {
            XCTAssertNotNil(item.action, item.identifier?.rawValue ?? "overflow item")
            XCTAssertNotNil(item.target, item.identifier?.rawValue ?? "overflow item")
        }
    }

    func testCanonicalNarrowFixtureKeepsNativePaletteAndOverflowAccessible() throws {
        let fixture = DeterministicInteractionFixture.narrow()
        let harness = fixture.makeHarness()
        let sync = harness.synchronizeDisplays()
        let display = try XCTUnwrap(fixture.screenProvider.displays.first)
        XCTAssertEqual(display.visibleFrame.width, 420)
        XCTAssertTrue(sync.hasConnectedDisplays)
        XCTAssertEqual(sync.connectedUUIDs, Set([display.uuid]))
        guard case .shown = fixture.palette.show(on: display) else {
            return XCTFail("Expected the canonical narrow display to show the palette")
        }
        defer {
            fixture.palette.close()
            fixture.shortcutController.stop()
        }

        XCTAssertEqual(fixture.palette.frame.width, 388, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(
            fixture.palette.frame.width,
            CGFloat(PaletteLayout.minimumSupportedWidth)
        )
        XCTAssertTrue(fixture.palette.isVisible)

        let controller = fixture.palette.paletteViewController
        XCTAssertGreaterThan(controller.view.bounds.width, 0)
        let more = controller.control(identifier: "palette.tools.overflow")
        XCTAssertFalse(more.isHidden)
        XCTAssertTrue(more.isEnabled)
        XCTAssertTrue(more.acceptsFirstResponder)
        XCTAssertNotNil(more.target)
        XCTAssertNotNil(more.action)
        let visibleTools: Set<PointerTool> = [.select]
        for tool in PointerTool.allCases {
            let control = controller.control(identifier: "palette.tool.\(toolIdentifier(tool))")
            XCTAssertEqual(control.isHidden, !visibleTools.contains(tool), tool.displayName)
        }

        let overflow = try XCTUnwrap(more as? NSPopUpButton)
        let overflowMenu = try XCTUnwrap(overflow.menu)
        XCTAssertEqual(
            overflowMenu.items.map { $0.identifier?.rawValue },
            [
                "palette.overflow.header",
                "palette.overflow.tool.arrow",
                "palette.overflow.tool.rectangle",
                "palette.overflow.tool.ellipse",
                "palette.overflow.tool.pen",
                "palette.overflow.tool.eraser",
                "palette.overflow.tool.emoji",
                "palette.overflow.tool.spotlight",
            ]
        )
        for item in overflowMenu.items.dropFirst() {
            XCTAssertTrue(item.isEnabled)
            XCTAssertNotNil(item.target)
            XCTAssertNotNil(item.action)
        }

        let metadata = harness.metadata()
        let byID = assertCompleteMetadata(metadata)
        XCTAssertEqual(
            metadata.map(\.identifier).filter { $0.hasPrefix("palette.tool.") },
            ["palette.tool.select"]
        )
        XCTAssertEqual(
            metadata.map(\.identifier).filter { $0.hasPrefix("palette.overflow.tool.") },
            [
                "palette.overflow.tool.arrow",
                "palette.overflow.tool.rectangle",
                "palette.overflow.tool.ellipse",
                "palette.overflow.tool.pen",
                "palette.overflow.tool.eraser",
                "palette.overflow.tool.emoji",
                "palette.overflow.tool.spotlight",
            ]
        )
        let overflowParentIndex = try XCTUnwrap(
            metadata.firstIndex { $0.identifier == "palette.tools.overflow" }
        )
        XCTAssertEqual(
            Array(metadata[overflowParentIndex...].prefix(9)).map(\.identifier),
            [
                "palette.tools.overflow",
                "palette.overflow.header",
                "palette.overflow.tool.arrow",
                "palette.overflow.tool.rectangle",
                "palette.overflow.tool.ellipse",
                "palette.overflow.tool.pen",
                "palette.overflow.tool.eraser",
                "palette.overflow.tool.emoji",
                "palette.overflow.tool.spotlight",
            ]
        )
        XCTAssertTrue(byID["palette.tools.overflow"]?.isEnabled == true)
        XCTAssertTrue(byID["palette.tools.overflow"]?.isKeyboardReachable == true)
        XCTAssertEqual(
            Set(metadata.map(\.identifier).filter {
                $0 == "palette.style.color"
                    || $0 == "palette.emoji"
                    || $0 == "palette.style.stroke-width"
                    || $0 == "palette.style.opacity"
                    || $0 == "palette.spotlight.radius"
                    || $0 == "palette.spotlight.dimness"
            }),
            Set([
                "palette.style.color",
                "palette.emoji",
                "palette.style.stroke-width",
                "palette.style.opacity",
                "palette.spotlight.radius",
                "palette.spotlight.dimness",
            ])
        )
        XCTAssertTrue(metadata.filter {
            $0.identifier == "palette.style.color"
                || $0.identifier == "palette.emoji"
                || $0.identifier == "palette.style.stroke-width"
                || $0.identifier == "palette.style.opacity"
                || $0.identifier == "palette.spotlight.radius"
                || $0.identifier == "palette.spotlight.dimness"
        }.allSatisfy { $0.value != nil && $0.help?.isEmpty == false })

        controller.refresh(session: fixture.commandRouter.session)
        controller.applyLayout(for: 388)
        fixture.palette.window.contentView?.layoutSubtreeIfNeeded()
        let expected = [
            "palette.mode",
            "palette.tool.select",
            "palette.tools.overflow",
            "palette.style.color",
            "palette.style.stroke-width",
            "palette.style.opacity",
        ]
        let start = controller.control(identifier: "palette.mode")
        XCTAssertTrue(fixture.palette.makeFirstResponder(start))
        var actual = [start.identifier!.rawValue]
        for _ in 1..<expected.count {
            fixture.palette.selectNextKeyView(nil)
            let responder = try XCTUnwrap(fixture.palette.firstResponder as? NSView)
            actual.append(try XCTUnwrap(responder.identifier?.rawValue))
        }
        XCTAssertEqual(actual, expected)
        fixture.palette.selectNextKeyView(nil)
        let wrapped = try XCTUnwrap(fixture.palette.firstResponder as? NSView)
        XCTAssertEqual(wrapped.identifier?.rawValue, "palette.mode")

        let styleScrollView = try XCTUnwrap(
            descendantViews(of: controller.view)
                .compactMap { $0 as? NSScrollView }
                .first { $0.hasHorizontalScroller }
        )
        XCTAssertFalse(styleScrollView.isHidden)
        XCTAssertTrue(styleScrollView.hasHorizontalScroller)
    }

    func testPendingShortcutMetadataKeepsPAndOCandidatesActionable() throws {
        let fixture = DeterministicInteractionFixture.standard()
        let harness = fixture.makeHarness()
        _ = harness.synchronizeDisplays()
        fixture.menuBar.install()
        defer {
            fixture.menuBar.remove()
            fixture.shortcutController.stop()
        }

        harness.route(.setShortcut(.controlOptionCommandO))
        let metadata = harness.metadata()
        let byID = assertCompleteMetadata(metadata)
        let guidance = "Press Control-Option-Command-O within 5 seconds to confirm"
        for identifier in [
            "menu.shortcut",
            "menu.shortcut.control-option-command-p",
            "menu.shortcut.control-option-command-o",
        ] {
            XCTAssertTrue(byID[identifier]?.isEnabled == true, identifier)
            XCTAssertTrue(byID[identifier]?.isKeyboardReachable == true, identifier)
        }
        XCTAssertEqual(
            byID["menu.shortcut"]?.value,
            guidance
        )
        XCTAssertEqual(byID["menu.shortcut"]?.help, guidance)
        XCTAssertEqual(
            byID["menu.shortcut.control-option-command-p"]?.value,
            "Selected"
        )
        XCTAssertEqual(
            byID["menu.shortcut.control-option-command-o"]?.value,
            "Pending"
        )
        XCTAssertEqual(
            byID["menu.shortcut.control-option-command-p"]?.help,
            "Pointer command: Control-Option-Command-P"
        )
        XCTAssertEqual(byID["menu.shortcut.control-option-command-o"]?.help, guidance)
        XCTAssertEqual(byID["palette.status"]?.value, guidance)
        XCTAssertEqual(byID["palette.status"]?.help, "Current annotation mode and shortcut status")
        XCTAssertEqual(byID["pointer.menu-bar"]?.value, guidance)
        XCTAssertEqual(byID["pointer.menu-bar"]?.help, guidance)

        let shortcutParent = try XCTUnwrap(fixture.menuBar.menu?.items.first {
            $0.identifier?.rawValue == "menu.shortcut"
        })
        let pItem = try XCTUnwrap(shortcutParent.submenu?.items.first {
            $0.identifier?.rawValue == "menu.shortcut.control-option-command-p"
        })
        let oItem = try XCTUnwrap(shortcutParent.submenu?.items.first {
            $0.identifier?.rawValue == "menu.shortcut.control-option-command-o"
        })
        XCTAssertEqual(pItem.title, ShortcutPreset.controlOptionCommandP.displayName)
        XCTAssertEqual(oItem.title, ShortcutPreset.controlOptionCommandO.displayName)
        XCTAssertEqual(pItem.representedObject as? String, ShortcutPreset.controlOptionCommandP.rawValue)
        XCTAssertEqual(oItem.representedObject as? String, ShortcutPreset.controlOptionCommandO.rawValue)
        XCTAssertNotNil(shortcutParent.action)
        XCTAssertNotNil(shortcutParent.submenu)
        XCTAssertNotNil(pItem.action)
        XCTAssertNotNil(pItem.target)
        XCTAssertNotNil(oItem.action)
        XCTAssertNotNil(oItem.target)
    }

    func testNoDisplayMetadataIsDeterministicAndKeepsLearningAndQuitDiscoverable() throws {
        let fixture = DeterministicInteractionFixture.empty()
        let harness = fixture.makeHarness()
        let firstSync = harness.synchronizeDisplays()
        fixture.menuBar.install()
        defer {
            fixture.menuBar.remove()
            fixture.shortcutController.stop()
        }

        XCTAssertFalse(firstSync.hasConnectedDisplays)
        XCTAssertTrue(firstSync.connectedUUIDs.isEmpty)
        let initialSession = fixture.commandRouter.session
        let initialSnapshot = harness.snapshot()
        for command in [
            CommandRouter.Command.toggleMode,
            .setMode(.annotation),
            .setTool(.rectangle),
        ] {
            harness.route(command)
        }
        XCTAssertEqual(fixture.commandRouter.session, initialSession)
        let finalSnapshot = harness.snapshot()
        XCTAssertEqual(finalSnapshot.mode, initialSnapshot.mode)
        XCTAssertEqual(finalSnapshot.selectedTool, initialSnapshot.selectedTool)
        XCTAssertEqual(finalSnapshot.marksByDisplay, initialSnapshot.marksByDisplay)
        XCTAssertEqual(finalSnapshot.previewMarksByDisplay, initialSnapshot.previewMarksByDisplay)

        let first = harness.metadata()
        let second = harness.metadata()
        XCTAssertEqual(first, second)
        let byID = assertCompleteMetadata(first)
        for identifier in [
            "menu.shortcut",
            "menu.shortcut.control-option-command-p",
            "menu.shortcut.control-option-command-o",
        ] {
            XCTAssertTrue(byID[identifier]?.isEnabled == true, identifier)
            XCTAssertTrue(byID[identifier]?.isKeyboardReachable == true, identifier)
        }
        XCTAssertEqual(byID["menu.shortcut"]?.value, "Active: Control-Option-Command-P")
        XCTAssertEqual(byID["menu.shortcut"]?.help, "Choose the active global shortcut preset")
        XCTAssertEqual(byID["menu.shortcut.control-option-command-p"]?.value, "Selected")
        XCTAssertEqual(byID["menu.shortcut.control-option-command-o"]?.value, "Not selected")
        XCTAssertEqual(
            byID["palette.status"]?.help,
            "Current annotation mode and shortcut status"
        )
        XCTAssertEqual(byID["pointer.menu-bar"]?.help, "No presentation display connected")

        XCTAssertEqual(byID["palette.mode"]?.value, "Off")
        XCTAssertEqual(byID["palette.status"]?.value, "No presentation display connected")
        XCTAssertFalse(byID["menu.toggle-mode"]?.isEnabled == true)
        XCTAssertFalse(byID["menu.toggle-mode"]?.isKeyboardReachable == true)
        XCTAssertEqual(
            byID["menu.toggle-mode"]?.value,
            "Unavailable — no presentation display connected"
        )
        XCTAssertFalse(byID["menu.clear-all"]?.isEnabled == true)
        XCTAssertEqual(
            byID["menu.clear-all"]?.value,
            "Unavailable — no marks to clear"
        )
        XCTAssertFalse(byID["menu.undo-clear-all"]?.isEnabled == true)
        XCTAssertEqual(byID["pointer.menu-bar"]?.value, "No presentation display connected")

        for identifier in ["menu.show-palette", "menu.learn-pointer", "menu.quit"] {
            XCTAssertTrue(byID[identifier]?.isEnabled == true, identifier)
            XCTAssertTrue(byID[identifier]?.isKeyboardReachable == true, identifier)
        }
        let menu = try XCTUnwrap(fixture.menuBar.menu)
        for identifier in [
            "menu.shortcut",
            "menu.shortcut.control-option-command-p",
            "menu.shortcut.control-option-command-o",
            "menu.show-palette",
            "menu.learn-pointer",
            "menu.quit",
        ] {
            let item = try XCTUnwrap(menuItem(identifier, in: menu))
            XCTAssertNotNil(item.action, identifier)
            XCTAssertNotNil(item.target, identifier)
        }
    }

    func testNativeTraversalMatchesReachableHarnessMetadataAtWideAndClampedWidths() throws {
        let cases: [(DeterministicInteractionFixture, [String])] = [
            (
                DeterministicInteractionFixture.standard(),
                [
                    "palette.mode",
                    "palette.tool.select",
                    "palette.tool.arrow",
                    "palette.tool.rectangle",
                    "palette.tool.ellipse",
                    "palette.tool.pen",
                    "palette.tool.eraser",
                    "palette.tool.emoji",
                    "palette.tool.spotlight",
                    "palette.style.color",
                    "palette.style.stroke-width",
                    "palette.style.opacity",
                ]
            ),
            (
                DeterministicInteractionFixture.clamped(),
                [
                    "palette.mode",
                    "palette.tool.select",
                    "palette.tool.arrow",
                    "palette.tool.rectangle",
                    "palette.tool.ellipse",
                    "palette.tool.pen",
                    "palette.tools.overflow",
                    "palette.style.color",
                    "palette.style.stroke-width",
                    "palette.style.opacity",
                ]
            ),
        ]
        for (fixture, expected) in cases {
            let harness = fixture.makeHarness()
            _ = harness.synchronizeDisplays()
            let display = try XCTUnwrap(fixture.screenProvider.displays.first)
            guard case .shown = fixture.palette.show(on: display) else {
                return XCTFail("Expected the palette to show for \(display.uuid.rawValue)")
            }
            defer {
                fixture.palette.close()
                fixture.shortcutController.stop()
            }
            fixture.palette.paletteViewController.refresh(session: fixture.commandRouter.session)
            fixture.palette.window.contentView?.layoutSubtreeIfNeeded()

            let start = fixture.palette.paletteViewController.control(identifier: "palette.mode")
            XCTAssertTrue(fixture.palette.makeFirstResponder(start))
            var actual = [start.identifier!.rawValue]
            for _ in 1..<expected.count {
                fixture.palette.selectNextKeyView(nil)
                let responder = try XCTUnwrap(fixture.palette.firstResponder as? NSView)
                actual.append(try XCTUnwrap(responder.identifier?.rawValue))
            }
            XCTAssertEqual(actual, expected)
            fixture.palette.selectNextKeyView(nil)
            let wrapped = try XCTUnwrap(fixture.palette.firstResponder as? NSView)
            XCTAssertEqual(wrapped.identifier?.rawValue, "palette.mode")
        }
    }

    private func menuItem(_ identifier: String, in menu: NSMenu) -> NSMenuItem? {
        if let direct = menu.items.first(where: { $0.identifier?.rawValue == identifier }) {
            return direct
        }
        return menu.items
            .compactMap(\.submenu)
            .flatMap(\.items)
            .first { $0.identifier?.rawValue == identifier }
    }

    private func descendantViews(of root: NSView) -> [NSView] {
        [root] + root.subviews.flatMap(descendantViews)
    }

    @discardableResult
    private func assertCompleteMetadata(
        _ metadata: [ControlMetadata],
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [String: ControlMetadata] {
        XCTAssertFalse(metadata.isEmpty, file: file, line: line)
        XCTAssertEqual(
            Set(metadata.map(\.identifier)).count,
            metadata.count,
            "Metadata identifiers must be unique",
            file: file,
            line: line
        )
        XCTAssertTrue(metadata.allSatisfy {
            !$0.identifier.isEmpty
                && !$0.accessibleName.isEmpty
                && $0.help?.isEmpty == false
                && !$0.role.isEmpty
                && $0.role != "AXUnknown"
        }, "Every metadata row needs an identifier, name, help, and role", file: file, line: line)
        return metadata.reduce(into: [String: ControlMetadata]()) { rows, row in
            rows[row.identifier] = row
        }
    }

    private func toolIdentifier(_ tool: PointerTool) -> String {
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
}
