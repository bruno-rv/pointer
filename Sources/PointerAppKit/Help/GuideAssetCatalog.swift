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
    case invalidSchemaVersion(expected: Int, actual: Int)
    case invalidCatalogIdentifier(expected: String, actual: String)
    case duplicateEntry(String)
    case invalidMetadata(String)
    case duplicateVariant(identifier: String, variant: GuideAssetVariant)
    case missingEntry(String)
    case missingVariant(identifier: String, variant: GuideAssetVariant)
    case invalidHash(identifier: String, variant: GuideAssetVariant, value: String)
    case invalidAssetIdentifier(String)
    case missingImage(path: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidSchemaVersion(expected, actual):
            return "Guide asset catalog schema version must be \(expected), got \(actual)"
        case let .invalidCatalogIdentifier(expected, actual):
            return "Guide asset catalog identifier must be \(expected), got \(actual)"
        case let .duplicateEntry(identifier):
            return "Guide asset entry is duplicated: \(identifier)"
        case let .invalidMetadata(identifier):
            return "Guide asset metadata is invalid: \(identifier)"
        case let .duplicateVariant(identifier, variant):
            return "Guide asset variant is duplicated: \(identifier) / \(variant.rawValue)"
        case let .missingEntry(identifier):
            return "Guide asset entry is missing: \(identifier)"
        case let .missingVariant(identifier, variant):
            return "Guide asset variant is missing: \(identifier) / \(variant.rawValue)"
        case let .invalidHash(identifier, variant, value):
            return "Guide asset hash is invalid: \(identifier) / \(variant.rawValue) / \(value)"
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
    public static let requiredAssetIdentifiers = [
        "arrow", "rectangle", "ellipse", "pen", "spotlight", "emoji", "select", "eraser",
    ]

    public let entries: [GuideAssetDescriptor]
    private let bundle: Bundle

    public init(envelope: GuideAssetCatalogEnvelope, bundle: Bundle) throws {
        try Self.validate(envelope: envelope)
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
        guard Self.isSafeAssetIdentifier(assetIdentifier) else {
            throw GuideAssetCatalogError.invalidAssetIdentifier(assetIdentifier)
        }
        let sourcePath = GuideAssetSourceMapping.sourcePath(
            for: assetIdentifier,
            variant: variant
        )
        let resourceName = String(sourcePath.dropLast(".png".count))
        guard let image = bundle.image(forResource: resourceName) else {
            throw GuideAssetCatalogError.missingImage(path: sourcePath)
        }
        return image
    }

    static func validateRequiredEntries(_ entries: [GuideAssetDescriptor]) throws {
        var identifiers = Set<String>()
        for entry in entries {
            guard identifiers.insert(entry.id).inserted else {
                throw GuideAssetCatalogError.duplicateEntry(entry.id)
            }
        }
        for identifier in requiredAssetIdentifiers {
            guard let entry = entries.first(where: { $0.id == identifier }) else {
                throw GuideAssetCatalogError.missingEntry(identifier)
            }
            guard !entry.accessibleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !entry.accessibleDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !entry.isDecorative else {
                throw GuideAssetCatalogError.invalidMetadata(identifier)
            }
            var variants = Set<GuideAssetVariant>()
            for descriptor in entry.variants {
                guard variants.insert(descriptor.variant).inserted else {
                    throw GuideAssetCatalogError.duplicateVariant(
                        identifier: identifier,
                        variant: descriptor.variant
                    )
                }
                guard isSafeAssetIdentifier(descriptor.assetIdentifier) else {
                    throw GuideAssetCatalogError.invalidAssetIdentifier(
                        descriptor.assetIdentifier
                    )
                }
                guard isLowercaseSHA256(descriptor.sourceSHA256) else {
                    throw GuideAssetCatalogError.invalidHash(
                        identifier: identifier,
                        variant: descriptor.variant,
                        value: descriptor.sourceSHA256
                    )
                }
            }
            for variant in GuideAssetVariant.allCases where !variants.contains(variant) {
                throw GuideAssetCatalogError.missingVariant(
                    identifier: identifier,
                    variant: variant
                )
            }
        }
    }

    private static func validate(envelope: GuideAssetCatalogEnvelope) throws {
        guard envelope.schemaVersion == schemaVersion else {
            throw GuideAssetCatalogError.invalidSchemaVersion(
                expected: schemaVersion,
                actual: envelope.schemaVersion
            )
        }
        guard envelope.catalogIdentifier == catalogIdentifier else {
            throw GuideAssetCatalogError.invalidCatalogIdentifier(
                expected: catalogIdentifier,
                actual: envelope.catalogIdentifier
            )
        }

        var identifiers = Set<String>()
        for entry in envelope.entries {
            guard !entry.id.isEmpty,
                  identifiers.insert(entry.id).inserted else {
                throw GuideAssetCatalogError.duplicateEntry(entry.id)
            }
            var variants = Set<GuideAssetVariant>()
            for descriptor in entry.variants {
                guard variants.insert(descriptor.variant).inserted else {
                    throw GuideAssetCatalogError.duplicateVariant(
                        identifier: entry.id,
                        variant: descriptor.variant
                    )
                }
                guard isSafeAssetIdentifier(descriptor.assetIdentifier) else {
                    throw GuideAssetCatalogError.invalidAssetIdentifier(descriptor.assetIdentifier)
                }
                guard isLowercaseSHA256(descriptor.sourceSHA256) else {
                    throw GuideAssetCatalogError.invalidHash(identifier: entry.id, variant: descriptor.variant, value: descriptor.sourceSHA256)
                }
            }
            for variant in GuideAssetVariant.allCases where !variants.contains(variant) {
                throw GuideAssetCatalogError.missingVariant(
                    identifier: entry.id,
                    variant: variant
                )
            }
        }
        for identifier in requiredAssetIdentifiers where !identifiers.contains(identifier) {
            throw GuideAssetCatalogError.missingEntry(identifier)
        }
        try validateRequiredEntries(envelope.entries)
    }

    static func isSafeAssetIdentifier(_ identifier: String) -> Bool {
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

    private static func isLowercaseSHA256(_ value: String) -> Bool {
        guard value.count == 64 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (scalar.value >= 48 && scalar.value <= 57
                || scalar.value >= 97 && scalar.value <= 102)
        }
    }
}
