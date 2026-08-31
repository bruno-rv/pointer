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
        let viewSource = try String(
            contentsOf: helpRoot.appendingPathComponent("FirstUseGuideViewController.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(viewSource.contains("public let variant"))
        let catalogSource = try String(
            contentsOf: helpRoot.appendingPathComponent("GuideAssetCatalog.swift"),
            encoding: .utf8
        )
        XCTAssertEqual(
            catalogSource.components(separatedBy: "image(forResource: resourceName)").count - 1,
            1
        )
        XCTAssertEqual(
            catalogSource.components(separatedBy: "let resourceName = String(sourcePath.dropLast(\".png\".count))").count - 1,
            1
        )
        XCTAssertTrue(catalogSource.contains("GuideAssetSourceMapping.sourcePath"))
        XCTAssertFalse(catalogSource.contains("bundle.url"))
        XCTAssertFalse(catalogSource.contains("bundle.path"))
        XCTAssertFalse(catalogSource.contains("NSImage(contentsOf"))
        XCTAssertFalse(catalogSource.contains("Bundle.main"))
        XCTAssertFalse(catalogSource.contains("NSImage(named"))
    }

    func testPlacementPlanUsesRightLeftTopBottomAndClampedCandidatesWithoutOverlap() throws {
        let display = DisplayFrame(x: 0, y: 0, width: 1_000, height: 800)
        let panel = DisplayFrame(x: 0, y: 0, width: 200, height: 160)
        let fixture = FirstUseGuideTestFixture()
        let makeContext: (DisplayFrame, [DisplayFrame]) -> GuidePlacementContext = { palette, avoidance in
            GuidePlacementContext(
                display: fixture.display,
                visibleFrame: display,
                paletteFrame: palette,
                avoidanceFrames: avoidance
            )
        }

        let right = FirstUseGuidePlacementPlan.frame(
            size: panel,
            in: makeContext(DisplayFrame(x: 100, y: 300, width: 200, height: 120), [])
        )
        let rightFrame = try XCTUnwrap(right)
        XCTAssertEqual(rightFrame.x, 316, accuracy: 0.001)
        XCTAssertEqual(rightFrame.y, 300, accuracy: 0.001)

        let left = FirstUseGuidePlacementPlan.frame(
            size: panel,
            in: makeContext(
                DisplayFrame(x: 700, y: 300, width: 200, height: 120),
                [DisplayFrame(x: 916, y: 300, width: 84, height: 160)]
            )
        )
        let leftFrame = try XCTUnwrap(left)
        XCTAssertEqual(leftFrame.x, 484, accuracy: 0.001)

        let top = FirstUseGuidePlacementPlan.frame(
            size: panel,
            in: makeContext(
                DisplayFrame(x: 400, y: 40, width: 200, height: 120),
                [DisplayFrame(x: 184, y: 40, width: 200, height: 160), DisplayFrame(x: 616, y: 40, width: 200, height: 160)]
            )
        )
        let topFrame = try XCTUnwrap(top)
        XCTAssertEqual(topFrame.y, 640, accuracy: 0.001)

        let clamped = FirstUseGuidePlacementPlan.frame(
            size: panel,
            in: makeContext(DisplayFrame(x: 900, y: 700, width: 200, height: 120), [])
        )
        let clampedFrame = try XCTUnwrap(clamped)
        XCTAssertLessThanOrEqual(clampedFrame.x + clampedFrame.width, display.x + display.width)
        XCTAssertLessThanOrEqual(clampedFrame.y + clampedFrame.height, display.y + display.height)

        let bottom = FirstUseGuidePlacementPlan.frame(
            size: panel,
            in: makeContext(
                DisplayFrame(x: 400, y: 600, width: 200, height: 120),
                [DisplayFrame(x: 184, y: 600, width: 200, height: 160), DisplayFrame(x: 616, y: 600, width: 200, height: 160)]
            )
        )
        let bottomFrame = try XCTUnwrap(bottom)
        XCTAssertEqual(bottomFrame.y, 0, accuracy: 0.001)
    }

    func testPlacementPlanReturnsNilWhenNoLegalFrameFitsAndControllerKeepsPanelHidden() {
        let display = DisplayFrame(x: 0, y: 0, width: 500, height: 400)
        let palette = DisplayFrame(x: 0, y: 0, width: 500, height: 400)
        let context = GuidePlacementContext(
            display: FirstUseGuideTestFixture.defaultDisplay,
            visibleFrame: display,
            paletteFrame: palette,
            avoidanceFrames: [palette]
        )
        XCTAssertNil(FirstUseGuidePlacementPlan.frame(
            size: DisplayFrame(x: 0, y: 0, width: 200, height: 160),
            in: context
        ))
        let invalidFrames = GuidePlacementContext(
            display: FirstUseGuideTestFixture.defaultDisplay,
            visibleFrame: display,
            paletteFrame: DisplayFrame(x: 0, y: 0, width: 0, height: 400),
            avoidanceFrames: []
        )
        XCTAssertNil(FirstUseGuidePlacementPlan.frame(
            size: DisplayFrame(x: 0, y: 0, width: 200, height: 160),
            in: invalidFrames
        ))

        let fixture = FirstUseGuideTestFixture()
        fixture.panel.becomesVisibleOnShow = false
        XCTAssertEqual(
            fixture.controller.showIfNeeded(in: fixture.context),
            .failed("Guide window did not become visible")
        )
        XCTAssertFalse(fixture.controller.isVisible)
        XCTAssertEqual(fixture.stateStore.markCount, 0)

        let invalidContext = GuidePlacementContext(
            display: fixture.display,
            visibleFrame: DisplayFrame(x: 0, y: 0, width: 0, height: 400),
            paletteFrame: fixture.context.paletteFrame,
            avoidanceFrames: []
        )
        XCTAssertEqual(
            fixture.controller.show(in: invalidContext),
            .failed("Guide placement context is invalid")
        )
    }

    func testAppearanceProviderSelectsDarkAndHighContrastBeforePreflight() {
        let dark = FirstUseGuideTestFixture(appearanceVariant: .dark)
        XCTAssertEqual(dark.controller.show(in: dark.context), .shown)
        XCTAssertEqual(Set(dark.catalog.imageRequests.map(\.1)), [.dark])

        let contrast = FirstUseGuideTestFixture(appearanceVariant: .highContrast)
        XCTAssertEqual(contrast.controller.show(in: contrast.context), .shown)
        XCTAssertEqual(Set(contrast.catalog.imageRequests.map(\.1)), [.highContrast])
    }

    func testAppearanceReloadUsesSelectedVariantAndRetainsImagesOnFailure() {
        let fixture = FirstUseGuideTestFixture()
        let viewController = FirstUseGuideViewController(
            assetCatalog: fixture.catalog,
            appearanceProvider: fixture.appearanceProvider
        )
        viewController.loadViewIfNeeded()
        XCTAssertEqual(fixture.catalog.imageRequests.count, 8)

        fixture.appearanceProvider.variant = .dark
        XCTAssertTrue(viewController.reloadImagesForCurrentAppearance())
        XCTAssertEqual(Set(fixture.catalog.imageRequests.suffix(8).map(\.1)), [.dark])
        let imageBeforeFailure = viewController.exampleImageViews.first?.image

        fixture.appearanceProvider.variant = .highContrast
        fixture.catalog.imageError = GuideAssetCatalogError.missingEntry("arrow")
        fixture.catalog.failingVariants = [.highContrast]
        XCTAssertFalse(viewController.reloadImagesForCurrentAppearance())
        XCTAssertTrue(viewController.exampleImageViews.first?.image === imageBeforeFailure)
    }

    func testReshowRetainedLoadedPanelAppliesDarkImagesWithoutMovingFrameOrFocus() throws {
        let fixture = FirstUseGuideTestFixture()
        XCTAssertEqual(fixture.controller.show(in: fixture.context), .shown)
        XCTAssertTrue(fixture.panel.isVisible)

        let viewController = try XCTUnwrap(fixture.panel.viewController)
        let lightImages = viewController.exampleImageViews.compactMap(\.image)
        let frameBeforeReshow = viewController.view.frame
        let focusBeforeReshow = viewController.accessibilityOrderLabels
        XCTAssertEqual(lightImages.count, FirstUseGuideViewController.examples.count)

        fixture.controller.dismiss()
        fixture.appearanceProvider.variant = .dark
        fixture.catalog.resetImageRequests()

        XCTAssertEqual(fixture.controller.show(in: fixture.context), .shown)
        XCTAssertTrue(fixture.panel.isVisible)
        let darkImages = viewController.exampleImageViews.compactMap(\.image)
        let expectedDarkImages = Dictionary(
            uniqueKeysWithValues: fixture.catalog.providedImages
                .filter { $0.1 == .dark }
                .map { ($0.0, $0.2) }
        )

        XCTAssertEqual(darkImages.count, FirstUseGuideViewController.examples.count)
        for (index, example) in FirstUseGuideViewController.examples.enumerated() {
            let expected = try XCTUnwrap(expectedDarkImages[example.assetIdentifier])
            let actual = try XCTUnwrap(viewController.exampleImageViews[index].image)
            XCTAssertTrue(actual === expected, example.assetIdentifier)
            XCTAssertFalse(actual === lightImages[index], example.assetIdentifier)
        }
        XCTAssertEqual(viewController.view.frame, frameBeforeReshow)
        XCTAssertEqual(viewController.accessibilityOrderLabels, focusBeforeReshow)
    }

    func testMissingOrEmptyCatalogMetadataFailsWithoutAccessibleFallback() {
        let fixture = FirstUseGuideTestFixture()
        let invalidArrow = GuideAssetDescriptor(
            id: "arrow",
            accessibleName: "",
            accessibleDescription: "",
            isDecorative: true,
            variants: fixture.catalog.entries[0].variants
        )
        let catalog = FirstUseGuideTestCatalog(
            entries: [invalidArrow] + fixture.catalog.entries.dropFirst()
        )
        let controller = FirstUseGuideController(
            stateStore: fixture.stateStore,
            placementProvider: fixture.placementProvider,
            assetCatalog: catalog,
            appearanceProvider: fixture.appearanceProvider,
            panelFactory: { _ in fixture.panel }
        )

        guard case let .failed(message) = controller.show(in: fixture.context) else {
            return XCTFail("Expected invalid metadata to fail presentation")
        }
        XCTAssertTrue(message.contains("arrow"))
        XCTAssertTrue(catalog.imageRequests.isEmpty)
    }

    func testCatalogEnvelopeRejectsSchemaIdentityDuplicatesVariantsHashesAndMetadata() throws {
        let fixture = FirstUseGuideTestFixture()
        let validEntries = fixture.catalog.entries
        let bundle = Bundle(for: FirstUseGuideTests.self)

        XCTAssertThrowsError(try GuideAssetCatalog(
            envelope: GuideAssetCatalogEnvelope(
                schemaVersion: 2,
                catalogIdentifier: GuideAssetCatalog.catalogIdentifier,
                entries: validEntries
            ),
            bundle: bundle
        )) { error in
            XCTAssertEqual(error as? GuideAssetCatalogError, .invalidSchemaVersion(expected: 1, actual: 2))
        }

        XCTAssertThrowsError(try GuideAssetCatalog(
            envelope: GuideAssetCatalogEnvelope(
                schemaVersion: 1,
                catalogIdentifier: "wrong",
                entries: validEntries
            ),
            bundle: bundle
        )) { error in
            XCTAssertEqual(error as? GuideAssetCatalogError, .invalidCatalogIdentifier(expected: GuideAssetCatalog.catalogIdentifier, actual: "wrong"))
        }

        XCTAssertThrowsError(try GuideAssetCatalog(
            envelope: GuideAssetCatalogEnvelope(
                schemaVersion: 1,
                catalogIdentifier: GuideAssetCatalog.catalogIdentifier,
                entries: validEntries + [validEntries[0]]
            ),
            bundle: bundle
        )) { error in
            XCTAssertEqual(error as? GuideAssetCatalogError, .duplicateEntry("arrow"))
        }

        var missingVariant = validEntries[0]
        missingVariant = GuideAssetDescriptor(
            id: missingVariant.id,
            accessibleName: missingVariant.accessibleName,
            accessibleDescription: missingVariant.accessibleDescription,
            isDecorative: false,
            variants: Array(missingVariant.variants.dropLast())
        )
        XCTAssertThrowsError(try GuideAssetCatalog(
            envelope: GuideAssetCatalogEnvelope(
                schemaVersion: 1,
                catalogIdentifier: GuideAssetCatalog.catalogIdentifier,
                entries: [missingVariant] + validEntries.dropFirst()
            ),
            bundle: bundle
        )) { error in
            XCTAssertEqual(
                error as? GuideAssetCatalogError,
                .missingVariant(identifier: "arrow", variant: .highContrast)
            )
        }

        let duplicateVariant = GuideAssetDescriptor(
            id: validEntries[0].id,
            accessibleName: validEntries[0].accessibleName,
            accessibleDescription: validEntries[0].accessibleDescription,
            isDecorative: false,
            variants: validEntries[0].variants + [validEntries[0].variants[0]]
        )
        XCTAssertThrowsError(try GuideAssetCatalog(
            envelope: GuideAssetCatalogEnvelope(
                schemaVersion: 1,
                catalogIdentifier: GuideAssetCatalog.catalogIdentifier,
                entries: [duplicateVariant] + validEntries.dropFirst()
            ),
            bundle: bundle
        )) { error in
            XCTAssertEqual(
                error as? GuideAssetCatalogError,
                .duplicateVariant(identifier: "arrow", variant: .light)
            )
        }

        let invalidHash = GuideAssetDescriptor(
            id: validEntries[0].id,
            accessibleName: validEntries[0].accessibleName,
            accessibleDescription: validEntries[0].accessibleDescription,
            isDecorative: false,
            variants: validEntries[0].variants.map {
                GuideAssetVariantDescriptor(
                    variant: $0.variant,
                    assetIdentifier: $0.assetIdentifier,
                    sourceSHA256: "NOT-A-HASH"
                )
            }
        )
        XCTAssertThrowsError(try GuideAssetCatalog(
            envelope: GuideAssetCatalogEnvelope(
                schemaVersion: 1,
                catalogIdentifier: GuideAssetCatalog.catalogIdentifier,
                entries: [invalidHash] + validEntries.dropFirst()
            ),
            bundle: bundle
        )) { error in
            XCTAssertEqual(
                error as? GuideAssetCatalogError,
                .invalidHash(identifier: "arrow", variant: .light, value: "NOT-A-HASH")
            )
        }

        let unsafeIdentifier = GuideAssetDescriptor(
            id: validEntries[0].id,
            accessibleName: validEntries[0].accessibleName,
            accessibleDescription: validEntries[0].accessibleDescription,
            isDecorative: false,
            variants: validEntries[0].variants.map {
                GuideAssetVariantDescriptor(
                    variant: $0.variant,
                    assetIdentifier: "../arrow",
                    sourceSHA256: $0.sourceSHA256
                )
            }
        )
        XCTAssertThrowsError(try GuideAssetCatalog(
            envelope: GuideAssetCatalogEnvelope(
                schemaVersion: 1,
                catalogIdentifier: GuideAssetCatalog.catalogIdentifier,
                entries: [unsafeIdentifier] + validEntries.dropFirst()
            ),
            bundle: bundle
        )) { error in
            XCTAssertEqual(error as? GuideAssetCatalogError, .invalidAssetIdentifier("../arrow"))
        }

        let invalidMetadata = GuideAssetDescriptor(
            id: validEntries[0].id,
            accessibleName: " ",
            accessibleDescription: "",
            isDecorative: true,
            variants: validEntries[0].variants
        )
        XCTAssertThrowsError(try GuideAssetCatalog(
            envelope: GuideAssetCatalogEnvelope(
                schemaVersion: 1,
                catalogIdentifier: GuideAssetCatalog.catalogIdentifier,
                entries: [invalidMetadata] + validEntries.dropFirst()
            ),
            bundle: bundle
        )) { error in
            XCTAssertEqual(error as? GuideAssetCatalogError, .invalidMetadata("arrow"))
        }
    }

    func testGuideLayoutUsesScrollableContentAndDeterministicAccessibleChildrenOrder() {
        let fixture = FirstUseGuideTestFixture()
        let viewController = FirstUseGuideViewController(assetCatalog: fixture.catalog)
        viewController.loadViewIfNeeded()

        XCTAssertNotNil(viewController.scrollView)
        XCTAssertTrue(viewController.scrollView?.hasVerticalScroller == true)
        XCTAssertEqual(viewController.exampleImageViews.count, 8)
        XCTAssertEqual(viewController.doneButton?.accessibilityLabel(), "Done")
        XCTAssertTrue(viewController.accessibilityOrderLabels.first == "Learn Pointer")
        XCTAssertEqual(viewController.accessibilityOrderLabels.last, "Done")
        let exampleNames = viewController.accessibilityOrderLabels
            .dropFirst(2)
            .dropLast()
            .enumerated()
            .filter { $0.offset.isMultiple(of: 3) }
            .map(\.element)
        XCTAssertEqual(exampleNames.count, 8)
    }

    func testWorkspaceCenterNotificationReloadsHighContrastAndDefaultCenterDoesNot() {
        let fixture = FirstUseGuideTestFixture()
        let viewController = FirstUseGuideViewController(
            assetCatalog: fixture.catalog,
            appearanceProvider: fixture.appearanceProvider
        )
        viewController.loadViewIfNeeded()
        fixture.catalog.resetImageRequests()
        viewController.startAppearanceObservation()

        fixture.appearanceProvider.variant = .highContrast
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        XCTAssertEqual(fixture.catalog.imageRequests.count, 8)
        XCTAssertEqual(Set(fixture.catalog.imageRequests.map(\.1)), [.highContrast])

        fixture.catalog.resetImageRequests()
        fixture.appearanceProvider.variant = .dark
        NotificationCenter.default.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
        XCTAssertTrue(fixture.catalog.imageRequests.isEmpty)
        viewController.stopAppearanceObservation()
    }

    func testEffectiveAppearanceUpdatesSemanticBackgroundWithoutMovingFrameOrFocus() {
        let fixture = FirstUseGuideTestFixture()
        let viewController = FirstUseGuideViewController(assetCatalog: fixture.catalog)
        viewController.loadViewIfNeeded()
        viewController.view.setFrameSize(NSSize(width: 320, height: 360))
        viewController.view.layoutSubtreeIfNeeded()
        viewController.view.appearance = NSAppearance(named: .aqua)
        viewController.refreshSemanticAppearance()
        let beforeFrame = viewController.view.frame
        let beforeFocus = viewController.accessibilityOrderLabels
        let beforeBackground = viewController.view.layer?.backgroundColor

        viewController.view.appearance = NSAppearance(named: .darkAqua)
        viewController.refreshSemanticAppearance()
        let afterBackground = viewController.view.layer?.backgroundColor

        XCTAssertNotEqual(beforeBackground?.components, afterBackground?.components)
        XCTAssertEqual(viewController.view.frame, beforeFrame)
        XCTAssertEqual(viewController.accessibilityOrderLabels, beforeFocus)
    }

    func testNarrowGuideKeepsTitleExplanationScrollAndDoneInside320To360Height() {
        let fixture = FirstUseGuideTestFixture()
        let viewController = FirstUseGuideViewController(assetCatalog: fixture.catalog)
        viewController.loadViewIfNeeded()
        for height in [320.0, 360.0] {
            viewController.view.setFrameSize(NSSize(width: 320, height: height))
            viewController.view.layoutSubtreeIfNeeded()
            for element in [
                viewController.titleLabel,
                viewController.explanationLabel,
                viewController.scrollView,
                viewController.doneButton,
            ].compactMap({ $0 }) {
                XCTAssertGreaterThanOrEqual(element.frame.minY, -0.5)
                XCTAssertLessThanOrEqual(element.frame.maxY, height + 0.5)
            }
        }
    }
}
