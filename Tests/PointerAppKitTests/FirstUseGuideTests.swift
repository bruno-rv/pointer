import AppKit
import XCTest
@testable import PointerAppKit

@MainActor
final class FirstUseGuideTests: XCTestCase {
    func testFailedOrHiddenPanelDoesNotMarkGuideSeen() {
        let fixture = FirstUseGuideTestFixture()
        fixture.panel.becomesVisibleOnShow = false

        XCTAssertEqual(fixture.controller.showIfNeeded(in: fixture.context), .failed("Guide window did not become visible"))
        XCTAssertEqual(fixture.stateStore.markCount, 0)
        XCTAssertFalse(fixture.stateStore.hasDismissedFirstUseGuide)
        XCTAssertFalse(fixture.controller.isVisible)
    }

    func testVisiblePanelMarksSeenOnlyAfterOrderFrontCallback() {
        let fixture = FirstUseGuideTestFixture()
        fixture.panel.invokesVisibleCallbackOnShow = false

        XCTAssertEqual(fixture.controller.showIfNeeded(in: fixture.context), .failed("Guide window did not become visible"))
        XCTAssertEqual(fixture.stateStore.markCount, 0)
        XCTAssertFalse(fixture.stateStore.hasDismissedFirstUseGuide)
    }

    func testCloseDoneAndEscapeDismissWithoutModeToolOrCanvasMutation() {
        let fixture = FirstUseGuideTestFixture()
        XCTAssertEqual(fixture.controller.show(in: fixture.context), .shown)
        XCTAssertTrue(fixture.controller.isVisible)

        XCTAssertTrue(fixture.controller.consumeEscape())
        XCTAssertFalse(fixture.controller.isVisible)
        XCTAssertFalse(fixture.controller.consumeEscape())
        XCTAssertEqual(fixture.panel.events, ["show", "visible", "close"])
    }

    func testDisplayLossHideAndReconnectRestoreOnceAfterPaletteShown() {
        let fixture = FirstUseGuideTestFixture()
        XCTAssertEqual(fixture.controller.show(in: fixture.context), .shown)
        fixture.controller.hideForDisplayLoss()
        XCTAssertFalse(fixture.controller.isVisible)
        XCTAssertEqual(fixture.stateStore.markCount, 1)

        XCTAssertEqual(fixture.controller.restoreAfterDisplayLoss(in: fixture.context), .shown)
        XCTAssertTrue(fixture.controller.isVisible)
        XCTAssertEqual(fixture.panel.showContexts.count, 2)
        XCTAssertEqual(fixture.controller.restoreAfterDisplayLoss(in: fixture.context), .notNeeded)
        XCTAssertEqual(fixture.panel.showContexts.count, 2)
    }

    func testApplicationStopClearsDisplayLossIntentWithoutSeenMutation() {
        let fixture = FirstUseGuideTestFixture()
        XCTAssertEqual(fixture.controller.showIfNeeded(in: fixture.context), .shown)
        let markCount = fixture.stateStore.markCount
        fixture.controller.hideForDisplayLoss()
        fixture.controller.hideForApplicationStop()

        XCTAssertFalse(fixture.controller.isVisible)
        XCTAssertEqual(fixture.stateStore.markCount, markCount)
        XCTAssertEqual(fixture.controller.restoreAfterDisplayLoss(in: fixture.context), .notNeeded)
    }

    func testSeenAndUnseenRestartRulesDoNotAutomaticallyReopenDismissedGuide() {
        let fixture = FirstUseGuideTestFixture(hasDismissedFirstUseGuide: true)
        XCTAssertEqual(fixture.controller.showIfNeeded(in: fixture.context), .notNeeded)
        XCTAssertTrue(fixture.panel.showContexts.isEmpty)
        XCTAssertFalse(fixture.controller.isVisible)
    }

    func testGuidePlacementProviderReceivesDisplayFramesAndClamps() {
        let fixture = FirstUseGuideTestFixture()
        _ = fixture.placementProvider.context(
            for: fixture.display,
            paletteFrame: fixture.context.paletteFrame
        )

        XCTAssertEqual(fixture.placementProvider.contexts.last?.display, fixture.display)
        XCTAssertEqual(fixture.placementProvider.contexts.last?.visibleFrame, fixture.display.visibleFrame)
        XCTAssertTrue(fixture.placementProvider.contexts.last?.avoidanceFrames.contains(fixture.context.paletteFrame) == true)
    }

