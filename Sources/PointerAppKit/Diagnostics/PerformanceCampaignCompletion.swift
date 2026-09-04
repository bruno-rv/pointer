import Foundation
import CryptoKit

/// The only aggregate completion artifact for the performance campaign. Each
/// comparison remains scoped to one fixture profile; this manifest links the
/// two independently accepted reports without combining their samples.
public struct PerformanceCampaignCompletionManifest: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let standard12ComparisonPath: String
    public let standard12ComparisonSHA256: String
    public let dense1000ComparisonPath: String
    public let dense1000ComparisonSHA256: String

    public init(
        schemaVersion: Int = PerformanceCampaignCompletionManifest.currentSchemaVersion,
        standard12ComparisonPath: String,
        standard12ComparisonSHA256: String,
        dense1000ComparisonPath: String,
        dense1000ComparisonSHA256: String
    ) {
        self.schemaVersion = schemaVersion
        self.standard12ComparisonPath = standard12ComparisonPath
        self.standard12ComparisonSHA256 = standard12ComparisonSHA256
        self.dense1000ComparisonPath = dense1000ComparisonPath
        self.dense1000ComparisonSHA256 = dense1000ComparisonSHA256
    }
}

public enum PerformanceCampaignCompletion {
    public static func load(from url: URL) throws -> PerformanceCampaignCompletionManifest {
        let repoRoot = try repoRoot(from: url)
        let data = try Data(contentsOf: url)
        let manifest = try PerformanceCanonicalJSON.decoded(PerformanceCampaignCompletionManifest.self, from: data)
        try validate(manifest: manifest, repoRoot: repoRoot)
        return manifest
    }

    public static func write(
        standard12ComparisonURL: URL,
        dense1000ComparisonURL: URL,
        outputURL: URL
    ) throws -> PerformanceCampaignCompletionManifest {
        try writeManifest(
            standard12ComparisonURL: standard12ComparisonURL,
            dense1000ComparisonURL: dense1000ComparisonURL,
            outputURL: outputURL
        )
    }

    public static func writeManifest(
        standard12ComparisonURL: URL,
        dense1000ComparisonURL: URL,
        outputURL: URL
    ) throws -> PerformanceCampaignCompletionManifest {
        let repoRoot = try repoRoot(from: outputURL)
        try validateComparisonPath(standard12ComparisonURL, profile: .standard12, repoRoot: repoRoot)
        try validateComparisonPath(dense1000ComparisonURL, profile: .dense1000, repoRoot: repoRoot)
        try validateSharedPerformanceRoot(
            standard12ComparisonURL: standard12ComparisonURL,
            dense1000ComparisonURL: dense1000ComparisonURL,
            outputURL: outputURL
        )
        try require(standard12ComparisonURL.standardizedFileURL.path != dense1000ComparisonURL.standardizedFileURL.path, "campaign completion paths must be distinct")
        let standardData = try Data(contentsOf: standard12ComparisonURL)
        let denseData = try Data(contentsOf: dense1000ComparisonURL)
        let manifest = PerformanceCampaignCompletionManifest(
            standard12ComparisonPath: relativeComparisonPath(for: .standard12),
            standard12ComparisonSHA256: sha256(standardData),
            dense1000ComparisonPath: relativeComparisonPath(for: .dense1000),
            dense1000ComparisonSHA256: sha256(denseData)
        )
        try validate(manifest: manifest, repoRoot: repoRoot)
        let data = try PerformanceCanonicalJSON.data(for: manifest)
        try writeIfNeeded(outputURL: outputURL, data: data)
        return manifest
    }

    public static func validate(manifest: PerformanceCampaignCompletionManifest) throws {
        try validate(
            manifest: manifest,
            repoRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        )
    }

