import Foundation
import XCTest
@testable import PointerAppKit

@MainActor
final class PerformanceComparisonHarnessTests: XCTestCase {
    func testComparisonPublicSurfaceIsEnforcedBySymbolGraphAndExternalModuleCompile() throws {
        let moduleDirectory = try pointerAppKitModuleDirectory()
        let sdkPath = try macOSSDKPath()
        let publicSymbolGraph = try extractPublicSymbolGraph(moduleDirectory: moduleDirectory, sdkPath: sdkPath)
        assertPublicSurfaceSymbolGraph(publicSymbolGraph)
        let sanitySource = """
        import Foundation
        import PointerAppKit
        let knownPublicUnit: PerformanceMetricUnit = .milliseconds
        _ = knownPublicUnit
        """
        let sanityResult = try compileExternal(sanitySource, moduleDirectory: moduleDirectory, sdkPath: sdkPath)
        assertExternalSuccess(sanityResult, context: "known public symbol")

        let exactWriter = """
        import Foundation
        import PointerAppKit

        @MainActor
        func probe() {
            let writer: (PerformanceComparisonDraft, URL, URL, URL, URL, URL, PerformanceConfiguration, PerformancePairEligibility) throws -> PerformanceComparisonReport = PerformanceComparisonHarness.writeComparison
            _ = writer
        }
        """
        let writerResult = try compileExternal(exactWriter, moduleDirectory: moduleDirectory, sdkPath: sdkPath)
        assertExternalSuccess(writerResult, context: "exact public writer signature")

        let draftProperties = [
            "harnessVersion",
            "foundationIdentity",
            "buildContractVersion",
            "baselineBuildProvenance",
            "candidateBuildProvenance",
            "baselineRunProvenance",
            "candidateRunProvenance",
            "pairEligibility",
            "pairExecutionArtifact",
            "pairExecutionArtifactSHA256",
            "baselineFixture",
            "candidateFixture",
            "baselineMeasurementIdentity",
            "candidateMeasurementIdentity",
            "baselineID",
            "candidateID",
            "metrics",
            "resilience",
            "seed",
            "resampleCount",
            "disposition"
        ]
        XCTAssertEqual(draftProperties.count, Set(draftProperties).count, "Draft property probe list must not contain duplicates")

        let draftPropertySurfaces = draftProperties.map { property in
            ("draft property \(property)", """
            import PointerAppKit
            func inspect(_ draft: PerformanceComparisonDraft) {
                _ = draft.\(property)
            }
            """)
        }
        let forbiddenSurfaces = [
            ("preflight", """
            import PointerAppKit
            @MainActor
            func probe() {
                let value = PerformanceComparisonHarness.preflight
                _ = value
            }
            """),
            ("compare", """
            import PointerAppKit
            @MainActor
            func probe() {
                let value = PerformanceComparisonHarness.compare
                _ = value
            }
            """),
            ("draft initializer", """
            import PointerAppKit
            let draft = PerformanceComparisonDraft()
            _ = draft
            """),
            ("legacy writer overload", """
            import Foundation
            import PointerAppKit
            @MainActor
            func legacyWriter(_ draft: PerformanceComparisonDraft, _ baseline: URL, _ candidate: URL, _ output: URL, _ configuration: PerformanceConfiguration, _ eligibility: PerformancePairEligibility) throws -> PerformanceComparisonReport {
                try PerformanceComparisonHarness.writeComparison(draft: draft, baselineURL: baseline, candidateURL: candidate, outputDirectory: output, configuration: configuration, eligibility: eligibility)
            }
            """),
            ("legacy writer missing pair artifact", """
            import Foundation
            import PointerAppKit
            @MainActor
            func legacyWriter(_ draft: PerformanceComparisonDraft, _ baseline: URL, _ candidate: URL, _ manual: URL, _ output: URL, _ configuration: PerformanceConfiguration, _ eligibility: PerformancePairEligibility) throws -> PerformanceComparisonReport {
                try PerformanceComparisonHarness.writeComparison(draft: draft, baselineURL: baseline, candidateURL: candidate, manualEvidenceDirectory: manual, outputDirectory: output, configuration: configuration, eligibility: eligibility)
            }
            """),
            ("legacy writer missing manual evidence", """
            import Foundation
            import PointerAppKit
            @MainActor
            func legacyWriter(_ draft: PerformanceComparisonDraft, _ baseline: URL, _ candidate: URL, _ pair: URL, _ output: URL, _ configuration: PerformanceConfiguration, _ eligibility: PerformancePairEligibility) throws -> PerformanceComparisonReport {
                try PerformanceComparisonHarness.writeComparison(draft: draft, baselineURL: baseline, candidateURL: candidate, pairExecutionURL: pair, outputDirectory: output, configuration: configuration, eligibility: eligibility)
            }
            """)
        ] + draftPropertySurfaces

        for (surface, source) in forbiddenSurfaces {
            let result = try compileExternal(source, moduleDirectory: moduleDirectory, sdkPath: sdkPath)
            XCTAssertNotEqual(result.status, 0, "\(surface) unexpectedly compiled:\n\(result.output)")
            let diagnostics = result.output.lowercased()
            XCTAssertFalse(diagnostics.contains("no such module") || diagnostics.contains("cannot find type") || diagnostics.contains("failed to load"), "\(surface) failed for module/toolchain resolution instead of the expected API check:\n\(result.output)")
            let expectedMarkers = surface.hasPrefix("legacy writer")
                ? ["missing argument", "no exact matches", "incorrect argument labels", "extraneous argument"]
                : ["inaccessible", "internal", "has no member"]
            XCTAssertTrue(expectedMarkers.contains { diagnostics.contains($0) }, "\(surface) produced an unexpected diagnostic:\n\(result.output)")
        }
    }

