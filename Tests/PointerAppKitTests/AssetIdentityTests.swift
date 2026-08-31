import AppKit
import CryptoKit
import Foundation
import ImageIO
import XCTest
@testable import PointerAppKit

@MainActor
final class AssetIdentityTests: XCTestCase {
    private struct AppIconSlot {
        let logicalWidth: Int
        let logicalHeight: Int
        let scale: Int
    }

    private static let guideIdentifiers = [
        "arrow", "rectangle", "ellipse", "pen", "spotlight", "emoji", "select", "eraser",
    ]

    private static let appIconSlots: [String: AppIconSlot] = [
        "icon-16-1x.png": AppIconSlot(logicalWidth: 16, logicalHeight: 16, scale: 1),
        "icon-16-2x.png": AppIconSlot(logicalWidth: 16, logicalHeight: 16, scale: 2),
        "icon-32-1x.png": AppIconSlot(logicalWidth: 32, logicalHeight: 32, scale: 1),
        "icon-32-2x.png": AppIconSlot(logicalWidth: 32, logicalHeight: 32, scale: 2),
        "icon-128-1x.png": AppIconSlot(logicalWidth: 128, logicalHeight: 128, scale: 1),
        "icon-128-2x.png": AppIconSlot(logicalWidth: 128, logicalHeight: 128, scale: 2),
        "icon-256-1x.png": AppIconSlot(logicalWidth: 256, logicalHeight: 256, scale: 1),
        "icon-256-2x.png": AppIconSlot(logicalWidth: 256, logicalHeight: 256, scale: 2),
        "icon-512.png": AppIconSlot(logicalWidth: 512, logicalHeight: 512, scale: 1),
        "icon-512-2x.png": AppIconSlot(logicalWidth: 512, logicalHeight: 512, scale: 2),
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
        let markerX = try XCTUnwrap(coordinate["x"] as? Int)
        let markerY = try XCTUnwrap(coordinate["y"] as? Int)
        XCTAssertEqual(markerX, 256)
        XCTAssertEqual(markerY, 256)
        let rgba = try XCTUnwrap(marker["rgba"] as? [Int])
        guard rgba.count == 4, rgba.allSatisfy({ (0...255).contains($0) }) else {
            XCTFail("marker RGBA must contain four byte values")
            return
        }
        XCTAssertEqual(rgba, [252, 127, 83, 253])

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
        XCTAssertEqual(iconImages.count, Self.appIconSlots.count)
        let iconFilenames = try iconImages.map { try XCTUnwrap($0["filename"] as? String) }
        XCTAssertEqual(Set(iconFilenames), expectedSourceNames)
        XCTAssertEqual(iconFilenames.count, Set(iconFilenames).count)
        for image in iconImages {
            XCTAssertEqual(Set(image.keys), ["filename", "idiom", "scale", "size"])
            let filename = try XCTUnwrap(image["filename"] as? String)
            let slot = try XCTUnwrap(Self.appIconSlots[filename], filename)
            XCTAssertEqual(image["idiom"] as? String, "mac", filename)
            XCTAssertEqual(image["scale"] as? String, "\(slot.scale)x", filename)
            XCTAssertEqual(
                image["size"] as? String,
                "\(slot.logicalWidth)x\(slot.logicalHeight)",
                filename
            )
            let imageURL = iconRoot.appendingPathComponent(filename)
            let physicalImage = try imageProperties(at: imageURL)
            XCTAssertEqual(physicalImage.width, slot.logicalWidth * slot.scale, filename)
            XCTAssertEqual(physicalImage.height, slot.logicalHeight * slot.scale, filename)
        }
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
            XCTAssertTrue(image.isStraightAlpha)
            XCTAssertTrue(image.isSRGB)
        }

        let canonicalImage = try decodedImage(at: iconRoot.appendingPathComponent("icon-512.png"))
        XCTAssertEqual(canonicalImage.width, 512)
        XCTAssertEqual(canonicalImage.height, 512)
        XCTAssertEqual(canonicalImage.bitsPerComponent, 8)
        XCTAssertEqual(canonicalImage.bitsPerPixel, 32)
        XCTAssertEqual(canonicalImage.alphaInfo, .last)
        XCTAssertEqual(canonicalImage.colorSpace?.name as String?, CGColorSpace.sRGB as String)