    public static func validate(
        manifest: PerformanceCampaignCompletionManifest,
        repoRoot: URL
    ) throws {
        try require(
            manifest.schemaVersion == PerformanceCampaignCompletionManifest.currentSchemaVersion,
            "unsupported campaign completion manifest schemaVersion"
        )
        try require(
            manifest.standard12ComparisonPath != manifest.dense1000ComparisonPath,
            "campaign completion paths must be distinct"
        )
        try require(manifest.standard12ComparisonSHA256.isLowercaseHex(count: 64), "standard12 comparison hash is invalid")
        try require(manifest.dense1000ComparisonSHA256.isLowercaseHex(count: 64), "dense1000 comparison hash is invalid")
        let standardURL = try resolveComparisonPath(manifest.standard12ComparisonPath, profile: .standard12, repoRoot: repoRoot)
        let denseURL = try resolveComparisonPath(manifest.dense1000ComparisonPath, profile: .dense1000, repoRoot: repoRoot)
        let standard = try comparison(at: standardURL, expectedSHA256: manifest.standard12ComparisonSHA256)
        let dense = try comparison(at: denseURL, expectedSHA256: manifest.dense1000ComparisonSHA256)
        try require(standard.baselineFixture.fixtureProfile == .standard12 && standard.candidateFixture.fixtureProfile == .standard12, "standard12 completion path does not contain a standard12 comparison")
        try require(dense.baselineFixture.fixtureProfile == .dense1000 && dense.candidateFixture.fixtureProfile == .dense1000, "dense1000 completion path does not contain a dense1000 comparison")
        try require(standard.baselineFixture == standard.candidateFixture, "standard12 comparison fixtures do not match")
        try require(dense.baselineFixture == dense.candidateFixture, "dense1000 comparison fixtures do not match")
        try require(standard.baselineFixture.fixtureProfile != dense.baselineFixture.fixtureProfile, "campaign comparisons must remain profile-separated")
        try require(standard.baselineID == dense.baselineID, "campaign baseline identity differs across profiles")
        try require(standard.candidateID == dense.candidateID, "campaign candidate identity differs across profiles")
        try require(standard.baselineRunProvenance.host == dense.baselineRunProvenance.host, "campaign host identity differs across profiles")
        try require(standard.foundationIdentity == dense.foundationIdentity, "campaign foundation identity differs across profiles")
        try require(standard.harnessVersion == dense.harnessVersion, "campaign harness version differs across profiles")
        try require(standard.buildContractVersion == dense.buildContractVersion, "campaign build contract differs across profiles")
        try require(standard.baselineRunProvenance.sourceRef == dense.baselineRunProvenance.sourceRef, "campaign baseline run identity differs across profiles")
        try require(standard.candidateRunProvenance.sourceRef == dense.candidateRunProvenance.sourceRef, "campaign candidate run identity differs across profiles")
        try require(standard.baselineRunProvenance.build.sourceIdentity == dense.baselineRunProvenance.build.sourceIdentity, "campaign baseline build identity differs across profiles")
        try require(standard.candidateRunProvenance.build.sourceIdentity == dense.candidateRunProvenance.build.sourceIdentity, "campaign candidate build identity differs across profiles")
        try require(standard.baselineRunProvenance.acceptedFoundationArtifactSHA256 == dense.baselineRunProvenance.acceptedFoundationArtifactSHA256, "campaign foundation artifact differs across profiles")
        try validateCrossProfileLineage(standard: standard, dense: dense)
    }

    internal static func validateSharedPerformanceRoot(
        standard12ComparisonURL: URL,
        dense1000ComparisonURL: URL,
        outputURL: URL,
        outputDirectory: URL? = nil
    ) throws {
        let repoRoot = try repoRoot(from: outputURL)
        try validateComparisonPath(standard12ComparisonURL, profile: .standard12, repoRoot: repoRoot)
        try validateComparisonPath(dense1000ComparisonURL, profile: .dense1000, repoRoot: repoRoot)
        if let outputDirectory {
            try require(physicalPath(outputDirectory) == physicalPath(repoRoot), "campaign outputDirectory does not match the repository root")
        }
    }