    func testEveryGuideExampleResolvesThroughInjectedCatalog() {
        let fixture = FirstUseGuideTestFixture()
        XCTAssertEqual(fixture.controller.show(in: fixture.context), .shown)

        XCTAssertEqual(fixture.catalog.imageRequests.count, 8)
        XCTAssertEqual(
            Set(fixture.catalog.imageRequests.map(\.0)),
            Set(["arrow", "rectangle", "ellipse", "pen", "spotlight", "emoji", "select", "eraser"])
        )
        XCTAssertTrue(fixture.catalog.imageRequests.allSatisfy { $0.1 == .light })
    }

    func testGuideExamplesExposeInjectedAccessibleMetadataAndFocusOrder() {
        let customArrow = GuideAssetDescriptor(
            id: "arrow",
            accessibleName: "Attention arrow",
            accessibleDescription: "Draws an attention arrow toward the important detail",
            isDecorative: false,
            variants: GuideAssetVariant.allCases.map {
                GuideAssetVariantDescriptor(
                    variant: $0,
                    assetIdentifier: "arrow",
                    sourceSHA256: String(repeating: "a", count: 64)
                )
            }
        )
        let fixture = FirstUseGuideTestFixture()
        let catalog = FirstUseGuideTestCatalog(
            entries: [customArrow] + fixture.catalog.entries.dropFirst()
        )
        let viewController = FirstUseGuideViewController(assetCatalog: catalog)
        viewController.loadViewIfNeeded()

        XCTAssertEqual(viewController.exampleImageViews.first?.accessibilityLabel(), "Attention arrow")
        XCTAssertEqual(
            viewController.exampleImageViews.first?.accessibilityHelp(),
            "Draws an attention arrow toward the important detail"
        )
        XCTAssertEqual(viewController.doneButton?.accessibilityLabel(), "Done")
    }

    func testGuideProtocolIsDeclaredOnlyInCAndConcreteCatalogStaysDLocal() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
        let helpRoot = sourceRoot.appendingPathComponent("PointerAppKit/Help")
        let stateSource = try String(
            contentsOf: helpRoot.appendingPathComponent("FirstUseGuideStateStoring.swift"),
            encoding: .utf8
        )
        let presentingSource = try String(
            contentsOf: helpRoot.appendingPathComponent("FirstUseGuidePresenting.swift"),
            encoding: .utf8
        )
        XCTAssertEqual(stateSource.components(separatedBy: "protocol FirstUseGuideStateStoring").count - 1, 1)
        XCTAssertEqual(presentingSource.components(separatedBy: "protocol FirstUseGuidePresenting").count - 1, 1)

        let sourceFiles = try FileManager.default
            .subpathsOfDirectory(atPath: sourceRoot.path)
            .filter { $0.hasSuffix(".swift") }
        var stateDeclarations = 0
        var presentingDeclarations = 0
        var stateExtensions = 0
        var presentingExtensions = 0
        for relativePath in sourceFiles {
            let source = try String(
                contentsOf: sourceRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            stateDeclarations += source.components(separatedBy: "protocol FirstUseGuideStateStoring").count - 1
            presentingDeclarations += source.components(separatedBy: "protocol FirstUseGuidePresenting").count - 1
            stateExtensions += source.components(separatedBy: "extension FirstUseGuideStateStoring").count - 1
            presentingExtensions += source.components(separatedBy: "extension FirstUseGuidePresenting").count - 1
        }
        XCTAssertEqual(stateDeclarations, 1)
        XCTAssertEqual(presentingDeclarations, 1)
        XCTAssertEqual(stateExtensions, 0)
        XCTAssertEqual(presentingExtensions, 0)

        for relativePath in sourceFiles where relativePath.hasPrefix("PointerAppKit/Help/") {
            let url = sourceRoot.appendingPathComponent(relativePath)
            guard url.lastPathComponent != "FirstUseGuideStateStoring.swift",
                  url.lastPathComponent != "FirstUseGuidePresenting.swift" else { continue }
            let source = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(source.contains("protocol FirstUseGuideStateStoring"), url.path)
            XCTAssertFalse(source.contains("protocol FirstUseGuidePresenting"), url.path)
            XCTAssertFalse(source.contains("extension FirstUseGuideStateStoring"), url.path)
            XCTAssertFalse(source.contains("extension FirstUseGuidePresenting"), url.path)
        }
        XCTAssertFalse(presentingSource.contains("assetCatalog"))
        XCTAssertFalse(try String(
            contentsOf: sourceRoot.appendingPathComponent("PointerAppKit/PointerApplicationController.swift"),
            encoding: .utf8
        ).contains("assetCatalog"))
    }
}