    func testComparisonRejectsCrossProfilePairWhileMatchingDenseReportsRemainIndependent() throws {
        let denseConfiguration = PerformanceConfiguration.dense1000
        let denseFixture = FixtureIdentity(
            identifier: PerformanceFixtureProfile.dense1000.identifier,
            fixtureProfile: .dense1000,
            fixtureVersion: PerformanceFixtureProfile.dense1000.version,
            markCount: denseConfiguration.fixtureMarkCount,
            continuationSamples: denseConfiguration.samplesPerGesture,
            warmupCount: denseConfiguration.warmupCount,
            trialCount: denseConfiguration.trialCount,
            seed: PerformanceFixtures.fixture.seed
        )
        let denseBaselineRun = PerformanceRunProvenance(
            variant: "baseline",
            outputRoot: "build/dense1000/baseline",
            sourceRef: PerformanceFixtures.baselineCommit,
            build: PerformanceFixtures.baselineBuild,
            host: PerformanceFixtures.host,
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            configuration: denseConfiguration,
            foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: denseConfiguration.harnessVersion,
            buildContractVersion: denseConfiguration.buildContractVersion,
            acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
        )
        let denseCandidateRun = PerformanceRunProvenance(
            variant: "candidate",
            outputRoot: "build/dense1000/candidate",
            sourceRef: PerformanceFixtures.commit,
            build: PerformanceFixtures.build,
            host: PerformanceFixtures.host,
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            configuration: denseConfiguration,
            foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: denseConfiguration.harnessVersion,
            buildContractVersion: denseConfiguration.buildContractVersion,
            acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
        )
        let denseBaseline = PerformanceFixtures.report(identity: PerformanceFixtures.baselineIdentity, build: PerformanceFixtures.baselineBuild, run: denseBaselineRun, fixture: denseFixture)
        let denseCandidate = PerformanceFixtures.report(run: denseCandidateRun, fixture: denseFixture)

        XCTAssertNoThrow(try denseBaseline.validateCompletion())
        XCTAssertNoThrow(try denseCandidate.validateCompletion())
        XCTAssertEqual(denseBaseline.fixture.fixtureProfile, .dense1000)
        XCTAssertEqual(denseCandidate.fixture.fixtureProfile, .dense1000)
        XCTAssertEqual(denseBaseline.runProvenance.configuration, denseConfiguration)
        XCTAssertEqual(denseCandidate.runProvenance.configuration, denseConfiguration)
        XCTAssertEqual(denseBaseline.fixture, denseCandidate.fixture)
        XCTAssertEqual(denseBaseline.renderer.frameMilliseconds.count, 30)
        XCTAssertEqual(denseCandidate.renderer.frameMilliseconds.count, 30)

        let denseEligibility = PerformancePairEligibility(
            baselineRoot: denseBaselineRun.outputRoot,
            candidateRoot: denseCandidateRun.outputRoot,
            baselineCommitSHA: PerformanceFixtures.baselineCommit,
            candidateCommitSHA: PerformanceFixtures.commit,
            foundationProvenance: PerformanceFixtures.foundationProvenance
        )
        XCTAssertNoThrow(try PerformanceComparisonHarness.preflight(
            baseline: denseBaseline,
            candidate: denseCandidate,
            configuration: denseConfiguration,
            eligibility: denseEligibility
        ))

        XCTAssertEqual(denseCandidate.host, PerformanceFixtures.candidate.host)
        XCTAssertEqual(denseCandidate.identity.sourceCommitSHA, PerformanceFixtures.candidate.identity.sourceCommitSHA)
        XCTAssertEqual(denseCandidate.renderer.frameMilliseconds.count, PerformanceFixtures.candidate.renderer.frameMilliseconds.count)
        let denseBaselineReportHash = PerformanceFixtures.sha256(try JSONEncoder().encode(denseBaseline))
        let denseCandidateReportHash = PerformanceFixtures.sha256(try JSONEncoder().encode(denseCandidate))
        let densePairArtifact = PerformancePairExecutionArtifact(
            baselineID: denseBaseline.identity.sourceCommitSHA!,
            candidateID: denseCandidate.identity.sourceCommitSHA!,
            baselineMeasurementReportSHA256: denseBaselineReportHash,
            candidateMeasurementReportSHA256: denseCandidateReportHash,
            records: PerformanceFixtures.executionArtifact.records
        )
        XCTAssertEqual(densePairArtifact.baselineMeasurementReportSHA256, denseBaselineReportHash)
        XCTAssertEqual(densePairArtifact.candidateMeasurementReportSHA256, denseCandidateReportHash)
        XCTAssertNoThrow(try densePairArtifact.validate(
            expectedBaselineID: denseBaseline.identity.sourceCommitSHA!,
            expectedCandidateID: denseCandidate.identity.sourceCommitSHA!,
            expectedBaselineReportHash: denseBaselineReportHash,
            expectedCandidateReportHash: denseCandidateReportHash,
            expectedArtifactHash: PerformanceFixtures.sha256(try PerformancePairExecutionArtifact.canonicalData(for: densePairArtifact)),
            pairCount: denseConfiguration.totalPairs
        ))

        let densePairArtifactHash = PerformanceFixtures.sha256(try PerformancePairExecutionArtifact.canonicalData(for: densePairArtifact))
        let manualDirectory = try makeManualEvidenceDirectory()
        defer { try? FileManager.default.removeItem(at: manualDirectory) }
        let denseDraft = try PerformanceComparisonHarness.compare(
            baseline: denseBaseline,
            candidate: denseCandidate,
            configuration: denseConfiguration,
            eligibility: denseEligibility,
            pairExecutionArtifact: densePairArtifact,
            manualEvidenceDirectory: manualDirectory,
            pairExecutionArtifactSHA256: densePairArtifactHash,
            baselineMeasurementReportSHA256: denseBaselineReportHash,
            candidateMeasurementReportSHA256: denseCandidateReportHash
        )
        let denseComparison = PerformanceComparisonReport(
            draft: denseDraft,
            baselineMeasurementReportSHA256: denseBaselineReportHash,
            candidateMeasurementReportSHA256: denseCandidateReportHash
        )
        try denseComparison.validateStructure()

        func tamperedDenseComparison(_ mutate: (inout [String: Any]) -> Void) throws -> PerformanceComparisonReport {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(denseComparison)) as? [String: Any])
            var baselineObject = try XCTUnwrap(object["baselineFixture"] as? [String: Any])
            var candidateObject = try XCTUnwrap(object["candidateFixture"] as? [String: Any])
            mutate(&baselineObject)
            mutate(&candidateObject)
            object["baselineFixture"] = baselineObject
            object["candidateFixture"] = candidateObject
            let data = try JSONSerialization.data(withJSONObject: object)
            return try JSONDecoder().decode(PerformanceComparisonReport.self, from: data)
        }
        let fixtureTamperCases: [(String, (inout [String: Any]) -> Void)] = [
            ("profile", { fixture in fixture["fixtureProfile"] = "standard12" }),
            ("version", { fixture in fixture["fixtureVersion"] = "pointer-fixture-forged/v1" }),
            ("identifier", { fixture in fixture["identifier"] = "pointer-standard-12-marks" }),
            ("mark count", { fixture in fixture["markCount"] = 12 })
        ]
        for (label, mutate) in fixtureTamperCases {
            let tampered = try tamperedDenseComparison(mutate)
            XCTAssertEqual(tampered.baselineFixture, tampered.candidateFixture, "\(label) tamper should preserve pair equality")
            XCTAssertThrowsError(try tampered.validateStructure(), "Persisted dense comparison accepted forged \(label)")
        }

        var crossProfileError: Error?
        XCTAssertThrowsError(try PerformanceComparisonHarness.preflight(baseline: PerformanceFixtures.baseline, candidate: denseCandidate, configuration: PerformanceConfiguration.standard, eligibility: PerformanceFixtures.eligibility)) {
            crossProfileError = $0
        }
        guard let crossProfileError else {
            return XCTFail("Expected cross-profile comparison preflight to reject the pair")
        }
        XCTAssertTrue(String(describing: crossProfileError).contains("fixture mismatch"), "Expected the profile-bound fixture gate, got: \(crossProfileError)")
    }

    func testComparisonRoundTripsEntireReportAndValidatesCompletion() throws {
        let report = PerformanceFixtures.comparison()
        try report.validateStructure()
        try report.validateCompletion()

        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(PerformanceComparisonReport.self, from: data)

        XCTAssertEqual(decoded, report)
        XCTAssertEqual(decoded.reportKind, .comparison)
        XCTAssertEqual(decoded.metrics.count, PerformanceMetricID.allCases.count)
        XCTAssertEqual(decoded.pairEligibility, PerformanceFixtures.eligibility)
        XCTAssertEqual(decoded.pairExecutionArtifact, PerformanceFixtures.executionArtifact)
        XCTAssertEqual(decoded.pairExecutionArtifactSHA256, PerformanceFixtures.executionArtifactSHA256)
        XCTAssertEqual(decoded.baselineFixture, PerformanceFixtures.fixture)
        XCTAssertEqual(decoded.candidateFixture, PerformanceFixtures.fixture)
        XCTAssertEqual(decoded.baselineMeasurementIdentity, PerformanceFixtures.baselineIdentity)
        XCTAssertEqual(decoded.candidateMeasurementIdentity, PerformanceFixtures.identity)
        XCTAssertEqual(decoded.baselineMeasurementReportSHA256, PerformanceFixtures.baselineMeasurementReportSHA256)
        XCTAssertEqual(decoded.candidateMeasurementReportSHA256, PerformanceFixtures.candidateMeasurementReportSHA256)
        XCTAssertEqual(decoded.baselineRunProvenance, PerformanceFixtures.baselineRun)
        XCTAssertEqual(decoded.candidateRunProvenance, PerformanceFixtures.run)
    }

    func testComparisonRejectsWrongOrMissingKind() throws {
        var wrongKindObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PerformanceFixtures.comparison())) as! [String: Any]
        wrongKindObject["reportKind"] = "measurement"
        let wrongKindData = try JSONSerialization.data(withJSONObject: wrongKindObject)
        let wrongKind = try JSONDecoder().decode(PerformanceComparisonReport.self, from: wrongKindData)
        XCTAssertThrowsError(try wrongKind.validateStructure())

        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PerformanceFixtures.comparison())) as! [String: Any]
        object.removeValue(forKey: "reportKind")
        let missingKindData = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try JSONDecoder().decode(PerformanceComparisonReport.self, from: missingKindData))
    }

    func testComparisonRejectsDuplicateOrMissingMetricIDs() throws {
        var duplicate = PerformanceFixtures.comparison().metrics
        duplicate[1] = duplicate[0]
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: duplicate).validateStructure())

        var missing = PerformanceFixtures.comparison().metrics
        missing.removeLast()
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: missing).validateStructure())
    }

    func testComparisonRejectsHostFixtureVersionAndProvenanceMismatches() throws {
        let mismatchedHost = HostIdentity(machineIdentifier: "other-machine", processArchitecture: "arm64", connectedDisplayUUIDs: ["fixture-display"])
        let hostBuild = PerformanceFixtures.baselineBuild
        let hostRun = PerformanceRunProvenance(variant: "baseline", outputRoot: "build/baseline", sourceRef: PerformanceFixtures.baselineCommit, build: hostBuild, host: mismatchedHost, recordedAtUTC: PerformanceFixtures.recordedAtUTC, configuration: PerformanceFixtures.configuration, foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath, foundation: PerformanceFixtures.foundation, harnessVersion: PerformanceFixtures.configuration.harnessVersion, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(baselineRun: hostRun).validateStructure())

        let mismatchedConfig = PerformanceConfiguration(fixtureMarkCount: 13, samplesPerGesture: 240, warmupCount: 5, trialCount: 30, pairsPerOrder: 15, bootstrapSeed: 48271, bootstrapResamples: 10_000, memoryWindowSeconds: 600, memorySampleIntervalSeconds: 5, harnessVersion: PerformanceFixtures.configuration.harnessVersion, foundationIdentity: PerformanceFixtures.foundation, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion)
        let configRun = PerformanceRunProvenance(variant: "baseline", outputRoot: "build/baseline", sourceRef: PerformanceFixtures.baselineCommit, build: hostBuild, host: PerformanceFixtures.host, recordedAtUTC: PerformanceFixtures.recordedAtUTC, configuration: mismatchedConfig, foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath, foundation: PerformanceFixtures.foundation, harnessVersion: PerformanceFixtures.configuration.harnessVersion, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(baselineRun: configRun).validateStructure())

        let mismatchedEligibility = PerformancePairEligibility(baselineRoot: "build/other", candidateRoot: PerformanceFixtures.eligibility.candidateRoot, baselineCommitSHA: PerformanceFixtures.eligibility.baselineCommitSHA, candidateCommitSHA: PerformanceFixtures.eligibility.candidateCommitSHA, foundationProvenance: PerformanceFixtures.eligibility.foundationProvenance)
        XCTAssertThrowsError(try PerformanceComparisonHarness.preflight(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: PerformanceFixtures.configuration, eligibility: mismatchedEligibility))

        let swappedBaseline = PerformanceRunProvenance(variant: "candidate", outputRoot: PerformanceFixtures.baselineRun.outputRoot, sourceRef: PerformanceFixtures.baselineRun.sourceRef, build: PerformanceFixtures.baselineRun.build, host: PerformanceFixtures.baselineRun.host, recordedAtUTC: PerformanceFixtures.baselineRun.recordedAtUTC, configuration: PerformanceFixtures.baselineRun.configuration, foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath, foundation: PerformanceFixtures.baselineRun.foundation, harnessVersion: PerformanceFixtures.baselineRun.harnessVersion, buildContractVersion: PerformanceFixtures.baselineRun.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.baselineRun.acceptedFoundationArtifactSHA256)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(baselineRun: swappedBaseline).validateStructure())

        let swappedCandidate = PerformanceRunProvenance(variant: "baseline", outputRoot: PerformanceFixtures.run.outputRoot, sourceRef: PerformanceFixtures.run.sourceRef, build: PerformanceFixtures.run.build, host: PerformanceFixtures.run.host, recordedAtUTC: PerformanceFixtures.run.recordedAtUTC, configuration: PerformanceFixtures.run.configuration, foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath, foundation: PerformanceFixtures.run.foundation, harnessVersion: PerformanceFixtures.run.harnessVersion, buildContractVersion: PerformanceFixtures.run.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.run.acceptedFoundationArtifactSHA256)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(candidateRun: swappedCandidate).validateStructure())
    }

    func testPreflightRejectsContentManifestLineageBeforeWriting() throws {
        let dirtyIdentity = MeasurementIdentity(sourceCommitSHA: nil, contentManifestSHA256: PerformanceFixtures.sourceManifest, hostModel: PerformanceFixtures.identity.hostModel, macOSVersion: PerformanceFixtures.identity.macOSVersion, xcodeVersion: PerformanceFixtures.identity.xcodeVersion, developerDirectory: PerformanceFixtures.identity.developerDirectory, powerState: PerformanceFixtures.identity.powerState, displayState: PerformanceFixtures.identity.displayState, buildConfiguration: "release")
        let dirtyBuild = BuildProvenance(sourceTreeStatus: .dirty, sourceIdentity: SourceIdentity(kind: .contentManifestSHA256, value: PerformanceFixtures.sourceManifest), sourceManifestSHA256: PerformanceFixtures.sourceManifest, executableSHA256: PerformanceFixtures.executable, bundleManifestSHA256: PerformanceFixtures.bundle, buildConfiguration: "release", recordedAtUTC: PerformanceFixtures.recordedAtUTC, foundation: PerformanceFixtures.foundation, harnessVersion: PerformanceFixtures.configuration.harnessVersion, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact)
        let dirtyRun = PerformanceRunProvenance(variant: "candidate", outputRoot: "build/candidate", sourceRef: PerformanceFixtures.sourceManifest, build: dirtyBuild, host: PerformanceFixtures.host, recordedAtUTC: PerformanceFixtures.recordedAtUTC, configuration: PerformanceFixtures.configuration, foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath, foundation: PerformanceFixtures.foundation, harnessVersion: PerformanceFixtures.configuration.harnessVersion, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact)
        let dirty = PerformanceFixtures.report(identity: dirtyIdentity, build: dirtyBuild, run: dirtyRun)

        XCTAssertThrowsError(try PerformanceComparisonHarness.preflight(baseline: dirty, candidate: PerformanceFixtures.candidate, configuration: PerformanceFixtures.configuration, eligibility: PerformanceFixtures.eligibility))
    }

    func testPreflightRejectsFailedAndUnmeasuredInputs() throws {
        for status in [MeasurementStatus.failed, .unmeasured] {
            let report = PerformanceFixtures.withStatuses(PerformanceFixtures.baseline, status: status)
            XCTAssertThrowsError(try PerformanceComparisonHarness.preflight(baseline: report, candidate: PerformanceFixtures.candidate, configuration: PerformanceFixtures.configuration, eligibility: PerformanceFixtures.eligibility))
        }
    }

    func testComparisonRejectsInvalidArraysRatiosAndBootstrap() throws {
        var shortSamples = PerformanceFixtures.comparison().metrics
        shortSamples[0] = MetricComparison(metricID: shortSamples[0].metricID, evidenceClass: shortSamples[0].evidenceClass, unit: shortSamples[0].unit, baselineID: shortSamples[0].baselineID, candidateID: shortSamples[0].candidateID, baselineSamples: [1], candidateSamples: [], ratios: [], deltas: [], budgetLimit: shortSamples[0].budgetLimit, bootstrapInterval: shortSamples[0].bootstrapInterval, manualEvidence: nil, disposition: .acceptedNoRegression)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: shortSamples).validateStructure())

        var wrongRatio = PerformanceFixtures.comparison().metrics
        wrongRatio[0] = MetricComparison(metricID: wrongRatio[0].metricID, evidenceClass: wrongRatio[0].evidenceClass, unit: wrongRatio[0].unit, baselineID: wrongRatio[0].baselineID, candidateID: wrongRatio[0].candidateID, baselineSamples: wrongRatio[0].baselineSamples, candidateSamples: wrongRatio[0].candidateSamples, ratios: Array(repeating: 1, count: 30), deltas: wrongRatio[0].deltas, budgetLimit: wrongRatio[0].budgetLimit, bootstrapInterval: wrongRatio[0].bootstrapInterval, manualEvidence: nil, disposition: .acceptedNoRegression)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: wrongRatio).validateStructure())

        var badBootstrap = PerformanceFixtures.comparison().metrics
        badBootstrap[0] = MetricComparison(metricID: badBootstrap[0].metricID, evidenceClass: badBootstrap[0].evidenceClass, unit: badBootstrap[0].unit, baselineID: badBootstrap[0].baselineID, candidateID: badBootstrap[0].candidateID, baselineSamples: badBootstrap[0].baselineSamples, candidateSamples: badBootstrap[0].candidateSamples, ratios: badBootstrap[0].ratios, deltas: badBootstrap[0].deltas, budgetLimit: badBootstrap[0].budgetLimit, bootstrapInterval: BootstrapInterval(lowerDelta: 2, upperDelta: 1, seed: 48271, resampleCount: 10_000), manualEvidence: nil, disposition: .acceptedNoRegression)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: badBootstrap).validateStructure())
    }

    func testComparisonRequiresThirtyPairedSamplesAndDerivedArrays() throws {
        var emptyDerived = PerformanceFixtures.comparison().metrics
        let value = emptyDerived[0]
        emptyDerived[0] = MetricComparison(metricID: value.metricID, evidenceClass: value.evidenceClass, unit: value.unit, baselineID: value.baselineID, candidateID: value.candidateID, baselineSamples: value.baselineSamples, candidateSamples: value.candidateSamples, ratios: [], deltas: [], budgetLimit: value.budgetLimit, bootstrapInterval: value.bootstrapInterval, manualEvidence: nil, disposition: value.disposition)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: emptyDerived).validateStructure())

        var shortDerived = PerformanceFixtures.comparison().metrics
        shortDerived[0] = MetricComparison(metricID: value.metricID, evidenceClass: value.evidenceClass, unit: value.unit, baselineID: value.baselineID, candidateID: value.candidateID, baselineSamples: value.baselineSamples, candidateSamples: value.candidateSamples, ratios: Array(value.ratios.dropLast()), deltas: Array(value.deltas.dropLast()), budgetLimit: value.budgetLimit, bootstrapInterval: value.bootstrapInterval, manualEvidence: nil, disposition: value.disposition)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: shortDerived).validateStructure())
    }

    func testComparisonRejectsNonPositiveMetricSamples() throws {
        var zeroBaseline = PerformanceFixtures.comparison().metrics
        let value = zeroBaseline[0]
        zeroBaseline[0] = MetricComparison(metricID: value.metricID, evidenceClass: value.evidenceClass, unit: value.unit, baselineID: value.baselineID, candidateID: value.candidateID, baselineSamples: Array(repeating: 0, count: 30), candidateSamples: value.candidateSamples, ratios: value.ratios, deltas: value.deltas, budgetLimit: value.budgetLimit, bootstrapInterval: value.bootstrapInterval, manualEvidence: nil, disposition: value.disposition)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: zeroBaseline).validateStructure())

        var negativeCandidate = PerformanceFixtures.comparison().metrics
        negativeCandidate[0] = MetricComparison(metricID: value.metricID, evidenceClass: value.evidenceClass, unit: value.unit, baselineID: value.baselineID, candidateID: value.candidateID, baselineSamples: value.baselineSamples, candidateSamples: Array(repeating: -1, count: 30), ratios: value.ratios, deltas: value.deltas, budgetLimit: value.budgetLimit, bootstrapInterval: value.bootstrapInterval, manualEvidence: nil, disposition: value.disposition)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: negativeCandidate).validateStructure())
    }

    func testComparisonCompletionRejectsSelfConsistentRatioRegressionAndBudgetBreach() throws {
        let value = PerformanceFixtures.comparison().metrics[0]
        let ratioRegression = (0..<30).map { _ in 1.2 }
        let ratioSamples = (0..<30).map { _ in 120.0 }
        let ratioMetric = MetricComparison(metricID: value.metricID, evidenceClass: value.evidenceClass, unit: value.unit, baselineID: value.baselineID, candidateID: value.candidateID, baselineSamples: Array(repeating: 100, count: 30), candidateSamples: ratioSamples, ratios: ratioRegression, deltas: Array(repeating: 20, count: 30), budgetLimit: nil, bootstrapInterval: BootstrapInterval(lowerDelta: 20, upperDelta: 20, seed: 48271, resampleCount: 10_000), manualEvidence: nil, disposition: .acceptedNoRegression)
        var ratioMetrics = PerformanceFixtures.comparison().metrics
        ratioMetrics[0] = ratioMetric
        let ratioReport = PerformanceFixtures.comparison(metrics: ratioMetrics)
        XCTAssertNoThrow(try ratioReport.validateStructure())
        XCTAssertThrowsError(try ratioReport.validateCompletion())

        let budgetValue = PerformanceFixtures.comparison().metrics.first { $0.metricID == .combinedFrame }!
        let budgetMetric = MetricComparison(metricID: budgetValue.metricID, evidenceClass: budgetValue.evidenceClass, unit: budgetValue.unit, baselineID: budgetValue.baselineID, candidateID: budgetValue.candidateID, baselineSamples: Array(repeating: 10, count: 30), candidateSamples: Array(repeating: 17, count: 30), ratios: Array(repeating: 1.7, count: 30), deltas: Array(repeating: 7, count: 30), budgetLimit: 16.7, bootstrapInterval: BootstrapInterval(lowerDelta: 7, upperDelta: 7, seed: 48271, resampleCount: 10_000), manualEvidence: nil, disposition: .acceptedNoRegression)
        var budgetMetrics = PerformanceFixtures.comparison().metrics
        budgetMetrics[budgetMetrics.firstIndex { $0.metricID == .combinedFrame }!] = budgetMetric
        let budgetReport = PerformanceFixtures.comparison(metrics: budgetMetrics)
        XCTAssertNoThrow(try budgetReport.validateStructure())
        XCTAssertThrowsError(try budgetReport.validateCompletion())
    }

    func testComparisonRequiresCanonicalUnitsAndNonSpoofableBudgets() throws {
        XCTAssertEqual(PerformanceMetricID.redrawLayout.canonicalUnit, .milliseconds)
        let metrics = PerformanceFixtures.comparison().metrics
        let combined = metrics.first { $0.metricID == .combinedFrame }!
        let wrongUnit = MetricComparison(metricID: combined.metricID, evidenceClass: combined.evidenceClass, unit: .bytes, baselineID: combined.baselineID, candidateID: combined.candidateID, baselineSamples: combined.baselineSamples, candidateSamples: combined.candidateSamples, ratios: combined.ratios, deltas: combined.deltas, budgetLimit: 16.7, bootstrapInterval: combined.bootstrapInterval, manualEvidence: nil, disposition: combined.disposition)
        var wrongUnitMetrics = metrics
        wrongUnitMetrics[wrongUnitMetrics.firstIndex { $0.metricID == .combinedFrame }!] = wrongUnit
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: wrongUnitMetrics).validateStructure())

        let missingBudget = MetricComparison(metricID: combined.metricID, evidenceClass: combined.evidenceClass, unit: combined.unit, baselineID: combined.baselineID, candidateID: combined.candidateID, baselineSamples: combined.baselineSamples, candidateSamples: combined.candidateSamples, ratios: combined.ratios, deltas: combined.deltas, budgetLimit: nil, bootstrapInterval: combined.bootstrapInterval, manualEvidence: nil, disposition: combined.disposition)
        var missingBudgetMetrics = metrics
        missingBudgetMetrics[missingBudgetMetrics.firstIndex { $0.metricID == .combinedFrame }!] = missingBudget
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: missingBudgetMetrics).validateStructure())

        let spoofedBudget = MetricComparison(metricID: combined.metricID, evidenceClass: combined.evidenceClass, unit: combined.unit, baselineID: combined.baselineID, candidateID: combined.candidateID, baselineSamples: combined.baselineSamples, candidateSamples: combined.candidateSamples, ratios: combined.ratios, deltas: combined.deltas, budgetLimit: 1e300, bootstrapInterval: combined.bootstrapInterval, manualEvidence: nil, disposition: combined.disposition)
        var spoofedBudgetMetrics = metrics
        spoofedBudgetMetrics[spoofedBudgetMetrics.firstIndex { $0.metricID == .combinedFrame }!] = spoofedBudget
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: spoofedBudgetMetrics).validateStructure())

        let memory = metrics.first { $0.metricID == .memoryRSS }!
        let unexpectedBudget = MetricComparison(metricID: memory.metricID, evidenceClass: memory.evidenceClass, unit: memory.unit, baselineID: memory.baselineID, candidateID: memory.candidateID, baselineSamples: memory.baselineSamples, candidateSamples: memory.candidateSamples, ratios: memory.ratios, deltas: memory.deltas, budgetLimit: 1e12, bootstrapInterval: memory.bootstrapInterval, manualEvidence: nil, disposition: memory.disposition)
        var unexpectedBudgetMetrics = metrics
        unexpectedBudgetMetrics[unexpectedBudgetMetrics.firstIndex { $0.metricID == .memoryRSS }!] = unexpectedBudget
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: unexpectedBudgetMetrics).validateStructure())

        XCTAssertNoThrow(try PerformanceFixtures.comparison().validateCompletion())
    }

    func testMemoryComparisonUsesPositiveAbsoluteRSSSamplesWithoutAnAbsoluteBudget() throws {
        let memory = PerformanceFixtures.comparison().metrics.first { $0.metricID == .memoryRSS }!
        XCTAssertEqual(memory.unit, .bytes)
        XCTAssertNil(memory.budgetLimit)
        XCTAssertTrue(memory.baselineSamples.allSatisfy { $0 > 0 })
        XCTAssertTrue(memory.candidateSamples.allSatisfy { $0 > 0 })

        let signed = MetricComparison(metricID: memory.metricID, evidenceClass: memory.evidenceClass, unit: memory.unit, baselineID: memory.baselineID, candidateID: memory.candidateID, baselineSamples: Array(repeating: -1, count: 30), candidateSamples: memory.candidateSamples, ratios: memory.ratios, deltas: memory.deltas, budgetLimit: nil, bootstrapInterval: memory.bootstrapInterval, manualEvidence: nil, disposition: memory.disposition)
        var metrics = PerformanceFixtures.comparison().metrics
        metrics[metrics.firstIndex { $0.metricID == .memoryRSS }!] = signed
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: metrics).validateStructure())
    }

    func testComparisonCompletionHonorsRendererCompositorSumAndCombinedFrameBoundary() throws {
        let baseline = PerformanceFixtures.comparison()
        let combined = baseline.metrics.first { $0.metricID == .combinedFrame }!
        let combinedBoundary = MetricComparison(metricID: combined.metricID, evidenceClass: combined.evidenceClass, unit: combined.unit, baselineID: combined.baselineID, candidateID: combined.candidateID, baselineSamples: Array(repeating: 16, count: 30), candidateSamples: Array(repeating: 16, count: 30), ratios: Array(repeating: 1, count: 30), deltas: Array(repeating: 0, count: 30), budgetLimit: 16.7, bootstrapInterval: BootstrapInterval(lowerDelta: 0, upperDelta: 0, seed: 48271, resampleCount: 10_000), manualEvidence: nil, disposition: .acceptedNoRegression)
        var boundaryMetrics = baseline.metrics
        boundaryMetrics[boundaryMetrics.firstIndex { $0.metricID == .combinedFrame }!] = combinedBoundary
        let boundaryReport = PerformanceFixtures.comparison(metrics: boundaryMetrics)
        XCTAssertNoThrow(try boundaryReport.validateCompletion())

        func capped(_ value: MetricComparison) -> MetricComparison {
            MetricComparison(metricID: value.metricID, evidenceClass: value.evidenceClass, unit: value.unit, baselineID: value.baselineID, candidateID: value.candidateID, baselineSamples: Array(repeating: 10, count: 30), candidateSamples: Array(repeating: 10, count: 30), ratios: Array(repeating: 1, count: 30), deltas: Array(repeating: 0, count: 30), budgetLimit: nil, bootstrapInterval: BootstrapInterval(lowerDelta: 0, upperDelta: 0, seed: 48271, resampleCount: 10_000), manualEvidence: nil, disposition: .acceptedNoRegression)
        }
        var overBudgetMetrics = baseline.metrics
        overBudgetMetrics[overBudgetMetrics.firstIndex { $0.metricID == .renderer }!] = capped(baseline.metrics.first { $0.metricID == .renderer }!)
        overBudgetMetrics[overBudgetMetrics.firstIndex { $0.metricID == .compositor }!] = capped(baseline.metrics.first { $0.metricID == .compositor }!)
        let overBudgetReport = PerformanceFixtures.comparison(metrics: overBudgetMetrics)
        XCTAssertNoThrow(try overBudgetReport.validateStructure())
        XCTAssertThrowsError(try overBudgetReport.validateCompletion())
    }

    func testComparisonCompletionRejectsResponsivenessAndInputToVisibleBudgetBreaches() throws {
        for metricID in [PerformanceMetricID.responsiveness, .inputToVisible] {
            let value = PerformanceFixtures.comparison().metrics.first { $0.metricID == metricID }!
            let breach = MetricComparison(metricID: value.metricID, evidenceClass: value.evidenceClass, unit: value.unit, baselineID: value.baselineID, candidateID: value.candidateID, baselineSamples: Array(repeating: 100, count: 30), candidateSamples: Array(repeating: 101, count: 30), ratios: Array(repeating: 1.01, count: 30), deltas: Array(repeating: 1, count: 30), budgetLimit: 100, bootstrapInterval: BootstrapInterval(lowerDelta: 1, upperDelta: 1, seed: 48271, resampleCount: 10_000), manualEvidence: value.manualEvidence, disposition: .acceptedNoRegression)
            var metrics = PerformanceFixtures.comparison().metrics
            metrics[metrics.firstIndex { $0.metricID == metricID }!] = breach
            let report = PerformanceFixtures.comparison(metrics: metrics)
            XCTAssertNoThrow(try report.validateStructure())
            XCTAssertThrowsError(try report.validateCompletion())
        }
    }

    func testComparisonRequiresMatchingPersistedFixtures() throws {
        let mismatched = FixtureIdentity(identifier: "other-fixture", fixtureProfile: .standard12, fixtureVersion: PerformanceFixtureProfile.standard12.version, markCount: PerformanceFixtures.fixture.markCount, continuationSamples: PerformanceFixtures.fixture.continuationSamples, warmupCount: PerformanceFixtures.fixture.warmupCount, trialCount: PerformanceFixtures.fixture.trialCount, seed: PerformanceFixtures.fixture.seed)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(baselineFixture: mismatched).validateStructure())

        let mismatchedCandidate = FixtureIdentity(identifier: "other-fixture", fixtureProfile: .standard12, fixtureVersion: PerformanceFixtureProfile.standard12.version, markCount: PerformanceFixtures.fixture.markCount, continuationSamples: PerformanceFixtures.fixture.continuationSamples, warmupCount: PerformanceFixtures.fixture.warmupCount, trialCount: PerformanceFixtures.fixture.trialCount, seed: PerformanceFixtures.fixture.seed)
        let candidateWithMismatchedFixture = PerformanceFixtures.report(fixture: mismatchedCandidate)
        XCTAssertThrowsError(try PerformanceComparisonHarness.preflight(baseline: PerformanceFixtures.baseline, candidate: candidateWithMismatchedFixture, configuration: PerformanceFixtures.configuration, eligibility: PerformanceFixtures.eligibility))
        XCTAssertThrowsError(try PerformanceFixtures.comparison(candidateFixture: mismatchedCandidate).validateStructure())
    }

    func testComparisonRejectsEveryMismatchedMeasurementEnvironmentDimension() throws {
        let mutations: [(String, (MeasurementIdentity) -> MeasurementIdentity)] = [
            ("hostModel", { value in MeasurementIdentity(sourceCommitSHA: value.sourceCommitSHA, contentManifestSHA256: value.contentManifestSHA256, hostModel: "other-model", macOSVersion: value.macOSVersion, xcodeVersion: value.xcodeVersion, developerDirectory: value.developerDirectory, powerState: value.powerState, displayState: value.displayState, buildConfiguration: value.buildConfiguration) }),
            ("macOSVersion", { value in MeasurementIdentity(sourceCommitSHA: value.sourceCommitSHA, contentManifestSHA256: value.contentManifestSHA256, hostModel: value.hostModel, macOSVersion: "other-macos", xcodeVersion: value.xcodeVersion, developerDirectory: value.developerDirectory, powerState: value.powerState, displayState: value.displayState, buildConfiguration: value.buildConfiguration) }),
            ("xcodeVersion", { value in MeasurementIdentity(sourceCommitSHA: value.sourceCommitSHA, contentManifestSHA256: value.contentManifestSHA256, hostModel: value.hostModel, macOSVersion: value.macOSVersion, xcodeVersion: "other-xcode", developerDirectory: value.developerDirectory, powerState: value.powerState, displayState: value.displayState, buildConfiguration: value.buildConfiguration) }),
            ("developerDirectory", { value in MeasurementIdentity(sourceCommitSHA: value.sourceCommitSHA, contentManifestSHA256: value.contentManifestSHA256, hostModel: value.hostModel, macOSVersion: value.macOSVersion, xcodeVersion: value.xcodeVersion, developerDirectory: "/other/developer", powerState: value.powerState, displayState: value.displayState, buildConfiguration: value.buildConfiguration) }),
            ("powerState", { value in MeasurementIdentity(sourceCommitSHA: value.sourceCommitSHA, contentManifestSHA256: value.contentManifestSHA256, hostModel: value.hostModel, macOSVersion: value.macOSVersion, xcodeVersion: value.xcodeVersion, developerDirectory: value.developerDirectory, powerState: "battery", displayState: value.displayState, buildConfiguration: value.buildConfiguration) }),
            ("displayState", { value in MeasurementIdentity(sourceCommitSHA: value.sourceCommitSHA, contentManifestSHA256: value.contentManifestSHA256, hostModel: value.hostModel, macOSVersion: value.macOSVersion, xcodeVersion: value.xcodeVersion, developerDirectory: value.developerDirectory, powerState: value.powerState, displayState: "two-displays", buildConfiguration: value.buildConfiguration) }),
            ("buildConfiguration", { value in MeasurementIdentity(sourceCommitSHA: value.sourceCommitSHA, contentManifestSHA256: value.contentManifestSHA256, hostModel: value.hostModel, macOSVersion: value.macOSVersion, xcodeVersion: value.xcodeVersion, developerDirectory: value.developerDirectory, powerState: value.powerState, displayState: value.displayState, buildConfiguration: "debug") }),
        ]

        for (label, mutate) in mutations {
            let report = PerformanceFixtures.comparison(baselineMeasurementIdentity: mutate(PerformanceFixtures.baselineIdentity))
            XCTAssertThrowsError(try report.validateStructure(), "Expected \(label) mismatch to be rejected")
        }
    }

    func testComparisonEnforcesManualEvidenceAndDeterministicExclusion() throws {
        let manual = PerformanceFixtures.comparison(metrics: PerformanceFixtures.metricComparisons(manualMetric: .inputToVisible))
        XCTAssertNoThrow(try manual.validateStructure())

        var missingEvidence = manual.metrics
        let metric = missingEvidence.firstIndex { $0.metricID == .inputToVisible }!
        let value = missingEvidence[metric]
        missingEvidence[metric] = MetricComparison(metricID: value.metricID, evidenceClass: .manual, unit: value.unit, baselineID: value.baselineID, candidateID: value.candidateID, baselineSamples: value.baselineSamples, candidateSamples: value.candidateSamples, ratios: value.ratios, deltas: value.deltas, budgetLimit: value.budgetLimit, bootstrapInterval: value.bootstrapInterval, manualEvidence: nil, disposition: value.disposition)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: missingEvidence).validateStructure())

        var wrongHostEvidence = manual.metrics
        let manualIndex = wrongHostEvidence.firstIndex { $0.metricID == .inputToVisible }!
        let manualMetric = wrongHostEvidence[manualIndex]
        let evidence = PerformanceFixtures.manualEvidencePair
        let wrongHostCandidate = ManualMetricEvidence(metricID: evidence.candidate.metricID, evidenceClass: evidence.candidate.evidenceClass, variant: evidence.candidate.variant, sourceCommitSHA: evidence.candidate.sourceCommitSHA, measurementReportSHA256: evidence.candidate.measurementReportSHA256, pairExecutionArtifactSHA256: evidence.candidate.pairExecutionArtifactSHA256, host: "other-machine", recordedAt: evidence.candidate.recordedAt, permissions: evidence.candidate.permissions, steps: evidence.candidate.steps, samples: evidence.candidate.samples, result: evidence.candidate.result, evidencePath: evidence.candidate.evidencePath)
        let wrongHostPair = ManualMetricEvidencePair(procedureVersion: evidence.procedureVersion, pairOrders: evidence.pairOrders, baseline: evidence.baseline, candidate: wrongHostCandidate)
        wrongHostEvidence[manualIndex] = MetricComparison(metricID: manualMetric.metricID, evidenceClass: manualMetric.evidenceClass, unit: manualMetric.unit, baselineID: manualMetric.baselineID, candidateID: manualMetric.candidateID, baselineSamples: manualMetric.baselineSamples, candidateSamples: manualMetric.candidateSamples, ratios: manualMetric.ratios, deltas: manualMetric.deltas, budgetLimit: manualMetric.budgetLimit, bootstrapInterval: manualMetric.bootstrapInterval, manualEvidence: wrongHostPair, disposition: manualMetric.disposition)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: wrongHostEvidence).validateStructure())

        var deterministicEvidence = PerformanceFixtures.comparison().metrics
        let deterministic = deterministicEvidence[0]
        deterministicEvidence[0] = MetricComparison(metricID: deterministic.metricID, evidenceClass: .deterministic, unit: deterministic.unit, baselineID: deterministic.baselineID, candidateID: deterministic.candidateID, baselineSamples: deterministic.baselineSamples, candidateSamples: deterministic.candidateSamples, ratios: deterministic.ratios, deltas: deterministic.deltas, budgetLimit: deterministic.budgetLimit, bootstrapInterval: deterministic.bootstrapInterval, manualEvidence: PerformanceFixtures.manualEvidencePair, disposition: deterministic.disposition)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: deterministicEvidence).validateStructure())
    }

    func testComparisonRejectsIncoherentResilienceAndDispositionOnCompletion() throws {
        let badResources = ResourceCounts(overlays: 0, timers: 0, handlers: 0, windows: 0, observers: 0)
        let badCase = ResilienceCase(identifier: "mode-toggle", status: .measured, iterationCount: 100, peakResourceCounts: badResources, endResourceCounts: ResourceCounts(overlays: 1, timers: 0, handlers: 0, windows: 0, observers: 0), leakedResource: false, unexpectedGrowth: false)
        let badResilience = ResilienceMeasurement(status: .measured, cases: [badCase], disposition: .acceptedNoRegression)
        let report = PerformanceFixtures.comparison(resilience: badResilience)
        XCTAssertThrowsError(try report.validateStructure())

        let revise = PerformanceFixtures.comparison(disposition: .revise)
        XCTAssertThrowsError(try revise.validateCompletion())
    }

    func testWriteComparisonIsAtomicAndDoesNotLeavePartialOutputOnFailure() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("pointer-comparison-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let baselineURL = temp.appendingPathComponent("baseline.json")
        let candidateURL = temp.appendingPathComponent("candidate.json")
        let outputURL = temp.appendingPathComponent("comparisons/paired-comparison.json")
        try JSONEncoder().encode(PerformanceFixtures.baseline).write(to: baselineURL)
        try JSONEncoder().encode(PerformanceFixtures.candidate).write(to: candidateURL)
        let manualEvidenceDirectory = temp.appendingPathComponent("manual", isDirectory: true)
        try FileManager.default.createDirectory(at: manualEvidenceDirectory, withIntermediateDirectories: true)
        let pairExecutionURL = temp.appendingPathComponent("pairs.json")
        try PerformancePairExecutionArtifact.canonicalData(for: PerformanceFixtures.executionArtifact).write(to: pairExecutionURL)

        XCTAssertThrowsError(try PerformanceComparisonHarness.writeComparison(draft: PerformanceFixtures.draft(), baselineURL: baselineURL, candidateURL: temp.appendingPathComponent("missing-candidate.json"), pairExecutionURL: pairExecutionURL, manualEvidenceDirectory: manualEvidenceDirectory, outputDirectory: outputURL.deletingLastPathComponent(), configuration: PerformanceFixtures.configuration, eligibility: PerformanceFixtures.eligibility))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func testWriteComparisonBindsExactInputBytesAndRejectsHashMismatchBeforeOutput() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("pointer-bound-comparison-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let baselineURL = temp.appendingPathComponent("baseline.json")
        let candidateURL = temp.appendingPathComponent("candidate.json")
        let baselineData = try JSONEncoder().encode(PerformanceFixtures.baseline)
        let candidateData = try JSONEncoder().encode(PerformanceFixtures.candidate)
        try baselineData.write(to: baselineURL)
        try candidateData.write(to: candidateURL)
        let outputDirectory = temp.appendingPathComponent("bound-output", isDirectory: true)
        let manualEvidenceDirectory = temp.appendingPathComponent("manual", isDirectory: true)
        try FileManager.default.createDirectory(at: manualEvidenceDirectory, withIntermediateDirectories: true)
        let pairExecutionURL = temp.appendingPathComponent("pairs.json")
        let pairArtifact = makeArtifact(baselineData: baselineData, candidateData: candidateData)
        try PerformancePairExecutionArtifact.canonicalData(for: pairArtifact).write(to: pairExecutionURL)
        let draft = try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: PerformanceFixtures.configuration, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: pairArtifact, manualEvidenceDirectory: manualEvidenceDirectory, pairExecutionArtifactSHA256: PerformanceFixtures.sha256(try Data(contentsOf: pairExecutionURL)))
        _ = try PerformanceComparisonHarness.writeComparison(draft: draft, baselineURL: baselineURL, candidateURL: candidateURL, pairExecutionURL: pairExecutionURL, manualEvidenceDirectory: manualEvidenceDirectory, outputDirectory: outputDirectory, configuration: PerformanceFixtures.configuration, eligibility: PerformanceFixtures.eligibility)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("paired-comparison.json").path))

        let writtenData = try Data(contentsOf: outputDirectory.appendingPathComponent("paired-comparison.json"))
        let persisted = try JSONDecoder().decode(PerformanceComparisonReport.self, from: writtenData)
        XCTAssertEqual(persisted.baselineMeasurementReportSHA256, PerformanceFixtures.sha256(baselineData))
        XCTAssertEqual(persisted.candidateMeasurementReportSHA256, PerformanceFixtures.sha256(candidateData))
        XCTAssertEqual(writtenData, try PerformanceCanonicalJSON.data(for: persisted))
    }

    func testWriteComparisonCrossChecksCallerReportAgainstDecodedInputsBeforeOutput() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("pointer-cross-check-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }

        let baselineURL = temp.appendingPathComponent("baseline.json")
        let candidateURL = temp.appendingPathComponent("candidate.json")
        let baselineData = try JSONEncoder().encode(PerformanceFixtures.baseline)
        let candidateData = try JSONEncoder().encode(PerformanceFixtures.candidate)
        try baselineData.write(to: baselineURL)
        try candidateData.write(to: candidateURL)
        let manualEvidenceDirectory = temp.appendingPathComponent("manual", isDirectory: true)
        try FileManager.default.createDirectory(at: manualEvidenceDirectory, withIntermediateDirectories: true)
        let pairExecutionURL = temp.appendingPathComponent("pairs.json")
        let pairArtifact = makeArtifact(baselineData: baselineData, candidateData: candidateData)
        try PerformancePairExecutionArtifact.canonicalData(for: pairArtifact).write(to: pairExecutionURL)
        func assertRejected(_ label: String, draft: PerformanceComparisonDraft, eligibility: PerformancePairEligibility = PerformanceFixtures.eligibility) {
            let outputDirectory = temp.appendingPathComponent(label, isDirectory: true)
            XCTAssertThrowsError(try PerformanceComparisonHarness.writeComparison(draft: draft, baselineURL: baselineURL, candidateURL: candidateURL, pairExecutionURL: pairExecutionURL, manualEvidenceDirectory: manualEvidenceDirectory, outputDirectory: outputDirectory, configuration: PerformanceFixtures.configuration, eligibility: eligibility), "Expected \(label) mismatch to be rejected")
            XCTAssertFalse(FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("paired-comparison.json").path))
        }

        assertRejected("identity", draft: PerformanceFixtures.draft(baselineMeasurementIdentity: PerformanceFixtures.identity))
        assertRejected("fixture", draft: PerformanceFixtures.draft(baselineFixture: FixtureIdentity(identifier: "other", fixtureProfile: .standard12, fixtureVersion: PerformanceFixtureProfile.standard12.version, markCount: PerformanceFixtures.fixture.markCount, continuationSamples: PerformanceFixtures.fixture.continuationSamples, warmupCount: PerformanceFixtures.fixture.warmupCount, trialCount: PerformanceFixtures.fixture.trialCount, seed: PerformanceFixtures.fixture.seed)))

        let changedCandidateBuild = BuildProvenance(sourceTreeStatus: .clean, sourceIdentity: PerformanceFixtures.build.sourceIdentity, sourceManifestSHA256: PerformanceFixtures.build.sourceManifestSHA256, executableSHA256: String(repeating: "8", count: 64), bundleManifestSHA256: PerformanceFixtures.build.bundleManifestSHA256, buildConfiguration: PerformanceFixtures.build.buildConfiguration, recordedAtUTC: PerformanceFixtures.build.recordedAtUTC, foundation: PerformanceFixtures.build.foundation, harnessVersion: PerformanceFixtures.build.harnessVersion, buildContractVersion: PerformanceFixtures.build.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.build.acceptedFoundationArtifactSHA256)
        let changedCandidateRun = PerformanceRunProvenance(variant: "candidate", outputRoot: PerformanceFixtures.run.outputRoot, sourceRef: PerformanceFixtures.run.sourceRef, build: changedCandidateBuild, host: PerformanceFixtures.run.host, recordedAtUTC: PerformanceFixtures.run.recordedAtUTC, configuration: PerformanceFixtures.run.configuration, foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath, foundation: PerformanceFixtures.run.foundation, harnessVersion: PerformanceFixtures.run.harnessVersion, buildContractVersion: PerformanceFixtures.run.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.run.acceptedFoundationArtifactSHA256)
        assertRejected("build", draft: PerformanceFixtures.draft(candidateBuild: changedCandidateBuild, candidateRun: changedCandidateRun))

        let changedRun = PerformanceRunProvenance(variant: "candidate", outputRoot: "build/other", sourceRef: PerformanceFixtures.run.sourceRef, build: PerformanceFixtures.run.build, host: PerformanceFixtures.run.host, recordedAtUTC: PerformanceFixtures.run.recordedAtUTC, configuration: PerformanceFixtures.run.configuration, foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath, foundation: PerformanceFixtures.run.foundation, harnessVersion: PerformanceFixtures.run.harnessVersion, buildContractVersion: PerformanceFixtures.run.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.run.acceptedFoundationArtifactSHA256)
        assertRejected("run", draft: PerformanceFixtures.draft(candidateRun: changedRun))

        let changedHost = HostIdentity(machineIdentifier: "other-machine", processArchitecture: PerformanceFixtures.host.processArchitecture, connectedDisplayUUIDs: PerformanceFixtures.host.connectedDisplayUUIDs)
        let changedBaselineRun = PerformanceRunProvenance(variant: "baseline", outputRoot: PerformanceFixtures.baselineRun.outputRoot, sourceRef: PerformanceFixtures.baselineRun.sourceRef, build: PerformanceFixtures.baselineRun.build, host: changedHost, recordedAtUTC: PerformanceFixtures.baselineRun.recordedAtUTC, configuration: PerformanceFixtures.baselineRun.configuration, foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath, foundation: PerformanceFixtures.baselineRun.foundation, harnessVersion: PerformanceFixtures.baselineRun.harnessVersion, buildContractVersion: PerformanceFixtures.baselineRun.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.baselineRun.acceptedFoundationArtifactSHA256)
        let changedCandidateHostRun = PerformanceRunProvenance(variant: "candidate", outputRoot: PerformanceFixtures.run.outputRoot, sourceRef: PerformanceFixtures.run.sourceRef, build: PerformanceFixtures.run.build, host: changedHost, recordedAtUTC: PerformanceFixtures.run.recordedAtUTC, configuration: PerformanceFixtures.run.configuration, foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath, foundation: PerformanceFixtures.run.foundation, harnessVersion: PerformanceFixtures.run.harnessVersion, buildContractVersion: PerformanceFixtures.run.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.run.acceptedFoundationArtifactSHA256)
        assertRejected("host", draft: PerformanceFixtures.draft(baselineRun: changedBaselineRun, candidateRun: changedCandidateHostRun))

        let changedConfiguration = PerformanceConfiguration(fixtureMarkCount: 12, samplesPerGesture: 240, warmupCount: 5, trialCount: 30, pairsPerOrder: 14, bootstrapSeed: 48271, bootstrapResamples: 10_000, memoryWindowSeconds: 600, memorySampleIntervalSeconds: 5, harnessVersion: PerformanceFixtures.configuration.harnessVersion, foundationIdentity: PerformanceFixtures.foundation, buildContractVersion: PerformanceFixtures.configuration.buildContractVersion)
        let changedBaselineConfigRun = PerformanceRunProvenance(variant: "baseline", outputRoot: PerformanceFixtures.baselineRun.outputRoot, sourceRef: PerformanceFixtures.baselineRun.sourceRef, build: PerformanceFixtures.baselineRun.build, host: PerformanceFixtures.baselineRun.host, recordedAtUTC: PerformanceFixtures.baselineRun.recordedAtUTC, configuration: changedConfiguration, foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath, foundation: PerformanceFixtures.baselineRun.foundation, harnessVersion: PerformanceFixtures.baselineRun.harnessVersion, buildContractVersion: PerformanceFixtures.baselineRun.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.baselineRun.acceptedFoundationArtifactSHA256)
        let changedCandidateConfigRun = PerformanceRunProvenance(variant: "candidate", outputRoot: PerformanceFixtures.run.outputRoot, sourceRef: PerformanceFixtures.run.sourceRef, build: PerformanceFixtures.run.build, host: PerformanceFixtures.run.host, recordedAtUTC: PerformanceFixtures.run.recordedAtUTC, configuration: changedConfiguration, foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath, foundation: PerformanceFixtures.run.foundation, harnessVersion: PerformanceFixtures.run.harnessVersion, buildContractVersion: PerformanceFixtures.run.buildContractVersion, acceptedFoundationArtifactSHA256: PerformanceFixtures.run.acceptedFoundationArtifactSHA256)
        assertRejected("configuration", draft: PerformanceFixtures.draft(baselineRun: changedBaselineConfigRun, candidateRun: changedCandidateConfigRun))

        let changedEligibility = PerformancePairEligibility(baselineRoot: "build/other", candidateRoot: PerformanceFixtures.eligibility.candidateRoot, baselineCommitSHA: PerformanceFixtures.eligibility.baselineCommitSHA, candidateCommitSHA: PerformanceFixtures.eligibility.candidateCommitSHA, foundationProvenance: PerformanceFixtures.eligibility.foundationProvenance)
        assertRejected("eligibility", draft: PerformanceFixtures.draft(), eligibility: changedEligibility)
    }

    func testValidPairPassesMeasuredPreflightButCompareRemainsTask3Owned() throws {
        XCTAssertNoThrow(try PerformanceComparisonHarness.preflight(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: PerformanceFixtures.configuration, eligibility: PerformanceFixtures.eligibility))
        let manualEvidenceDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("pointer-manual-evidence-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: manualEvidenceDirectory, withIntermediateDirectories: true)
        let draft = try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: PerformanceFixtures.configuration, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: PerformanceFixtures.executionArtifact, manualEvidenceDirectory: manualEvidenceDirectory, pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256)
        XCTAssertEqual(draft.metrics.count, PerformanceMetricID.allCases.count)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: manualEvidenceDirectory, includingPropertiesForKeys: nil).isEmpty)
    }

    func testComparisonCalculatesExactlyFifteenPairsPerOrderAndDerivedValues() throws {
        let directory = try makeManualEvidenceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let draft = try PerformanceComparisonHarness.compare(
            baseline: PerformanceFixtures.baseline,
            candidate: PerformanceFixtures.candidate,
            configuration: PerformanceConfiguration.standard,
            eligibility: PerformanceFixtures.eligibility,
            pairExecutionArtifact: PerformanceFixtures.executionArtifact,
            manualEvidenceDirectory: directory,
            pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256
        )

        XCTAssertEqual(draft.seed, 48271)
        XCTAssertEqual(draft.resampleCount, 10_000)
        let records = PerformanceFixtures.executionArtifact.records.sorted { $0.pairIndex < $1.pairIndex }
        XCTAssertEqual(draft.pairExecutionArtifact, PerformanceFixtures.executionArtifact)
        XCTAssertEqual(records.filter { $0.order == .baselineFirst }.count, 15)
        XCTAssertEqual(records.filter { $0.order == .candidateFirst }.count, 15)
        for metric in draft.metrics {
            XCTAssertEqual(metric.baselineSamples.count, 30, metric.metricID.rawValue)
            XCTAssertEqual(metric.candidateSamples.count, 30, metric.metricID.rawValue)
            XCTAssertEqual(metric.ratios, zip(metric.baselineSamples, metric.candidateSamples).map { $1 / $0 })
            XCTAssertEqual(metric.deltas, zip(metric.baselineSamples, metric.candidateSamples).map { $1 - $0 })
            XCTAssertEqual(metric.disposition, .acceptedNoRegression)
        }
    }

    func testComparisonPreservesVariedRawTimingArraysInsteadOfRepeatingP95() throws {
        let directory = try makeManualEvidenceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let draft = try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: .standard, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: PerformanceFixtures.executionArtifact, manualEvidenceDirectory: directory, pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256)

        let records = PerformanceFixtures.executionArtifact.records.sorted { $0.pairIndex < $1.pairIndex }
        XCTAssertEqual(draft.metrics.first { $0.metricID == .renderer }?.baselineSamples, records.map { PerformanceFixtures.baseline.renderer.frameMilliseconds[$0.baselineSampleIndex] })
        XCTAssertEqual(draft.metrics.first { $0.metricID == .compositor }?.baselineSamples, records.map { PerformanceFixtures.baseline.compositor.frameMilliseconds[$0.baselineSampleIndex] })
        XCTAssertEqual(draft.metrics.first { $0.metricID == .combinedFrame }?.baselineSamples, records.map { PerformanceFixtures.baseline.combinedFrame.frameMilliseconds[$0.baselineSampleIndex] })
        XCTAssertEqual(draft.metrics.first { $0.metricID == .redrawLayout }?.baselineSamples, records.map { PerformanceFixtures.baseline.redrawLayout.sampleMilliseconds[$0.baselineSampleIndex] })
        XCTAssertEqual(draft.metrics.first { $0.metricID == .responsiveness }?.baselineSamples, records.map { PerformanceFixtures.baseline.responsiveness.responseMilliseconds[$0.baselineSampleIndex] })
        XCTAssertEqual(draft.metrics.first { $0.metricID == .inputToVisible }?.baselineSamples, records.map { PerformanceFixtures.baseline.inputToVisible.sampleMilliseconds[$0.baselineSampleIndex] })
        XCTAssertNotEqual(draft.metrics.first { $0.metricID == .renderer }?.baselineSamples, Array(repeating: PerformanceFixtures.baseline.renderer.p95Milliseconds, count: 30))
    }

    func testComparisonBootstrapUsesKnownDeterministicVectorAndChangesWithSeed() throws {
        let deltas = [-2.0, -1.0, 0.0, 1.0]
        let expected = BootstrapInterval(lowerDelta: -1.75, upperDelta: 1.0, seed: 48271, resampleCount: 32)
        XCTAssertEqual(PerformanceComparisonHarness.bootstrapInterval(deltas: deltas, seed: 48271, resampleCount: 32), expected)
        XCTAssertEqual(
            PerformanceComparisonHarness.bootstrapInterval(deltas: deltas, seed: 48271, resampleCount: 32),
            PerformanceComparisonHarness.bootstrapInterval(deltas: deltas, seed: 48271, resampleCount: 32)
        )
        XCTAssertNotEqual(
            PerformanceComparisonHarness.bootstrapInterval(deltas: deltas, seed: 48271, resampleCount: 32),
            PerformanceComparisonHarness.bootstrapInterval(deltas: deltas, seed: 48272, resampleCount: 32)
        )
    }

    func testComparisonImprovementClaimRequiresStrictlyNegativeBootstrapUpperBound() throws {
        let directory = try makeManualEvidenceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let unchanged = try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: .standard, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: PerformanceFixtures.executionArtifact, manualEvidenceDirectory: directory, pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256)
        XCTAssertTrue(unchanged.metrics.allSatisfy { !$0.improvementClaimed })

        let improvedModel = ModelMeasurement(status: .measured, trialNanoseconds: Array(repeating: 1_000_000, count: 30), medianNanoseconds: 1_000_000, p95Nanoseconds: 1_000_000, madNanoseconds: 0, publicationCount: PerformanceFixtures.model.publicationCount, modelChecksum: PerformanceFixtures.model.modelChecksum, finalStateValid: true)
        let improved = try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.report(model: improvedModel), configuration: .standard, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: PerformanceFixtures.executionArtifact, manualEvidenceDirectory: directory, pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256)
        XCTAssertTrue(try XCTUnwrap(improved.metrics.first { $0.metricID == .model }).improvementClaimed)
    }

    func testComparisonRejectsTamperedBootstrapSummary() throws {
        let directory = try makeManualEvidenceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let draft = try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: .standard, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: PerformanceFixtures.executionArtifact, manualEvidenceDirectory: directory, pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256)
        let value = draft.metrics[0]
        var tampered = draft.metrics
        tampered[0] = MetricComparison(metricID: value.metricID, evidenceClass: value.evidenceClass, unit: value.unit, baselineID: value.baselineID, candidateID: value.candidateID, baselineSamples: value.baselineSamples, candidateSamples: value.candidateSamples, ratios: value.ratios, deltas: value.deltas, budgetLimit: value.budgetLimit, bootstrapInterval: BootstrapInterval(lowerDelta: value.bootstrapInterval.lowerDelta + 1, upperDelta: value.bootstrapInterval.upperDelta + 1, seed: value.bootstrapInterval.seed, resampleCount: value.bootstrapInterval.resampleCount), manualEvidence: value.manualEvidence, disposition: value.disposition, improvementClaimed: value.improvementClaimed)
        XCTAssertThrowsError(try PerformanceFixtures.comparison(metrics: tampered).validateStructure())
    }

    func testComparisonLoadsOnlyExactValidManualEvidenceAndKeepsDeterministicMetricsSeparate() throws {
        let directory = try makeManualEvidenceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeManualEvidencePair(to: directory, pair: PerformanceFixtures.manualEvidencePair)

        let draft = try PerformanceComparisonHarness.compare(
            baseline: PerformanceFixtures.baseline,
            candidate: PerformanceFixtures.candidate,
            configuration: PerformanceConfiguration.standard,
            eligibility: PerformanceFixtures.eligibility,
            pairExecutionArtifact: PerformanceFixtures.executionArtifact,
            manualEvidenceDirectory: directory,
            pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256
        )
        let manual = try XCTUnwrap(draft.metrics.first { $0.metricID == .inputToVisible })
        XCTAssertEqual(manual.evidenceClass, .manual)
        XCTAssertEqual(manual.manualEvidence, PerformanceFixtures.manualEvidencePair)
        XCTAssertNil(draft.metrics.first { $0.metricID == .model }?.manualEvidence)
    }

    func testComparisonRejectsMalformedUnknownDuplicateAndMismatchedManualEvidenceFiles() throws {
        let cases: [(String, (URL) throws -> Void)] = [
            ("malformed", { directory in
                try Data("not-json".utf8).write(to: directory.appendingPathComponent("inputToVisible.json"))
            }),
            ("unknown", { directory in
                try Data("{}".utf8).write(to: directory.appendingPathComponent("model.json"))
            }),
            ("wrong-file-name", { directory in
                try self.writeManualEvidencePair(to: directory, pair: PerformanceFixtures.manualEvidencePair, fileName: "compositor.json")
            }),
            ("wrong-host", { directory in
                let pair = PerformanceFixtures.manualEvidencePair
                try self.writeManualEvidencePair(to: directory, pair: ManualMetricEvidencePair(procedureVersion: pair.procedureVersion, pairOrders: pair.pairOrders, baseline: pair.baseline, candidate: self.replacing(pair.candidate, host: "another-host")))
            }),
            ("missing-permission", { directory in
                let pair = PerformanceFixtures.manualEvidencePair
                try self.writeManualEvidencePair(to: directory, pair: ManualMetricEvidencePair(procedureVersion: pair.procedureVersion, pairOrders: pair.pairOrders, baseline: self.replacing(pair.baseline, permissions: []), candidate: pair.candidate))
            }),
            ("wrong-path", { directory in
                let pair = PerformanceFixtures.manualEvidencePair
                try self.writeManualEvidencePair(to: directory, pair: ManualMetricEvidencePair(procedureVersion: pair.procedureVersion, pairOrders: pair.pairOrders, baseline: pair.baseline, candidate: self.replacing(pair.candidate, evidencePath: "other.json")))
            }),
            ("hidden-unknown", { directory in
                try Data("{}".utf8).write(to: directory.appendingPathComponent(".extra.json"))
            }),
            ("symlink", { directory in
                let backingDirectory = directory.deletingLastPathComponent().appendingPathComponent("pointer-manual-back-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: backingDirectory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: backingDirectory) }
                try self.writeManualEvidencePair(to: backingDirectory, pair: PerformanceFixtures.manualEvidencePair, fileName: "backing.json")
                try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("inputToVisible.json"), withDestinationURL: backingDirectory.appendingPathComponent("backing.json"))
            }),
        ]

        for (label, populate) in cases {
            let directory = try makeManualEvidenceDirectory()
            try populate(directory)
            XCTAssertThrowsError(try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: .standard, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: PerformanceFixtures.executionArtifact, manualEvidenceDirectory: directory, pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256), label)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    func testComparisonMapsCompletedResilienceWithoutFabricatingAcceptance() throws {
        let directory = try makeManualEvidenceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let draft = try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: .standard, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: PerformanceFixtures.executionArtifact, manualEvidenceDirectory: directory, pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256)
        XCTAssertEqual(draft.resilience, PerformanceFixtures.candidate.resilience)
        XCTAssertTrue(draft.resilience.cases.allSatisfy { $0.status == .measured && !$0.leakedResource && !$0.unexpectedGrowth })
        XCTAssertEqual(draft.disposition, .acceptedNoRegression)
    }

    func testComparisonProducesReviseDispositionForRatioRegression() throws {
        let directory = try makeManualEvidenceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let slowerModel = ModelMeasurement(status: .measured, trialNanoseconds: Array(repeating: 2_000_000, count: 30), medianNanoseconds: 2_000_000, p95Nanoseconds: 2_000_000, madNanoseconds: 0, publicationCount: PerformanceFixtures.model.publicationCount, modelChecksum: PerformanceFixtures.model.modelChecksum, finalStateValid: true)
        let slowerCandidate = PerformanceFixtures.report(model: slowerModel)

        let draft = try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: slowerCandidate, configuration: .standard, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: PerformanceFixtures.executionArtifact, manualEvidenceDirectory: directory, pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256)
        let model = try XCTUnwrap(draft.metrics.first { $0.metricID == .model })
        XCTAssertEqual(model.disposition, .revise)
        XCTAssertEqual(draft.disposition, .revise)
    }

    func testWriterRecomputesSuppliedDraftBeforePersisting() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("pointer-recompute-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let baselineURL = temp.appendingPathComponent("baseline.json")
        let candidateURL = temp.appendingPathComponent("candidate.json")
        try JSONEncoder().encode(PerformanceFixtures.baseline).write(to: baselineURL)
        try JSONEncoder().encode(PerformanceFixtures.candidate).write(to: candidateURL)
        let manualDirectory = try makeManualEvidenceDirectory()
        defer { try? FileManager.default.removeItem(at: manualDirectory) }
        let pairArtifact = makeArtifact(baselineData: try Data(contentsOf: baselineURL), candidateData: try Data(contentsOf: candidateURL))
        let pairExecutionURL = temp.appendingPathComponent("pairs.json")
        try PerformancePairExecutionArtifact.canonicalData(for: pairArtifact).write(to: pairExecutionURL)
        let expected = try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: .standard, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: pairArtifact, manualEvidenceDirectory: manualDirectory, pairExecutionArtifactSHA256: PerformanceFixtures.sha256(try Data(contentsOf: pairExecutionURL)))
        _ = try PerformanceComparisonHarness.writeComparison(draft: expected, baselineURL: baselineURL, candidateURL: candidateURL, pairExecutionURL: pairExecutionURL, manualEvidenceDirectory: manualDirectory, outputDirectory: temp.appendingPathComponent("valid"), configuration: .standard, eligibility: PerformanceFixtures.eligibility)

        var syntheticMetrics = expected.metrics
        let value = syntheticMetrics[0]
        syntheticMetrics[0] = MetricComparison(metricID: value.metricID, evidenceClass: value.evidenceClass, unit: value.unit, baselineID: value.baselineID, candidateID: value.candidateID, baselineSamples: value.baselineSamples, candidateSamples: Array(repeating: value.candidateSamples[0], count: value.candidateSamples.count), ratios: value.ratios, deltas: value.deltas, budgetLimit: value.budgetLimit, bootstrapInterval: value.bootstrapInterval, manualEvidence: value.manualEvidence, disposition: value.disposition, improvementClaimed: value.improvementClaimed)
        let stale = PerformanceComparisonDraft(harnessVersion: expected.harnessVersion, foundationIdentity: expected.foundationIdentity, buildContractVersion: expected.buildContractVersion, baselineBuildProvenance: expected.baselineBuildProvenance, candidateBuildProvenance: expected.candidateBuildProvenance, baselineRunProvenance: expected.baselineRunProvenance, candidateRunProvenance: expected.candidateRunProvenance, pairEligibility: expected.pairEligibility, pairExecutionArtifact: expected.pairExecutionArtifact, pairExecutionArtifactSHA256: expected.pairExecutionArtifactSHA256, baselineFixture: expected.baselineFixture, candidateFixture: expected.candidateFixture, baselineMeasurementIdentity: expected.baselineMeasurementIdentity, candidateMeasurementIdentity: expected.candidateMeasurementIdentity, baselineID: expected.baselineID, candidateID: expected.candidateID, metrics: syntheticMetrics, resilience: expected.resilience, seed: expected.seed, resampleCount: expected.resampleCount, disposition: expected.disposition)
        let outputDirectory = temp.appendingPathComponent("stale")
        XCTAssertThrowsError(try PerformanceComparisonHarness.writeComparison(draft: stale, baselineURL: baselineURL, candidateURL: candidateURL, pairExecutionURL: pairExecutionURL, manualEvidenceDirectory: manualDirectory, outputDirectory: outputDirectory, configuration: .standard, eligibility: PerformanceFixtures.eligibility))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent("paired-comparison.json").path))
    }

    func testObservedPairArtifactDrivesOrderAndSampleIndices() throws {
        let directory = try makeManualEvidenceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifact = PerformanceFixtures.executionArtifact
        let draft = try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: .standard, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: artifact, manualEvidenceDirectory: directory, pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256)

        XCTAssertEqual(draft.pairExecutionArtifact, artifact)
        let records = artifact.records.sorted { $0.pairIndex < $1.pairIndex }
        XCTAssertEqual(records.filter { $0.order == .baselineFirst }.count, 15)
        XCTAssertEqual(records.filter { $0.order == .candidateFirst }.count, 15)
        let renderer = try XCTUnwrap(draft.metrics.first { $0.metricID == .renderer })
        XCTAssertEqual(renderer.baselineSamples, records.map { PerformanceFixtures.baseline.renderer.frameMilliseconds[$0.baselineSampleIndex] })
        XCTAssertEqual(renderer.candidateSamples, records.map { PerformanceFixtures.candidate.renderer.frameMilliseconds[$0.candidateSampleIndex] })
    }

    func testComparisonRejectsForgedObservedPairArtifact() throws {
        let directory = try makeManualEvidenceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = PerformanceFixtures.executionArtifact.records
        let forgedOrder = PerformancePairExecutionRecord(pairIndex: original[0].pairIndex, order: .candidateFirst, baselineSampleIndex: original[0].baselineSampleIndex, candidateSampleIndex: original[0].candidateSampleIndex, baselineStartedAtUTC: original[0].baselineStartedAtUTC, candidateStartedAtUTC: original[0].candidateStartedAtUTC, baselineEndedAtUTC: original[0].baselineEndedAtUTC, candidateEndedAtUTC: original[0].candidateEndedAtUTC)
        let forged = PerformancePairExecutionArtifact(schemaVersion: PerformanceFixtures.executionArtifact.schemaVersion, baselineID: PerformanceFixtures.executionArtifact.baselineID, candidateID: PerformanceFixtures.executionArtifact.candidateID, baselineMeasurementReportSHA256: PerformanceFixtures.executionArtifact.baselineMeasurementReportSHA256, candidateMeasurementReportSHA256: PerformanceFixtures.executionArtifact.candidateMeasurementReportSHA256, records: [forgedOrder] + Array(original.dropFirst()))
        XCTAssertThrowsError(try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: .standard, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: forged, manualEvidenceDirectory: directory, pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256))
    }

    func testComparisonRejectsValidCountArtifactWithPermutedOrderSequence() throws {
        let directory = try makeManualEvidenceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = PerformanceFixtures.executionArtifact.records
        let first = original[0]
        let fifteenth = original[15]
        let swappedFirst = PerformancePairExecutionRecord(pairIndex: first.pairIndex, order: .candidateFirst, baselineSampleIndex: first.baselineSampleIndex, candidateSampleIndex: first.candidateSampleIndex, baselineStartedAtUTC: first.candidateStartedAtUTC, candidateStartedAtUTC: first.baselineStartedAtUTC, baselineEndedAtUTC: first.candidateEndedAtUTC, candidateEndedAtUTC: first.baselineEndedAtUTC)
        let swappedFifteenth = PerformancePairExecutionRecord(pairIndex: fifteenth.pairIndex, order: .baselineFirst, baselineSampleIndex: fifteenth.baselineSampleIndex, candidateSampleIndex: fifteenth.candidateSampleIndex, baselineStartedAtUTC: fifteenth.candidateStartedAtUTC, candidateStartedAtUTC: fifteenth.baselineStartedAtUTC, baselineEndedAtUTC: fifteenth.candidateEndedAtUTC, candidateEndedAtUTC: fifteenth.baselineEndedAtUTC)
        var records = original
        records[0] = swappedFirst
        records[15] = swappedFifteenth
        let forged = PerformancePairExecutionArtifact(schemaVersion: PerformanceFixtures.executionArtifact.schemaVersion, baselineID: PerformanceFixtures.executionArtifact.baselineID, candidateID: PerformanceFixtures.executionArtifact.candidateID, baselineMeasurementReportSHA256: PerformanceFixtures.executionArtifact.baselineMeasurementReportSHA256, candidateMeasurementReportSHA256: PerformanceFixtures.executionArtifact.candidateMeasurementReportSHA256, records: records)
        let forgedHash = PerformanceFixtures.sha256(try PerformancePairExecutionArtifact.canonicalData(for: forged))
        XCTAssertThrowsError(try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: .standard, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: forged, manualEvidenceDirectory: directory, pairExecutionArtifactSHA256: forgedHash))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).isEmpty)
    }

    func testComparisonRejectsPairEndBoundaryAndCrossPairOverlap() throws {
        let directory = try makeManualEvidenceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = PerformanceFixtures.executionArtifact.records

        let first = original[0]
        var endBoundaryRecords = original
        endBoundaryRecords[0] = PerformancePairExecutionRecord(pairIndex: first.pairIndex, order: first.order, baselineSampleIndex: first.baselineSampleIndex, candidateSampleIndex: first.candidateSampleIndex, baselineStartedAtUTC: first.baselineStartedAtUTC, candidateStartedAtUTC: first.candidateStartedAtUTC, baselineEndedAtUTC: first.candidateStartedAtUTC, candidateEndedAtUTC: first.candidateEndedAtUTC)
        let endBoundaryArtifact = PerformancePairExecutionArtifact(baselineID: PerformanceFixtures.executionArtifact.baselineID, candidateID: PerformanceFixtures.executionArtifact.candidateID, baselineMeasurementReportSHA256: PerformanceFixtures.executionArtifact.baselineMeasurementReportSHA256, candidateMeasurementReportSHA256: PerformanceFixtures.executionArtifact.candidateMeasurementReportSHA256, records: endBoundaryRecords)
        let endBoundaryHash = PerformanceFixtures.sha256(try PerformancePairExecutionArtifact.canonicalData(for: endBoundaryArtifact))
        XCTAssertThrowsError(try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: .standard, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: endBoundaryArtifact, manualEvidenceDirectory: directory, pairExecutionArtifactSHA256: endBoundaryHash))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).isEmpty)

        var overlapRecords = original
        let second = original[1]
        overlapRecords[1] = PerformancePairExecutionRecord(pairIndex: second.pairIndex, order: second.order, baselineSampleIndex: second.baselineSampleIndex, candidateSampleIndex: second.candidateSampleIndex, baselineStartedAtUTC: "2026-08-31T12:00:03Z", candidateStartedAtUTC: "2026-08-31T12:00:05Z", baselineEndedAtUTC: "2026-08-31T12:00:04Z", candidateEndedAtUTC: "2026-08-31T12:00:06Z")
        let overlapArtifact = PerformancePairExecutionArtifact(baselineID: PerformanceFixtures.executionArtifact.baselineID, candidateID: PerformanceFixtures.executionArtifact.candidateID, baselineMeasurementReportSHA256: PerformanceFixtures.executionArtifact.baselineMeasurementReportSHA256, candidateMeasurementReportSHA256: PerformanceFixtures.executionArtifact.candidateMeasurementReportSHA256, records: overlapRecords)
        let overlapHash = PerformanceFixtures.sha256(try PerformancePairExecutionArtifact.canonicalData(for: overlapArtifact))
        XCTAssertThrowsError(try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: .standard, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: overlapArtifact, manualEvidenceDirectory: directory, pairExecutionArtifactSHA256: overlapHash))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).isEmpty)
    }

    func testComparisonRejectsManualEvidenceProcedureMismatch() throws {
        let directory = try makeManualEvidenceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pair = PerformanceFixtures.manualEvidencePair
        let candidate = replacing(pair.candidate, steps: "Different procedure")
        try writeManualEvidencePair(to: directory, pair: ManualMetricEvidencePair(procedureVersion: pair.procedureVersion, pairOrders: pair.pairOrders, baseline: pair.baseline, candidate: candidate))
        XCTAssertThrowsError(try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: .standard, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: PerformanceFixtures.executionArtifact, manualEvidenceDirectory: directory, pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256))
    }

    func testComparisonUsesIdentityBoundManualEvidencePairSamples() throws {
        let directory = try makeManualEvidenceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeManualEvidencePair(to: directory, pair: PerformanceFixtures.manualEvidencePair)
        let draft = try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: .standard, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: PerformanceFixtures.executionArtifact, manualEvidenceDirectory: directory, pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256)
        let metric = try XCTUnwrap(draft.metrics.first { $0.metricID == .inputToVisible })
        XCTAssertEqual(metric.manualEvidence, PerformanceFixtures.manualEvidencePair)
        XCTAssertEqual(metric.baselineSamples, PerformanceFixtures.manualEvidencePair.baseline.samples)
        XCTAssertEqual(metric.candidateSamples, PerformanceFixtures.manualEvidencePair.candidate.samples)
    }

    func testComparisonRejectsManualCandidateSamplesThatDoNotMatchRecordedIndices() throws {
        let directory = try makeManualEvidenceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pair = PerformanceFixtures.manualEvidencePair
        let tamperedCandidate = replacing(pair.candidate, samples: Array(repeating: 99, count: 30))
        try writeManualEvidencePair(to: directory, pair: ManualMetricEvidencePair(procedureVersion: pair.procedureVersion, pairOrders: pair.pairOrders, baseline: pair.baseline, candidate: tamperedCandidate))
        XCTAssertThrowsError(try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: .standard, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: PerformanceFixtures.executionArtifact, manualEvidenceDirectory: directory, pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256))
    }

    func testComparisonRejectsStaleManualEvidenceIdentity() throws {
        let directory = try makeManualEvidenceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let evidence = PerformanceFixtures.manualEvidencePair.candidate
        let staleCandidate = ManualMetricEvidence(metricID: evidence.metricID, evidenceClass: evidence.evidenceClass, variant: evidence.variant, sourceCommitSHA: String(repeating: "1", count: 40), measurementReportSHA256: evidence.measurementReportSHA256, pairExecutionArtifactSHA256: evidence.pairExecutionArtifactSHA256, host: evidence.host, recordedAt: evidence.recordedAt, permissions: evidence.permissions, steps: evidence.steps, samples: evidence.samples, result: evidence.result, evidencePath: evidence.evidencePath)
        let stale = ManualMetricEvidencePair(procedureVersion: PerformanceFixtures.manualEvidencePair.procedureVersion, pairOrders: PerformanceFixtures.manualEvidencePair.pairOrders, baseline: PerformanceFixtures.manualEvidencePair.baseline, candidate: staleCandidate)
        try writeManualEvidencePair(to: directory, pair: stale)
        XCTAssertThrowsError(try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: .standard, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: PerformanceFixtures.executionArtifact, manualEvidenceDirectory: directory, pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256))
    }

    func testReportRejectsTamperedEmbeddedArtifactAgainstCanonicalHash() throws {
        var records = PerformanceFixtures.executionArtifact.records
        let first = records[0]
        let second = records[1]
        records[0] = PerformancePairExecutionRecord(pairIndex: first.pairIndex, order: first.order, baselineSampleIndex: second.baselineSampleIndex, candidateSampleIndex: first.candidateSampleIndex, baselineStartedAtUTC: first.baselineStartedAtUTC, candidateStartedAtUTC: first.candidateStartedAtUTC, baselineEndedAtUTC: first.baselineEndedAtUTC, candidateEndedAtUTC: first.candidateEndedAtUTC)
        records[1] = PerformancePairExecutionRecord(pairIndex: second.pairIndex, order: second.order, baselineSampleIndex: first.baselineSampleIndex, candidateSampleIndex: second.candidateSampleIndex, baselineStartedAtUTC: second.baselineStartedAtUTC, candidateStartedAtUTC: second.candidateStartedAtUTC, baselineEndedAtUTC: second.baselineEndedAtUTC, candidateEndedAtUTC: second.candidateEndedAtUTC)
        let tampered = PerformancePairExecutionArtifact(baselineID: PerformanceFixtures.executionArtifact.baselineID, candidateID: PerformanceFixtures.executionArtifact.candidateID, baselineMeasurementReportSHA256: PerformanceFixtures.executionArtifact.baselineMeasurementReportSHA256, candidateMeasurementReportSHA256: PerformanceFixtures.executionArtifact.candidateMeasurementReportSHA256, records: records)
        let report = PerformanceFixtures.comparison(pairExecutionArtifact: tampered, pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256)
        XCTAssertThrowsError(try report.validateStructure())
    }

    func testWriterRejectsNonCanonicalAndRecursivelyUnknownPairArtifactBytes() throws {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("pointer-artifact-shape-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let baselineURL = temp.appendingPathComponent("baseline.json")
        let candidateURL = temp.appendingPathComponent("candidate.json")
        try JSONEncoder().encode(PerformanceFixtures.baseline).write(to: baselineURL)
        try JSONEncoder().encode(PerformanceFixtures.candidate).write(to: candidateURL)
        let manualDirectory = temp.appendingPathComponent("manual", isDirectory: true)
        try FileManager.default.createDirectory(at: manualDirectory, withIntermediateDirectories: true)
        let pairURL = temp.appendingPathComponent("pairs.json")
        let canonical = try PerformancePairExecutionArtifact.canonicalData(for: PerformanceFixtures.executionArtifact)
        var noncanonical = Data([10])
        noncanonical.append(canonical)
        try noncanonical.write(to: pairURL)
        XCTAssertThrowsError(try PerformanceComparisonHarness.writeComparison(draft: PerformanceFixtures.draft(), baselineURL: baselineURL, candidateURL: candidateURL, pairExecutionURL: pairURL, manualEvidenceDirectory: manualDirectory, outputDirectory: temp.appendingPathComponent("newline"), configuration: .standard, eligibility: PerformanceFixtures.eligibility))

        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: canonical) as? [String: Any])
        var records = try XCTUnwrap(object["records"] as? [[String: Any]])
        records[0]["unexpected"] = true
        object["records"] = records
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(to: pairURL)
        XCTAssertThrowsError(try PerformanceComparisonHarness.writeComparison(draft: PerformanceFixtures.draft(), baselineURL: baselineURL, candidateURL: candidateURL, pairExecutionURL: pairURL, manualEvidenceDirectory: manualDirectory, outputDirectory: temp.appendingPathComponent("unknown"), configuration: .standard, eligibility: PerformanceFixtures.eligibility))
    }

    func testManualCompositorEvidenceUsesObservedSamples() throws {
        let directory = try makeManualEvidenceDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let records = PerformanceFixtures.executionArtifact.records.sorted { $0.pairIndex < $1.pairIndex }
        let manual = makeEvidencePair(metricID: .compositor, baselineSamples: records.map { PerformanceFixtures.baseline.compositor.frameMilliseconds[$0.baselineSampleIndex] }, candidateSamples: records.map { PerformanceFixtures.candidate.compositor.frameMilliseconds[$0.candidateSampleIndex] }, fileName: "compositor.json")
        try writeManualEvidencePair(to: directory, pair: manual, fileName: "compositor.json")

        let draft = try PerformanceComparisonHarness.compare(baseline: PerformanceFixtures.baseline, candidate: PerformanceFixtures.candidate, configuration: .standard, eligibility: PerformanceFixtures.eligibility, pairExecutionArtifact: PerformanceFixtures.executionArtifact, manualEvidenceDirectory: directory, pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256)
        XCTAssertEqual(draft.metrics.first { $0.metricID == .compositor }?.disposition, .acceptedNoRegression)
        XCTAssertEqual(draft.disposition, .acceptedNoRegression)
    }

    private func makeManualEvidenceDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("pointer-manual-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func writeManualEvidencePair(to directory: URL, pair: ManualMetricEvidencePair, fileName: String = "inputToVisible.json") throws {
        let data = try ManualMetricAdapter.canonicalData(from: JSONEncoder().encode(ManualMetricAdapter(evidence: pair)))
        try data.write(to: directory.appendingPathComponent(fileName))
    }

    private func makeArtifact(baselineData: Data, candidateData: Data) -> PerformancePairExecutionArtifact {
        PerformancePairExecutionArtifact(
            baselineID: PerformanceFixtures.baselineCommit,
            candidateID: PerformanceFixtures.commit,
            baselineMeasurementReportSHA256: PerformanceFixtures.sha256(baselineData),
            candidateMeasurementReportSHA256: PerformanceFixtures.sha256(candidateData),
            records: PerformanceFixtures.executionArtifact.records
        )
    }

    private func makeEvidencePair(metricID: PerformanceMetricID, baselineSamples: [Double], candidateSamples: [Double], fileName: String) -> ManualMetricEvidencePair {
        let artifact = PerformanceFixtures.executionArtifact
        let orders = artifact.records.sorted { $0.pairIndex < $1.pairIndex }.map(\.order)
        let baseline = ManualMetricEvidence(metricID: metricID, evidenceClass: .manual, variant: "baseline", sourceCommitSHA: PerformanceFixtures.baselineCommit, measurementReportSHA256: PerformanceFixtures.baselineMeasurementReportSHA256, pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256, host: PerformanceFixtures.host.machineIdentifier, recordedAt: PerformanceFixtures.recordedAtUTC, permissions: ["Screen Recording"], steps: "Measure the metric.", samples: baselineSamples, result: "Manual samples recorded.", evidencePath: fileName)
        let candidate = ManualMetricEvidence(metricID: metricID, evidenceClass: .manual, variant: "candidate", sourceCommitSHA: PerformanceFixtures.commit, measurementReportSHA256: PerformanceFixtures.candidateMeasurementReportSHA256, pairExecutionArtifactSHA256: PerformanceFixtures.executionArtifactSHA256, host: PerformanceFixtures.host.machineIdentifier, recordedAt: PerformanceFixtures.recordedAtUTC, permissions: ["Screen Recording"], steps: "Measure the metric.", samples: candidateSamples, result: "Manual samples recorded.", evidencePath: fileName)
        return ManualMetricEvidencePair(procedureVersion: "pointer-manual-procedure/v1", pairOrders: orders, baseline: baseline, candidate: candidate)
    }

    private func replacing(_ evidence: ManualMetricEvidence, host: String? = nil, permissions: [String]? = nil, samples: [Double]? = nil, steps: String? = nil, evidencePath: String? = nil) -> ManualMetricEvidence {
        ManualMetricEvidence(metricID: evidence.metricID, evidenceClass: evidence.evidenceClass, variant: evidence.variant, sourceCommitSHA: evidence.sourceCommitSHA, measurementReportSHA256: evidence.measurementReportSHA256, pairExecutionArtifactSHA256: evidence.pairExecutionArtifactSHA256, host: host ?? evidence.host, recordedAt: evidence.recordedAt, permissions: permissions ?? evidence.permissions, steps: steps ?? evidence.steps, samples: samples ?? evidence.samples, result: evidence.result, evidencePath: evidencePath ?? evidence.evidencePath)
    }

    private func extractPublicSymbolGraph(moduleDirectory: URL, sdkPath: String) throws -> [String: Any] {
        let fileManager = FileManager.default
        let outputDirectory = fileManager.temporaryDirectory.appendingPathComponent("pointer-public-symbols-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: outputDirectory) }

        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "swift-symbolgraph-extract",
            "-module-name", "PointerAppKit",
            "-I", moduleDirectory.path,
            "-sdk", sdkPath,
            "-target", swiftTargetTriple(),
            "-minimum-access-level", "public",
            "-skip-synthesized-members",
            "-output-dir", outputDirectory.path
        ]
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        process.waitUntilExit()

        let diagnostics = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "PerformanceComparisonHarnessTests", code: 4, userInfo: [NSLocalizedDescriptionKey: "Public symbol graph extraction failed: \(diagnostics)"])
        }
        let graphURL = outputDirectory.appendingPathComponent("PointerAppKit.symbols.json")
        let graphData = try Data(contentsOf: graphURL)
        guard !graphData.isEmpty,
              let graph = try JSONSerialization.jsonObject(with: graphData) as? [String: Any]
        else {
            throw NSError(domain: "PerformanceComparisonHarnessTests", code: 5, userInfo: [NSLocalizedDescriptionKey: "Public symbol graph is empty or invalid"])
        }
        return graph
    }

    private func assertPublicSurfaceSymbolGraph(_ graph: [String: Any]) {
        guard let module = graph["module"] as? [String: Any],
              let moduleName = module["name"] as? String,
              let platform = module["platform"] as? [String: Any],
              let architecture = platform["architecture"] as? String,
              let vendor = platform["vendor"] as? String,
              let operatingSystem = platform["operatingSystem"] as? [String: Any],
              let operatingSystemName = operatingSystem["name"] as? String,
              let symbols = graph["symbols"] as? [[String: Any]],
              !symbols.isEmpty
        else {
            XCTFail("Public symbol graph has no valid module identity or symbols")
            return
        }
        XCTAssertEqual(moduleName, "PointerAppKit")
        XCTAssertEqual(architecture, swiftTargetArchitecture())
        XCTAssertEqual(vendor, "apple")
        XCTAssertEqual(operatingSystemName, "macosx")

        let relevantSymbols = symbols.filter { symbol in
            guard let path = symbol["pathComponents"] as? [String] else {
                return false
            }
            return path.first == "PerformanceComparisonDraft" || path.first == "PerformanceComparisonHarness"
        }
        XCTAssertFalse(relevantSymbols.isEmpty, "Public symbol graph did not contain comparison API declarations")

        func symbolKey(_ symbol: [String: Any]) -> String? {
            guard let kind = (symbol["kind"] as? [String: Any])?["identifier"] as? String,
                  let path = symbol["pathComponents"] as? [String],
                  let accessLevel = symbol["accessLevel"] as? String,
                  let fragments = symbol["declarationFragments"] as? [[String: Any]]
            else {
                return nil
            }
            let declaration = fragments.compactMap { $0["spelling"] as? String }.joined()
            return [kind, path.joined(separator: "."), declaration, accessLevel].joined(separator: "|")
        }

        let expectedSymbols: Set<String> = [
            "swift.struct|PerformanceComparisonDraft|struct PerformanceComparisonDraft|public",
            "swift.enum|PerformanceComparisonHarness|@MainActor enum PerformanceComparisonHarness|public",
            "swift.type.method|PerformanceComparisonHarness.writeComparison(draft:baselineURL:candidateURL:pairExecutionURL:manualEvidenceDirectory:outputDirectory:configuration:eligibility:)|@MainActor static func writeComparison(draft: PerformanceComparisonDraft, baselineURL: URL, candidateURL: URL, pairExecutionURL: URL, manualEvidenceDirectory: URL, outputDirectory: URL, configuration: PerformanceConfiguration, eligibility: PerformancePairEligibility) throws -> PerformanceComparisonReport|public"
        ]
        XCTAssertEqual(Set(relevantSymbols.compactMap(symbolKey)), expectedSymbols, "Comparison public symbol inventory changed")

        guard let draftID = relevantSymbols.first(where: { ($0["pathComponents"] as? [String]) == ["PerformanceComparisonDraft"] }).flatMap({ ($0["identifier"] as? [String: Any])?["precise"] as? String }),
              let harnessID = relevantSymbols.first(where: { ($0["pathComponents"] as? [String]) == ["PerformanceComparisonHarness"] }).flatMap({ ($0["identifier"] as? [String: Any])?["precise"] as? String }),
              let writerID = relevantSymbols.first(where: { ($0["pathComponents"] as? [String])?.first == "PerformanceComparisonHarness" && ($0["pathComponents"] as? [String])?.count == 2 }).flatMap({ ($0["identifier"] as? [String: Any])?["precise"] as? String })
        else {
            XCTFail("Comparison public symbol identifiers are incomplete")
            return
        }
        let relevantIDs = Set([draftID, harnessID, writerID])
        guard let relationships = graph["relationships"] as? [[String: Any]] else {
            XCTFail("Public symbol graph has no relationship inventory")
            return
        }

        func endpointName(_ identifier: String, relation: [String: Any]) -> String {
            switch identifier {
            case draftID:
                return "PerformanceComparisonDraft"
            case harnessID:
                return "PerformanceComparisonHarness"
            case writerID:
                return "PerformanceComparisonHarness.writeComparison(draft:baselineURL:candidateURL:pairExecutionURL:manualEvidenceDirectory:outputDirectory:configuration:eligibility:)"
            default:
                return relation["targetFallback"] as? String ?? identifier
            }
        }

        let actualRelationships = Set(relationships.compactMap { relation -> String? in
            guard let kind = relation["kind"] as? String,
                  let source = relation["source"] as? String,
                  let target = relation["target"] as? String,
                  relevantIDs.contains(source) || relevantIDs.contains(target)
            else {
                return nil
            }
            return [kind, endpointName(source, relation: relation), endpointName(target, relation: relation)].joined(separator: "|")
        })
        let expectedRelationships: Set<String> = [
            "memberOf|PerformanceComparisonHarness.writeComparison(draft:baselineURL:candidateURL:pairExecutionURL:manualEvidenceDirectory:outputDirectory:configuration:eligibility:)|PerformanceComparisonHarness",
            "conformsTo|PerformanceComparisonHarness|Swift.Sendable",
            "conformsTo|PerformanceComparisonHarness|Swift.SendableMetatype",
            "conformsTo|PerformanceComparisonDraft|Swift.Sendable",
            "conformsTo|PerformanceComparisonDraft|Swift.Equatable",
            "conformsTo|PerformanceComparisonDraft|Swift.SendableMetatype"
        ]
        XCTAssertEqual(actualRelationships, expectedRelationships, "Comparison public symbol relationships changed")
    }

    private func swiftTargetArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "arm64"
        #endif
    }

    private func swiftTargetTriple() -> String {
        "\(swiftTargetArchitecture())-apple-macos14.0"
    }

    private func pointerAppKitModuleDirectory() throws -> URL {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let buildRoot = packageRoot.appendingPathComponent(".build", isDirectory: true)
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: buildRoot, includingPropertiesForKeys: nil, options: []) else {
            throw NSError(domain: "PerformanceComparisonHarnessTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to enumerate SwiftPM build products"])
        }
        let debugModules = enumerator.compactMap { element -> URL? in
            guard let url = element as? URL,
                  url.lastPathComponent == "PointerAppKit.swiftmodule",
                  url.pathComponents.contains("debug")
            else {
                return nil
            }
            return url.deletingLastPathComponent()
        }.sorted { $0.path < $1.path }
        if let moduleDirectory = debugModules.first {
            return moduleDirectory
        }
        throw NSError(domain: "PerformanceComparisonHarnessTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "PointerAppKit.swiftmodule was not built"])
    }

    private func macOSSDKPath() throws -> String {
        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--sdk", "macosx", "--show-sdk-path"]
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        process.waitUntilExit()
        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0, !output.isEmpty else {
            throw NSError(domain: "PerformanceComparisonHarnessTests", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to resolve the macOS SDK for external API probe: \(output)"])
        }
        return output
    }

    private func compileExternal(_ source: String, moduleDirectory: URL, sdkPath: String) throws -> (status: Int32, output: String) {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent("pointer-public-surface-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("PublicSurface.swift")
        try Data(source.utf8).write(to: sourceURL)

        let outputPipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["swiftc", "-typecheck", "-sdk", sdkPath, "-I", moduleDirectory.path, sourceURL.path]
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.currentDirectoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        try process.run()
        process.waitUntilExit()

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    private func assertExternalSuccess(_ result: (status: Int32, output: String), context: String) {
        XCTAssertEqual(result.status, 0, "\(context) did not compile:\n\(result.output)")
        let diagnostics = result.output.lowercased()
        XCTAssertFalse(diagnostics.contains("no such module") || diagnostics.contains("cannot find type") || diagnostics.contains("failed to load"), "\(context) could not resolve the imported module:\n\(result.output)")
    }
}