    private static func validateCrossProfileLineage(
        standard: PerformanceComparisonReport,
        dense: PerformanceComparisonReport
    ) throws {
        try require(lineageBuild(standard.baselineBuildProvenance) == lineageBuild(dense.baselineBuildProvenance), "campaign baseline build lineage differs across profiles")
        try require(lineageBuild(standard.candidateBuildProvenance) == lineageBuild(dense.candidateBuildProvenance), "campaign candidate build lineage differs across profiles")
        try require(standard.baselineMeasurementIdentity == dense.baselineMeasurementIdentity, "campaign baseline measurement environment differs across profiles")
        try require(standard.candidateMeasurementIdentity == dense.candidateMeasurementIdentity, "campaign candidate measurement environment differs across profiles")
        try require(standard.baselineRunProvenance.sourceRef == dense.baselineRunProvenance.sourceRef, "campaign baseline source commit differs across profiles")
        try require(standard.candidateRunProvenance.sourceRef == dense.candidateRunProvenance.sourceRef, "campaign candidate source commit differs across profiles")
        try require(standard.baselineRunProvenance.host == dense.baselineRunProvenance.host, "campaign baseline host differs across profiles")
        try require(standard.candidateRunProvenance.host == dense.candidateRunProvenance.host, "campaign candidate host differs across profiles")
        try require(standard.baselineRunProvenance.foundationProvenancePath == dense.baselineRunProvenance.foundationProvenancePath, "campaign baseline foundation path differs across profiles")
        try require(standard.candidateRunProvenance.foundationProvenancePath == dense.candidateRunProvenance.foundationProvenancePath, "campaign candidate foundation path differs across profiles")
        try require(standard.pairEligibility.foundationProvenance == dense.pairEligibility.foundationProvenance, "campaign foundation provenance differs across profiles")
        try require(configurationLineage(standard.baselineRunProvenance.configuration) == configurationLineage(dense.baselineRunProvenance.configuration), "campaign baseline configuration differs across profiles")
        try require(configurationLineage(standard.candidateRunProvenance.configuration) == configurationLineage(dense.candidateRunProvenance.configuration), "campaign candidate configuration differs across profiles")
        try require(fixtureLineage(standard.baselineFixture) == fixtureLineage(dense.baselineFixture), "campaign baseline fixture contract differs across profiles")
        try require(fixtureLineage(standard.candidateFixture) == fixtureLineage(dense.candidateFixture), "campaign candidate fixture contract differs across profiles")
    }

    private struct BuildLineage: Equatable {
        let sourceTreeStatus: SourceTreeStatus
        let sourceIdentity: SourceIdentity
        let sourceManifestSHA256: String
        let executableSHA256: String
        let bundleManifestSHA256: String
        let buildConfiguration: String
        let foundation: FoundationIdentity
        let harnessVersion: String
        let buildContractVersion: String
        let acceptedFoundationArtifactSHA256: String?
    }

    private static func lineageBuild(_ build: BuildProvenance) -> BuildLineage {
        BuildLineage(
            sourceTreeStatus: build.sourceTreeStatus,
            sourceIdentity: build.sourceIdentity,
            sourceManifestSHA256: build.sourceManifestSHA256,
            executableSHA256: build.executableSHA256,
            bundleManifestSHA256: build.bundleManifestSHA256,
            buildConfiguration: build.buildConfiguration,
            foundation: build.foundation,
            harnessVersion: build.harnessVersion,
            buildContractVersion: build.buildContractVersion,
            acceptedFoundationArtifactSHA256: build.acceptedFoundationArtifactSHA256
        )
    }

    private struct ConfigurationLineage: Equatable {
        let samplesPerGesture: Int
        let warmupCount: Int
        let trialCount: Int
        let pairsPerOrder: Int
        let bootstrapSeed: UInt64
        let bootstrapResamples: Int
        let memoryWindowSeconds: Int
        let memorySampleIntervalSeconds: Int
        let harnessVersion: String
        let foundationIdentity: FoundationIdentity
        let buildContractVersion: String
    }

    private static func configurationLineage(_ configuration: PerformanceConfiguration) -> ConfigurationLineage {
        ConfigurationLineage(
            samplesPerGesture: configuration.samplesPerGesture,
            warmupCount: configuration.warmupCount,
            trialCount: configuration.trialCount,
            pairsPerOrder: configuration.pairsPerOrder,
            bootstrapSeed: configuration.bootstrapSeed,
            bootstrapResamples: configuration.bootstrapResamples,
            memoryWindowSeconds: configuration.memoryWindowSeconds,
            memorySampleIntervalSeconds: configuration.memorySampleIntervalSeconds,
            harnessVersion: configuration.harnessVersion,
            foundationIdentity: configuration.foundationIdentity,
            buildContractVersion: configuration.buildContractVersion
        )
    }

    private struct FixtureLineage: Equatable {
        let continuationSamples: Int
        let warmupCount: Int
        let trialCount: Int
        let seed: UInt64
    }

    private static func fixtureLineage(_ fixture: FixtureIdentity) -> FixtureLineage {
        FixtureLineage(
            continuationSamples: fixture.continuationSamples,
            warmupCount: fixture.warmupCount,
            trialCount: fixture.trialCount,
            seed: fixture.seed
        )
    }

