import AppKit
import Foundation

public enum GuideAssetVariant: String, CaseIterable, Codable, Sendable {
    case light
    case dark
    case highContrast
}

public struct GuideAssetVariantDescriptor: Codable, Equatable, Sendable {
    public let variant: GuideAssetVariant
    public let assetIdentifier: String
    public let sourceSHA256: String

    public init(
        variant: GuideAssetVariant,
        assetIdentifier: String,
        sourceSHA256: String
    ) {
        self.variant = variant
        self.assetIdentifier = assetIdentifier
        self.sourceSHA256 = sourceSHA256
    }
}

public struct GuideAssetDescriptor: Codable, Equatable, Sendable {
    public let id: String
    public let accessibleName: String
    public let accessibleDescription: String
    public let isDecorative: Bool
    public let variants: [GuideAssetVariantDescriptor]

    public init(
        id: String,
        accessibleName: String,
        accessibleDescription: String,
        isDecorative: Bool,
        variants: [GuideAssetVariantDescriptor]
    ) {
        self.id = id
        self.accessibleName = accessibleName
        self.accessibleDescription = accessibleDescription
        self.isDecorative = isDecorative
        self.variants = variants
    }
}

public struct GuideAssetCatalogEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let catalogIdentifier: String
    public let entries: [GuideAssetDescriptor]

    public init(
        schemaVersion: Int,
        catalogIdentifier: String,
        entries: [GuideAssetDescriptor]
    ) {
        self.schemaVersion = schemaVersion
        self.catalogIdentifier = catalogIdentifier
        self.entries = entries
    }
}

public enum GuideAssetCatalogError: Error, Equatable, LocalizedError {
    case missingEntry(String)
    case missingVariant(identifier: String, variant: GuideAssetVariant)
    case invalidAssetIdentifier(String)
    case missingImage(path: String)

    public var errorDescription: String? {
        switch self {
        case let .missingEntry(identifier):
            return "Guide asset entry is missing: \(identifier)"
        case let .missingVariant(identifier, variant):
            return "Guide asset variant is missing: \(identifier) / \(variant.rawValue)"
        case let .invalidAssetIdentifier(identifier):
            return "Guide asset identifier is invalid: \(identifier)"
        case let .missingImage(path):
            return "Guide asset image is missing: \(path)"
        }
    }
}

@MainActor
public protocol GuideAssetCatalogProviding: AnyObject {
    var entries: [GuideAssetDescriptor] { get }
    func image(for identifier: String, variant: GuideAssetVariant) throws -> NSImage
}

public enum GuideAssetSourceMapping {
    public static func sourcePath(
        for assetIdentifier: String,
        variant: GuideAssetVariant
    ) -> String {
        "\(assetIdentifier)-\(variant.rawValue).png"
    }
}

@MainActor
public final class GuideAssetCatalog: GuideAssetCatalogProviding {
    public static let schemaVersion = 1
    public static let catalogIdentifier = "pointer.first-use-guide.v1"

    public let entries: [GuideAssetDescriptor]
    private let bundle: Bundle

    public init(envelope: GuideAssetCatalogEnvelope, bundle: Bundle) {
        entries = envelope.entries
        self.bundle = bundle
    }

    public func image(for identifier: String, variant: GuideAssetVariant) throws -> NSImage {
        guard let entry = entries.first(where: { $0.id == identifier }) else {
            throw GuideAssetCatalogError.missingEntry(identifier)
        }
        guard let variantDescriptor = entry.variants.first(where: { $0.variant == variant }) else {
            throw GuideAssetCatalogError.missingVariant(identifier: identifier, variant: variant)
        }
        let assetIdentifier = variantDescriptor.assetIdentifier
        guard isSafeAssetIdentifier(assetIdentifier) else {
            throw GuideAssetCatalogError.invalidAssetIdentifier(assetIdentifier)
        }
        let sourcePath = GuideAssetSourceMapping.sourcePath(
            for: assetIdentifier,
            variant: variant
        )
        guard let imageURL = bundle.url(
            forResource: sourcePath,
            withExtension: nil,
            subdirectory: "FirstUseGuide"
        ), let image = NSImage(contentsOf: imageURL) else {
            throw GuideAssetCatalogError.missingImage(path: sourcePath)
        }
        return image
    }

    private func isSafeAssetIdentifier(_ identifier: String) -> Bool {
        guard !identifier.isEmpty,
              !identifier.contains("/"),
              !identifier.contains("\\"),
              !identifier.contains("..") else {
            return false
        }
        return identifier.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (scalar == "-" || scalar == "." || scalar == "_"
                || scalar.properties.isAlphabetic || scalar.properties.numericType != nil)
        }
    }
}
