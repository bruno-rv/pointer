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
        XCTAssertFalse(byID["palette.overflow.header"]?.isEnabled == true)

        let overflow = try XCTUnwrap(
            fixture.palette.paletteViewController.control(identifier: "palette.tools.overflow")
                as? NSPopUpButton
        )
        let menu = try XCTUnwrap(overflow.menu)
        XCTAssertEqual(
            menu.items.filter { $0.identifier?.rawValue.hasPrefix("palette.overflow.tool.") == true }.count,
            3
        )
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
        XCTAssertEqual(
            byID["menu.shortcut"]?.value,
            "Press Control-Option-Command-O within 5 seconds to confirm"
        )
        XCTAssertEqual(
            byID["menu.shortcut.control-option-command-p"]?.value,
            "Selected"
        )
        XCTAssertEqual(
            byID["menu.shortcut.control-option-command-o"]?.value,
            "Pending"
        )

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
    }

    func testNoDisplayMetadataIsDeterministicAndKeepsLearningAndQuitDiscoverable() {
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
    }

    func testNativeTraversalMatchesReachableHarnessMetadataAtWideAndClampedWidths() throws {
        for makeFixture in [
            { DeterministicInteractionFixture.standard() },
            { DeterministicInteractionFixture.clamped() },
        ] {
            let fixture = makeFixture()
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

            let expected = harness.metadata()
                .filter { $0.identifier.hasPrefix("palette.") }
                .filter(\.isKeyboardReachable)
                .filter { !$0.identifier.hasPrefix("palette.overflow.tool.") }
                .map(\.identifier)
            let start = fixture.palette.paletteViewController.control(identifier: "palette.mode")
            XCTAssertTrue(fixture.palette.makeFirstResponder(start))
            var actual = [start.identifier!.rawValue]
            for _ in 1..<expected.count {
                fixture.palette.selectNextKeyView(nil)
                let responder = try XCTUnwrap(fixture.palette.firstResponder as? NSView)
                actual.append(try XCTUnwrap(responder.identifier?.rawValue))
            }
            XCTAssertEqual(actual, expected)
        }
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