    private static func physicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func repoRoot(from outputURL: URL) throws -> URL {
        try validateRawPath(outputURL)
        let canonical = outputURL.standardizedFileURL
        let components = canonical.pathComponents
        let codexIndices = components.indices.filter { components[$0] == ".codex" }
        try require(codexIndices.count == 1, "campaign output must contain one .codex component")
        guard let codexIndex = codexIndices.first, codexIndex > 1 else {
            throw PerformanceValidationError.invalid("campaign output must be nested under a repository root")
        }
        try validatePath(canonical, suffix: [".codex", "sdd", "reports", "quality-campaign", "performance", "campaign-completion", "manifest.json"])
        var root = URL(fileURLWithPath: "/", isDirectory: true)
        for component in components.dropFirst().prefix(codexIndex - 1) {
            root.appendPathComponent(component)
        }
        return root.standardizedFileURL
    }

    private static func relativeComparisonPath(for profile: PerformanceFixtureProfile) -> String {
        ".codex/sdd/reports/quality-campaign/performance/\(profile.rawValue)/comparisons/paired-comparison.json"
    }

    private static func resolveComparisonPath(
        _ relativePath: String,
        profile: PerformanceFixtureProfile,
        repoRoot: URL
    ) throws -> URL {
        try require(relativePath == relativeComparisonPath(for: profile), "campaign comparison path is not the canonical repository-relative path")
        let url = repoRoot.appendingPathComponent(relativePath).standardizedFileURL
        try validateComparisonPath(url, profile: profile, repoRoot: repoRoot)
        return url
    }

    private static func validateComparisonPath(
        _ url: URL,
        profile: PerformanceFixtureProfile,
        repoRoot: URL
    ) throws {
        let expected = repoRoot.appendingPathComponent(relativeComparisonPath(for: profile)).standardizedFileURL
        try require(url.standardizedFileURL.path == expected.path, "campaign comparison path is not under the repository performance root")
        try validatePath(url, suffix: [profile.rawValue, "comparisons", "paired-comparison.json"])
    }

    private static func comparison(at url: URL, expectedSHA256: String) throws -> PerformanceComparisonReport {
        try require(url.path.hasSuffix("/comparisons/paired-comparison.json"), "campaign completion comparison path is required")
        try require(FileManager.default.fileExists(atPath: url.path), "campaign completion comparison is missing")
        let data = try Data(contentsOf: url)
        try require(sha256(data) == expectedSHA256, "campaign completion comparison hash mismatch")
        let report = try JSONDecoder().decode(PerformanceComparisonReport.self, from: data)
        try require(data == PerformanceCanonicalJSON.data(for: report), "campaign completion comparison is not canonical")
        try report.validateCompletion()
        return report
    }

    private static func validatePath(_ url: URL, suffix: [String]) throws {
        try validateRawPath(url)
        try require(Array(url.standardizedFileURL.pathComponents.suffix(suffix.count)) == suffix, "campaign completion path is not canonical")
    }

    private static func validateRawPath(_ url: URL) throws {
        try require(url.isFileURL && url.query == nil && url.fragment == nil, "campaign completion path must be a file URL without query or fragment")
        let raw = String(url.absoluteString.dropFirst("file://".count)).removingPercentEncoding ?? url.path
        try require(raw.hasPrefix("/") && raw.count > 1, "campaign completion path must be absolute")
        try require(!raw.hasPrefix("//") && !raw.hasSuffix("/") && !raw.contains("//"), "campaign completion path is not canonically spelled")
        let components = raw.split(separator: "/", omittingEmptySubsequences: false)
        try require(components.dropFirst().allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }, "campaign completion path contains a traversal or dot component")
        try require(URL(fileURLWithPath: raw).path == raw, "campaign completion path is not canonically spelled")
        var current = URL(fileURLWithPath: "/")
        for component in components.dropFirst() {
            current.appendPathComponent(String(component))
            guard FileManager.default.fileExists(atPath: current.path) else { continue }
            let attributes = try FileManager.default.attributesOfItem(atPath: current.path)
            let systemAlias = current.path == "/var" || current.path == "/tmp"
            try require(systemAlias || attributes[.type] as? FileAttributeType != .typeSymbolicLink, "campaign completion path uses a symbolic link")
        }
    }

    private static func writeIfNeeded(outputURL: URL, data: Data) throws {
        let parent = outputURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            let existing = try Data(contentsOf: outputURL)
            try require(existing == data, "campaign completion manifest conflicts with existing bytes")
            return
        }
        try data.write(to: outputURL, options: .atomic)
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw PerformanceValidationError.invalid(message)
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    func isLowercaseHex(count: Int) -> Bool {
        guard self.count == count else { return false }
        return unicodeScalars.allSatisfy {
            CharacterSet(charactersIn: "0123456789abcdef").contains($0)
        }
    }
}