        let normalized = try normalizedRGBA8(at: iconRoot.appendingPathComponent("icon-512.png"))
        let normalizedDigest = sha256(of: normalized)
        let expectedDigest = try XCTUnwrap(manifest["expectedResolvedDigest"] as? String)
        XCTAssertEqual(expectedDigest, "dc9bb4ae78701a0d79004050eb062b836f1aa7623ad13c0b09b45d5a6dd59068")
        XCTAssertEqual(normalizedDigest, expectedDigest)
        guard (0..<512).contains(markerX), (0..<512).contains(markerY) else {
            XCTFail("marker coordinate must be inside canonical 512x512 image")
            return
        }
        let markerOffset = (markerY * 512 + markerX) * 4
        XCTAssertEqual(Array(normalized[markerOffset..<(markerOffset + 4)]), rgba.map(UInt8.init))
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
            let image = try XCTUnwrap(images.first, imagesetName)
            XCTAssertEqual(Set(image.keys), ["filename", "idiom", "scale"], imagesetName)
            let filenames = images.compactMap { $0["filename"] as? String }
            XCTAssertEqual(filenames.count, 1, imagesetName)
            let components = imagesetName
                .dropLast(".imageset".count)
                .split(separator: "-", maxSplits: 1)
            guard components.count == 2 else {
                XCTFail("imageset name must encode identifier and variant: \(imagesetName)")
                continue
            }
            let identifier = String(components[0])
            guard let variant = GuideAssetVariant(rawValue: String(components[1])) else {
                XCTFail("imageset name has unknown guide variant: \(imagesetName)")
                continue
            }
            let expectedFilename = GuideAssetSourceMapping.sourcePath(
                for: identifier,
                variant: variant
            )
            XCTAssertEqual(image["filename"] as? String, expectedFilename, imagesetName)
            XCTAssertEqual(image["idiom"] as? String, "universal", imagesetName)
            XCTAssertEqual(image["scale"] as? String, "1x", imagesetName)
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: imagesetURL.appendingPathComponent(expectedFilename).path
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
            let hashes = entry.variants.map(\.sourceSHA256)
            XCTAssertEqual(hashes.count, Set(hashes).count, entry.id)
            for variant in entry.variants {
                XCTAssertEqual(variant.assetIdentifier, entry.id, entry.id)
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

    func testAssetManifestsContainNoNetworkReferences() throws {
        let bundleRoot = repositoryRoot.appendingPathComponent("Bundle")
        let jsonURLs = try XCTUnwrap(FileManager.default.subpaths(atPath: bundleRoot.path))
            .map(bundleRoot.appendingPathComponent)
            .filter { $0.pathExtension == "json" }
        XCTAssertTrue(jsonURLs.contains { $0.lastPathComponent == "AppIconIdentity.json" })
        XCTAssertTrue(jsonURLs.contains { $0.lastPathComponent == "GuideAssetIdentity.json" })
        XCTAssertTrue(jsonURLs.contains { $0.lastPathComponent == "Contents.json" })
        for url in jsonURLs {
            let contents = try String(contentsOf: url, encoding: .utf8)
            XCTAssertNil(contents.range(of: #"(?i)https?://"#, options: .regularExpression), url.path)
        }
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
        try sha256(of: Data(contentsOf: url))
    }

    private func sha256(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func decodedImage(at url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil), url.path)
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), url.path)
    }

    private func normalizedRGBA8(at url: URL) throws -> Data {
        let image = try decodedImage(at: url)
        XCTAssertEqual(image.width, 512, url.path)
        XCTAssertEqual(image.height, 512, url.path)
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var premultiplied = [UInt8](repeating: 0, count: 512 * 512 * 4)
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
            | CGImageAlphaInfo.premultipliedLast.rawValue
        let context = try XCTUnwrap(CGContext(
            data: &premultiplied,
            width: 512,
            height: 512,
            bitsPerComponent: 8,
            bytesPerRow: 512 * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ))
        context.interpolationQuality = .none
        context.setShouldAntialias(false)
        context.draw(image, in: CGRect(x: 0, y: 0, width: 512, height: 512))

        // Use integer round-to-nearest unpremultiplication and canonicalize RGB
        // to zero for transparent pixels before hashing row-major RGBA bytes.
        var straight = [UInt8](repeating: 0, count: premultiplied.count)
        for offset in stride(from: 0, to: premultiplied.count, by: 4) {
            let alpha = Int(premultiplied[offset + 3])
            straight[offset + 3] = UInt8(alpha)
            guard alpha > 0 else { continue }
            straight[offset] = UInt8(min(255, (Int(premultiplied[offset]) * 255 + alpha / 2) / alpha))
            straight[offset + 1] = UInt8(min(255, (Int(premultiplied[offset + 1]) * 255 + alpha / 2) / alpha))
            straight[offset + 2] = UInt8(min(255, (Int(premultiplied[offset + 2]) * 255 + alpha / 2) / alpha))
        }
        return Data(straight)
    }

    private func imageProperties(at url: URL) throws -> (
        width: Int,
        height: Int,
        hasAlpha: Bool,
        isStraightAlpha: Bool,
        isSRGB: Bool
    ) {
        let image = try decodedImage(at: url)
        let alphaInfo = image.alphaInfo
        let hasAlpha = alphaInfo != .none && alphaInfo != .noneSkipFirst && alphaInfo != .noneSkipLast
        let isStraightAlpha = alphaInfo == .first || alphaInfo == .last
        let colorSpaceName = image.colorSpace?.name as String?
        return (
            image.width,
            image.height,
            hasAlpha,
            isStraightAlpha,
            colorSpaceName == (CGColorSpace.sRGB as String)
        )
    }
}
