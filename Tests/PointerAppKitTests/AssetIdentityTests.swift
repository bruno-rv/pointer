import AppKit
import CryptoKit
import Foundation
import ImageIO
import XCTest
@testable import PointerAppKit

@MainActor
final class AssetIdentityTests: XCTestCase {
    private static let guideIdentifiers = [
        "arrow", "rectangle", "ellipse", "pen", "spotlight", "emoji", "select", "eraser",
    ]

    func testAppIconIdentityNamesExactAssetAndRasterPolicy() throws {
        let manifest = try jsonObject(at: repositoryRoot.appendingPathComponent("Bundle/AppIconIdentity.json"))
        XCTAssertEqual(Set(manifest.keys), [
            "name", "sourceFiles", "canonicalDimensions", "colorSpace", "alphaPolicy",
            "markerPixel", "expectedResolvedDigest",
        ])
        XCTAssertEqual(manifest["name"] as? String, "AppIcon")
        XCTAssertEqual(manifest["colorSpace"] as? String, "sRGB IEC 61966-2.1")
        XCTAssertEqual(manifest["alphaPolicy"] as? String, "straight")
        XCTAssertEqual(
            manifest["expectedResolvedDigest"] as? String,
            "dc9bb4ae78701a0d79004050eb062b836f1aa7623ad13c0b09b45d5a6dd59068"
        )

        let dimensions = try dictionary(manifest["canonicalDimensions"], key: "canonicalDimensions")
        XCTAssertEqual(dimensions["width"] as? Int, 512)
        XCTAssertEqual(dimensions["height"] as? Int, 512)

        let marker = try dictionary(manifest["markerPixel"], key: "markerPixel")
        let coordinate = try dictionary(marker["coordinate"], key: "markerPixel.coordinate")
        XCTAssertEqual(coordinate["x"] as? Int, 256)
        XCTAssertEqual(coordinate["y"] as? Int, 256)
        let rgba = try XCTUnwrap(marker["rgba"] as? [Int])
        XCTAssertEqual(rgba.count, 4)
        XCTAssertTrue(rgba.allSatisfy { (0...255).contains($0) })

        let sourceFiles = try XCTUnwrap(manifest["sourceFiles"] as? [[String: Any]])
        let expectedSourceNames: Set<String> = [
            "icon-16-1x.png", "icon-16-2x.png", "icon-32-1x.png", "icon-32-2x.png",
            "icon-128-1x.png", "icon-128-2x.png", "icon-256-1x.png", "icon-256-2x.png",
            "icon-512.png", "icon-512-2x.png",
        ]
        XCTAssertEqual(Set(sourceFiles.compactMap { $0["path"] as? String }), expectedSourceNames)
        let iconRoot = repositoryRoot.appendingPathComponent("Bundle/Assets.xcassets/AppIcon.appiconset")
        let iconContents = try jsonObject(at: iconRoot.appendingPathComponent("Contents.json"))
        XCTAssertEqual(Set(iconContents.keys), ["images", "info"])
        let iconImages = try XCTUnwrap(iconContents["images"] as? [[String: Any]])
        XCTAssertEqual(iconImages.count, expectedSourceNames.count)
        XCTAssertEqual(Set(iconImages.compactMap { $0["filename"] as? String }), expectedSourceNames)
        XCTAssertEqual(iconImages.compactMap { $0["filename"] as? String }.count, expectedSourceNames.count)
        let trackedSourceNames = Set(
            (try FileManager.default.subpathsOfDirectory(atPath: iconRoot.path))
                .filter { $0.hasSuffix(".png") }
        )
        XCTAssertEqual(trackedSourceNames, expectedSourceNames)
        for source in sourceFiles {
            XCTAssertEqual(Set(source.keys), ["path", "sha256", "dimensions"])
            let path = try XCTUnwrap(source["path"] as? String)
            let imageURL = repositoryRoot
                .appendingPathComponent("Bundle/Assets.xcassets/AppIcon.appiconset")
                .appendingPathComponent(path)
            let sourceDimensions = try dictionary(source["dimensions"], key: "source dimensions")
            XCTAssertEqual(try sha256(of: imageURL), source["sha256"] as? String)
            let image = try imageProperties(at: imageURL)
            XCTAssertEqual(sourceDimensions["width"] as? Int, image.width)
            XCTAssertEqual(sourceDimensions["height"] as? Int, image.height)
            XCTAssertTrue(image.hasAlpha)
            XCTAssertTrue(image.isSRGB)
        }
    }

    func testGuideAssetsHaveCanonicalIdentifiersAndTrackedFiles() throws {
        let manifestURL = repositoryRoot.appendingPathComponent("Bundle/GuideAssetIdentity.json")
        let manifest = try jsonObject(at: manifestURL)
        XCTAssertEqual(Set(manifest.keys), ["schemaVersion", "catalogIdentifier", "entries"])
        XCTAssertEqual(manifest["schemaVersion"] as? Int, GuideAssetCatalog.schemaVersion)
        XCTAssertEqual(manifest["catalogIdentifier"] as? String, GuideAssetCatalog.catalogIdentifier)

        let envelope = try JSONDecoder().decode(
            GuideAssetCatalogEnvelope.self,
            from: Data(contentsOf: manifestURL)
        )
        XCTAssertEqual(envelope.entries.map(\.id), Self.guideIdentifiers)

        let guideRoot = repositoryRoot.appendingPathComponent("Bundle/Assets.xcassets/FirstUseGuide")
        let trackedPaths = try FileManager.default.subpathsOfDirectory(atPath: guideRoot.path)
        let expectedImagesetNames = Set(Self.guideIdentifiers.flatMap { identifier in
            GuideAssetVariant.allCases.map { "\(identifier)-\($0.rawValue).imageset" }
        })
        let imagesetNames = Set(trackedPaths.filter { $0.hasSuffix(".imageset") })
        XCTAssertEqual(imagesetNames, expectedImagesetNames)
        for imagesetName in imagesetNames {
            let imagesetURL = guideRoot.appendingPathComponent(imagesetName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: imagesetURL.appendingPathComponent("Contents.json").path))
            let contents = try jsonObject(at: imagesetURL.appendingPathComponent("Contents.json"))
            XCTAssertEqual(Set(contents.keys), ["images", "info"], imagesetName)
            let images = try XCTUnwrap(contents["images"] as? [[String: Any]])
            XCTAssertEqual(images.count, 1, imagesetName)
            let filenames = images.compactMap { $0["filename"] as? String }
            XCTAssertEqual(filenames.count, 1, imagesetName)
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: imagesetURL.appendingPathComponent(filenames[0]).path
            ), imagesetName)
        }
        XCTAssertFalse(trackedPaths.contains { $0.lowercased().hasSuffix(".svg") })
        let pngURLs = trackedPaths
            .filter { $0.hasSuffix(".png") }
            .map { guideRoot.appendingPathComponent($0) }
        XCTAssertEqual(pngURLs.count, Self.guideIdentifiers.count * GuideAssetVariant.allCases.count)

        var expectedPaths = Set<String>()
        for entry in envelope.entries {
            XCTAssertFalse(entry.accessibleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(entry.accessibleDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertFalse(entry.isDecorative)
            XCTAssertEqual(Set(entry.variants.map(\.variant)), Set(GuideAssetVariant.allCases))
            XCTAssertEqual(entry.variants.count, GuideAssetVariant.allCases.count)
            for variant in entry.variants {
                let sourcePath = GuideAssetSourceMapping.sourcePath(
                    for: variant.assetIdentifier,
                    variant: variant.variant
                )
                let matches = pngURLs.filter { $0.lastPathComponent == sourcePath }
                XCTAssertEqual(matches.count, 1, sourcePath)
                let imageURL = try XCTUnwrap(matches.first)
                expectedPaths.insert(imageURL.path)
                XCTAssertEqual(try sha256(of: imageURL), variant.sourceSHA256, sourcePath)
                let image = try imageProperties(at: imageURL)
                XCTAssertEqual(image.width, 512, sourcePath)
                XCTAssertEqual(image.height, 512, sourcePath)
                XCTAssertTrue(image.isSRGB, sourcePath)
            }
        }
        XCTAssertEqual(Set(pngURLs.map(\.path)), expectedPaths)
    }

    func testEveryGuideExampleResolvesItsMappedRasterThroughInjectedCatalog() throws {
        let manifestURL = repositoryRoot.appendingPathComponent("Bundle/GuideAssetIdentity.json")
        let envelope = try JSONDecoder().decode(
            GuideAssetCatalogEnvelope.self,
            from: Data(contentsOf: manifestURL)
        )
        let sourceRoot = repositoryRoot.appendingPathComponent("Bundle/Assets.xcassets/FirstUseGuide")
        let temporaryBundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PointerGuideAssets-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: temporaryBundleURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryBundleURL) }
        try Data("<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict></dict></plist>".utf8)
            .write(to: temporaryBundleURL.appendingPathComponent("Info.plist"))

        for entry in envelope.entries {
            for variant in entry.variants {
                let sourcePath = GuideAssetSourceMapping.sourcePath(
                    for: variant.assetIdentifier,
                    variant: variant.variant
                )
                let sourceURL = try XCTUnwrap(
                    FileManager.default
                        .subpaths(atPath: sourceRoot.path)?
                        .map(sourceRoot.appendingPathComponent)
                        .first { $0.lastPathComponent == sourcePath }
                )
                try FileManager.default.copyItem(
                    at: sourceURL,
                    to: temporaryBundleURL.appendingPathComponent(sourcePath)
                )
            }
        }

        let bundle = try XCTUnwrap(Bundle(url: temporaryBundleURL))
        let catalog = try GuideAssetCatalog(envelope: envelope, bundle: bundle)
        for entry in envelope.entries {
            for variant in entry.variants {
                let image = try catalog.image(for: entry.id, variant: variant.variant)
                XCTAssertEqual(image.representations.first?.pixelsWide, 512, entry.id)
                XCTAssertEqual(image.representations.first?.pixelsHigh, 512, entry.id)
            }
        }
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func jsonObject(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func dictionary(_ value: Any?, key: String) throws -> [String: Any] {
        try XCTUnwrap(value as? [String: Any], key)
    }

    private func sha256(of url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func imageProperties(at url: URL) throws -> (width: Int, height: Int, hasAlpha: Bool, isSRGB: Bool) {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), url.path)
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), url.path)
        let alphaInfo = image.alphaInfo
        let hasAlpha = alphaInfo != .none && alphaInfo != .noneSkipFirst && alphaInfo != .noneSkipLast
        let colorSpaceName = image.colorSpace?.name as String?
        return (
            image.width,
            image.height,
            hasAlpha,
            colorSpaceName == (CGColorSpace.sRGB as String)
        )
    }
}
