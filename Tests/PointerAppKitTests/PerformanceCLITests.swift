import Foundation
import CryptoKit
import XCTest
@testable import PointerAppKit

@MainActor
final class PerformanceCLITests: XCTestCase {
    func testMetricSamplesCarryExplicitStatusAndStableDiagnosticInCanonicalOrder() throws {
        let samples = PerformanceMetricID.allCases.enumerated().map { index, metricID in
            if index == 1 {
                return PerformanceTrialMetricSample(metricID: metricID, unit: metricID.canonicalUnit, status: .unmeasured, value: nil, diagnostic: "windowserver-unavailable")
            }
            return PerformanceTrialMetricSample(metricID: metricID, unit: metricID.canonicalUnit, status: .measured, value: Double(index + 1), diagnostic: nil)
        }
        XCTAssertEqual(samples.map(\.metricID), PerformanceMetricID.allCases)
        XCTAssertNil(samples[1].value)
        XCTAssertEqual(samples[1].diagnostic, "windowserver-unavailable")
        let result = makeResult(variant: .baseline, pairIndex: 0, order: .baselineFirst, samples: samples)
        let resultData = try PerformanceCanonicalJSON.data(for: result)
        XCTAssertEqual(try PerformanceCanonicalJSON.decoded(PerformanceTrialResult.self, from: resultData), result)
        let sampleObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: resultData) as? [String: Any])
        let wireSamples = try XCTUnwrap(sampleObject["samples"] as? [[String: Any]])
        XCTAssertTrue(wireSamples.allSatisfy { Set($0.keys) == ["metricID", "unit", "status", "value", "diagnostic"] })
        var omittedValue = try XCTUnwrap(wireSamples[1])
        omittedValue.removeValue(forKey: "value")
        var omittedObject = sampleObject
        var omittedSamples = wireSamples
        omittedSamples[1] = omittedValue
        omittedObject["samples"] = omittedSamples
        let omittedData = try JSONSerialization.data(withJSONObject: omittedObject, options: [.sortedKeys])
        XCTAssertThrowsError(try JSONDecoder().decode(PerformanceTrialResult.self, from: omittedData))
        var unknownObject = sampleObject
        unknownObject["unknown"] = true
        let unknownData = try JSONSerialization.data(withJSONObject: unknownObject, options: [.sortedKeys])
        XCTAssertThrowsError(try PerformanceCanonicalJSON.decoded(PerformanceTrialResult.self, from: unknownData))
    }

    func testExactVersionedTrialWireTypesRoundTripAllCanonicalMetricSamples() throws {
        let request = PerformanceTrialRequest(
            schemaVersion: 1,
            variant: .baseline,
            fixtureProfile: .standard12,
            pairIndex: 0,
            order: .baselineFirst,
            sampleIndex: 0
        )
        let result = makeResult(
            variant: .baseline,
            pairIndex: 0,
            order: .baselineFirst,
            request: request
        )
        let data = try PerformanceCanonicalJSON.data(for: result)
        XCTAssertEqual(try PerformanceCanonicalJSON.decoded(PerformanceTrialResult.self, from: data), result)
        XCTAssertEqual(result.samples.map(\.metricID), PerformanceMetricID.allCases)
        XCTAssertEqual(result.warmupCountExecuted, 5)
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["unknown"] = true
        let unknownData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        XCTAssertThrowsError(try PerformanceCanonicalJSON.decoded(PerformanceTrialResult.self, from: unknownData))
    }

    func testDirectTrialDecodingRejectsUnknownKeysAtEveryPublicEnvelope() throws {
        let request = PerformanceTrialRequest(variant: .baseline, fixtureProfile: .standard12, pairIndex: 0, order: .baselineFirst, sampleIndex: 0)
        let requestData = try PerformanceCanonicalJSON.data(for: request)
        var requestObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: requestData) as? [String: Any])
        requestObject["unknown"] = true
        let unknownRequestData = try JSONSerialization.data(withJSONObject: requestObject, options: [.sortedKeys])
        XCTAssertThrowsError(try JSONDecoder().decode(PerformanceTrialRequest.self, from: unknownRequestData))

        let result = makeResult(variant: .baseline, pairIndex: 0, order: .baselineFirst)
        let resultData = try PerformanceCanonicalJSON.data(for: result)
        var resultObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: resultData) as? [String: Any])
        resultObject["unknown"] = true
        let unknownResultData = try JSONSerialization.data(withJSONObject: resultObject, options: [.sortedKeys])
        XCTAssertThrowsError(try JSONDecoder().decode(PerformanceTrialResult.self, from: unknownResultData))

        var evidenceObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: resultData) as? [String: Any])
        var modelEvidence = try XCTUnwrap(evidenceObject["modelEvidence"] as? [String: Any])
        modelEvidence["unknown"] = true
        evidenceObject["modelEvidence"] = modelEvidence
        let unknownEvidenceData = try JSONSerialization.data(withJSONObject: evidenceObject, options: [.sortedKeys])
        XCTAssertThrowsError(try JSONDecoder().decode(PerformanceTrialResult.self, from: unknownEvidenceData))
    }

    func testExternalTrialSidecarUsesExactNullableScalarWireShape() throws {
        let request = PerformanceTrialRequest(variant: .candidate, fixtureProfile: .standard12, pairIndex: 15, order: .candidateFirst, sampleIndex: 15)
        let binding = PerformanceExternalTrialBinding(
            request: request,
            sourceIdentity: PerformanceFixtures.build.sourceIdentity,
            runProvenanceSHA256: String(repeating: "a", count: 64),
            pairEligibilitySHA256: String(repeating: "b", count: 64),
            startedAtUTC: "2026-09-01T00:00:00.123Z",
            endedAtUTC: "2026-09-01T00:00:01.123Z"
        )
        let measurements = PerformanceExternalTrialSidecar.requiredMetricIDs.enumerated().map { index, metricID in
            PerformanceExternalTrialScalarMeasurement(metricID: metricID, unit: metricID.canonicalUnit, status: index == 0 ? .unmeasured : .measured, value: index == 0 ? nil : Double(index + 1), diagnostic: index == 0 ? "fixture-unavailable" : nil)
        }
        let sidecar = PerformanceExternalTrialSidecar(binding: binding, measurements: measurements)
        let data = try PerformanceCanonicalJSON.data(for: sidecar)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let wireMeasurements = try XCTUnwrap(root["measurements"] as? [[String: Any]])
        XCTAssertTrue(wireMeasurements.allSatisfy { Set($0.keys) == ["metricID", "unit", "status", "value", "diagnostic"] })
        XCTAssertTrue(wireMeasurements[0]["value"] is NSNull)
        XCTAssertTrue(wireMeasurements[1]["diagnostic"] is NSNull)
        XCTAssertEqual(try PerformanceCanonicalJSON.decoded(PerformanceExternalTrialSidecar.self, from: data), sidecar)
        var omitted = wireMeasurements[0]
        omitted.removeValue(forKey: "diagnostic")
        var omittedRoot = root
        var omittedMeasurements = wireMeasurements
        omittedMeasurements[0] = omitted
        omittedRoot["measurements"] = omittedMeasurements
        let omittedData = try JSONSerialization.data(withJSONObject: omittedRoot, options: [.sortedKeys])
        XCTAssertThrowsError(try JSONDecoder().decode(PerformanceExternalTrialSidecar.self, from: omittedData))
    }

    func testExternalAggregateSidecarRequiresThirtyOrderedResultHashes() throws {
        let sidecar = PerformanceExternalAggregateSidecar(
            binding: PerformanceExternalAggregateBinding(
                variant: .baseline,
                fixtureProfile: .standard12,
                sourceIdentity: PerformanceFixtures.baselineBuild.sourceIdentity,
                runProvenanceSHA256: String(repeating: "0", count: 64),
                pairEligibilitySHA256: String(repeating: "0", count: 64)
            ),
            resultSHA256s: Array(repeating: String(repeating: "a", count: 64), count: 30),
            memory: PerformanceFixtures.memory,
            resilience: PerformanceFixtures.resilience
        )
        XCTAssertNoThrow(try sidecar.validate())
        let data = try PerformanceCanonicalJSON.data(for: sidecar)
        XCTAssertEqual(try PerformanceCanonicalJSON.decoded(PerformanceExternalAggregateSidecar.self, from: data), sidecar)
        let wrongCount = PerformanceExternalAggregateSidecar(binding: sidecar.binding, resultSHA256s: Array(repeating: String(repeating: "a", count: 64), count: 29), memory: sidecar.memory, resilience: sidecar.resilience)
        XCTAssertThrowsError(try wrongCount.validate())
    }

    func testTrialRunnerExecutesExactlyFiveWarmupsAndOneScalarSample() throws {
        let request = PerformanceTrialRequest(
            variant: .baseline,
            fixtureProfile: .standard12,
            pairIndex: 0,
            order: .baselineFirst,
            sampleIndex: 0
        )
        let executor = RecordingTrialExecutor()
        let result = try PerformanceTrialRunner.run(
            request: request,
            sourceIdentity: PerformanceFixtures.baselineBuild.sourceIdentity,
            runProvenanceSHA256: String(repeating: "a", count: 64),
            pairEligibilitySHA256: String(repeating: "b", count: 64),
            executor: executor
        )
        XCTAssertEqual(executor.warmupCount, 5)
        XCTAssertEqual(executor.sampleCount, 1)
        XCTAssertEqual(result.samples.count, PerformanceMetricID.allCases.count)
        XCTAssertEqual(result.request.sampleIndex, result.request.pairIndex)
        XCTAssertTrue(result.startedAtUTC.contains("."))
        XCTAssertTrue(result.endedAtUTC.contains("."))
    }

    func testPartialStoreUsesDerivedNamesCanonicalBytesAndConflictSafeRetries() throws {
        let directory = try temporaryDirectory("pointer-partial-store")
        defer { try? FileManager.default.removeItem(at: directory) }
        let baseline = makeResult(variant: .baseline, pairIndex: 0, order: .baselineFirst)
        let candidate = makeResult(variant: .candidate, pairIndex: 0, order: .baselineFirst)
        let store = PerformancePartialPairStore(directory: directory)
        let baselineURL = try store.store(PerformancePartialPair(fixtureProfile: .standard12, pairIndex: 0, order: .baselineFirst, baseline: baseline))
        XCTAssertEqual(baselineURL.lastPathComponent, "0.json")
        let firstBytes = try Data(contentsOf: baselineURL)
        let baselineObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: firstBytes) as? [String: Any])
        XCTAssertEqual(Set(baselineObject.keys), ["schemaVersion", "fixtureProfile", "pairIndex", "order", "baseline", "candidate"])
        XCTAssertTrue(baselineObject["candidate"] is NSNull)
        var omittedCandidate = baselineObject
        omittedCandidate.removeValue(forKey: "candidate")
        let omittedCandidateData = try JSONSerialization.data(withJSONObject: omittedCandidate, options: [.sortedKeys])
        XCTAssertThrowsError(try JSONDecoder().decode(PerformancePartialPair.self, from: omittedCandidateData))
        XCTAssertEqual(try store.store(PerformancePartialPair(fixtureProfile: .standard12, pairIndex: 0, order: .baselineFirst, baseline: baseline)), baselineURL)
        XCTAssertEqual(try Data(contentsOf: baselineURL), firstBytes)
        let mergedURL = try store.store(PerformancePartialPair(fixtureProfile: .standard12, pairIndex: 0, order: .baselineFirst, baseline: baseline, candidate: candidate))
        XCTAssertEqual(mergedURL, baselineURL)
        XCTAssertEqual(try store.load(pairOrder: .baselineFirst, pairIndex: 0).candidate, candidate)
        let conflict = makeResult(variant: .baseline, pairIndex: 0, order: .baselineFirst, values: Array(repeating: 99, count: 11))
        XCTAssertThrowsError(try store.store(PerformancePartialPair(fixtureProfile: .standard12, pairIndex: 0, order: .baselineFirst, baseline: conflict)))
    }

    func testPartialPairUsesItsNominalPublicWireType() {
        XCTAssertEqual(String(describing: PerformancePartialPair.self), "PerformancePartialPair")
    }

    func testPartialStoreRequiresFirstVariantForEachPairOrder() throws {
        let directory = try temporaryDirectory("pointer-partial-order")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PerformancePartialPairStore(directory: directory)
        XCTAssertThrowsError(try store.store(PerformancePartialPair(
            fixtureProfile: .standard12,
            pairIndex: 0,
            order: .baselineFirst,
            candidate: makeResult(variant: .candidate, pairIndex: 0, order: .baselineFirst)
        )))
        XCTAssertThrowsError(try store.store(PerformancePartialPair(
            fixtureProfile: .standard12,
            pairIndex: 15,
            order: .candidateFirst,
            baseline: makeResult(variant: .baseline, pairIndex: 15, order: .candidateFirst)
        )))
        XCTAssertNoThrow(try store.store(PerformancePartialPair(
            fixtureProfile: .standard12,
            pairIndex: 15,
            order: .candidateFirst,
            candidate: makeResult(variant: .candidate, pairIndex: 15, order: .candidateFirst)
        )))
    }

    func testPartialReservationBlocksDuplicateAndExtraEntryBeforeMeasurement() throws {
        let directory = try temporaryDirectory("pointer-partial-reservation")
        defer { try? FileManager.default.removeItem(at: directory) }
        let request = PerformanceTrialRequest(variant: .baseline, fixtureProfile: .standard12, pairIndex: 0, order: .baselineFirst, sampleIndex: 0)
        let store = PerformancePartialPairStore(directory: directory)
        let first = try store.reserve(request: request, sourceIdentity: PerformanceFixtures.baselineBuild.sourceIdentity, runProvenanceSHA256: String(repeating: "0", count: 64), pairEligibilitySHA256: String(repeating: "0", count: 64))
        XCTAssertThrowsError(try store.reserve(request: request, sourceIdentity: PerformanceFixtures.baselineBuild.sourceIdentity, runProvenanceSHA256: String(repeating: "0", count: 64), pairEligibilitySHA256: String(repeating: "0", count: 64)))
        first.release()
        try Data("extra".utf8).write(to: directory.appendingPathComponent(".unexpected.tmp"))
        XCTAssertThrowsError(try store.reserve(request: request, sourceIdentity: PerformanceFixtures.baselineBuild.sourceIdentity, runProvenanceSHA256: String(repeating: "0", count: 64), pairEligibilitySHA256: String(repeating: "0", count: 64)))
    }

    func testPartialStoreRejectsLocksMalformedUnknownAndExtraFiles() throws {
        let directory = try temporaryDirectory("pointer-partial-shape")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PerformancePartialPairStore(directory: directory)
        let lockURL = directory.appendingPathComponent("0.json.lock")
        XCTAssertTrue(FileManager.default.createFile(atPath: lockURL.path, contents: Data()))
        XCTAssertThrowsError(try store.store(PerformancePartialPair(fixtureProfile: .standard12, pairIndex: 0, order: .baselineFirst, baseline: makeResult(variant: .baseline, pairIndex: 0, order: .baselineFirst))))
        try FileManager.default.removeItem(at: lockURL)
        let malformedURL = directory.appendingPathComponent("0.json")
        try Data("{}".utf8).write(to: malformedURL)
        XCTAssertThrowsError(try store.load(pairOrder: .baselineFirst, pairIndex: 0))
        try FileManager.default.removeItem(at: malformedURL)
        _ = try store.store(PerformancePartialPair(fixtureProfile: .standard12, pairIndex: 0, order: .baselineFirst, baseline: makeResult(variant: .baseline, pairIndex: 0, order: .baselineFirst)))
        let extraURL = directory.appendingPathComponent("extra.json")
        try Data("{}".utf8).write(to: extraURL)
        XCTAssertThrowsError(try store.loadAll(configuration: .standard12))
    }

    func testFinalizerAggregatesEveryMeasuredMetricIntoThirtySampleReports() throws {
        let root = try temporaryDirectory("pointer-finalizer-all-metrics")
        defer { try? FileManager.default.removeItem(at: root) }
        let partialDirectory = root.appendingPathComponent("standard12/pair-execution/partial", isDirectory: true)
        let store = PerformancePartialPairStore(directory: partialDirectory)
        for index in 0..<30 {
            let order: PairOrder = index < 15 ? .baselineFirst : .candidateFirst
            let baseline = makeResult(variant: .baseline, pairIndex: index, order: order, values: metricValues(offset: Double(index)))
            let candidate = makeResult(variant: .candidate, pairIndex: index, order: order, values: metricValues(offset: Double(index + 1)))
            _ = try store.store(PerformancePartialPair(fixtureProfile: .standard12, pairIndex: index, order: order, baseline: baseline, candidate: candidate))
        }
        let output = root.appendingPathComponent("standard12", isDirectory: true)
        let result = try PerformancePairExecutionFinalizer.finalize(
            partialDirectory: partialDirectory,
            baselineReportURL: output.appendingPathComponent("measurements/baseline.json"),
            candidateReportURL: output.appendingPathComponent("measurements/candidate.json"),
            outputDirectory: output,
            configuration: .standard12,
            baselineRun: PerformanceFixtures.baselineRun,
            candidateRun: PerformanceFixtures.run,
            baselineBuild: PerformanceFixtures.baselineBuild,
            candidateBuild: PerformanceFixtures.build,
            baselineIdentity: PerformanceFixtures.baselineIdentity,
            candidateIdentity: PerformanceFixtures.identity,
            baselineRunProvenanceSHA256: String(repeating: "0", count: 64),
            candidateRunProvenanceSHA256: String(repeating: "0", count: 64),
            pairEligibilitySHA256: String(repeating: "0", count: 64)
        )
        XCTAssertEqual(result.artifact.records.count, 30)
        XCTAssertEqual(result.baselineReport.model.trialNanoseconds.count, 30)
        XCTAssertEqual(result.baselineReport.renderer.frameMilliseconds.count, 30)
        XCTAssertEqual(result.baselineReport.compositor.frameMilliseconds.count, 30)
        XCTAssertEqual(result.baselineReport.combinedFrame.frameMilliseconds.count, 30)
        XCTAssertEqual(result.baselineReport.launch.coldMilliseconds.count, 30)
        XCTAssertEqual(result.baselineReport.launch.warmMilliseconds.count, 30)
        XCTAssertEqual(result.baselineReport.allocations.bytesPerGesture.count, 30)
        XCTAssertEqual(result.baselineReport.redrawLayout.sampleMilliseconds.count, 30)
        XCTAssertEqual(result.baselineReport.responsiveness.responseMilliseconds.count, 30)
        XCTAssertEqual(result.baselineReport.inputToVisible.sampleMilliseconds.count, 30)
        XCTAssertEqual(result.baselineReport.memory.status, .measured)
        XCTAssertEqual(result.baselineReport.memory.samples.count, 30)
        XCTAssertEqual(result.baselineReport.disposition, .revise)
        XCTAssertTrue(FileManager.default.fileExists(atPath: output.appendingPathComponent("pair-execution/pair-execution.json").path))
    }

    func testFinalizerPreservesDirtyContentIdentityAndCanonicalizesThirtyPartialOutputs() throws {
        let root = try temporaryDirectory("pointer-finalizer-dirty-content")
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = PerformanceFixtureProfile.standard12
        let configuration = PerformanceConfiguration.standard12
        let partialDirectory = root.appendingPathComponent("standard12/pair-execution/partial", isDirectory: true)
        let output = root.appendingPathComponent("standard12", isDirectory: true)
        let dirtyContent = SourceIdentity(kind: .contentManifestSHA256, value: PerformanceFixtures.sourceManifest)
        let dirtyCandidateContent = dirtyContent
        let dirtyBaselineBuild = BuildProvenance(
            sourceTreeStatus: .dirty,
            sourceIdentity: dirtyContent,
            sourceManifestSHA256: dirtyContent.value,
            executableSHA256: PerformanceFixtures.executable,
            bundleManifestSHA256: PerformanceFixtures.bundle,
            buildConfiguration: "debug",
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: configuration.harnessVersion,
            buildContractVersion: configuration.buildContractVersion,
            acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
        )
        let dirtyCandidateBuild = BuildProvenance(
            sourceTreeStatus: .dirty,
            sourceIdentity: dirtyCandidateContent,
            sourceManifestSHA256: dirtyCandidateContent.value,
            executableSHA256: PerformanceFixtures.executable,
            bundleManifestSHA256: PerformanceFixtures.bundle,
            buildConfiguration: "debug",
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: configuration.harnessVersion,
            buildContractVersion: configuration.buildContractVersion,
            acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
        )
        let dirtyBaselineRun = PerformanceRunProvenance(
            variant: "baseline",
            outputRoot: root.appendingPathComponent("standard12/baseline", isDirectory: true).path,
            sourceRef: PerformanceFixtures.baselineCommit,
            build: dirtyBaselineBuild,
            host: PerformanceFixtures.host,
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            configuration: configuration,
            foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: configuration.harnessVersion,
            buildContractVersion: configuration.buildContractVersion,
            acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
        )
        let dirtyCandidateRun = PerformanceRunProvenance(
            variant: "candidate",
            outputRoot: root.appendingPathComponent("standard12/candidate", isDirectory: true).path,
            sourceRef: PerformanceFixtures.commit,
            build: dirtyCandidateBuild,
            host: PerformanceFixtures.host,
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            configuration: configuration,
            foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: configuration.harnessVersion,
            buildContractVersion: configuration.buildContractVersion,
            acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
        )
        let baselineRunHash = String(repeating: "1", count: 64)
        let candidateRunHash = String(repeating: "2", count: 64)
        let pairEligibilityHash = String(repeating: "3", count: 64)
        let store = PerformancePartialPairStore(directory: partialDirectory)
        for index in 0..<30 {
            let order: PairOrder = index < 15 ? .baselineFirst : .candidateFirst
            let baseline = makeResult(variant: .baseline, pairIndex: index, order: order, runProvenanceSHA256: baselineRunHash, pairEligibilitySHA256: pairEligibilityHash, sourceIdentity: dirtyContent)
            let candidate = makeResult(variant: .candidate, pairIndex: index, order: order, runProvenanceSHA256: candidateRunHash, pairEligibilitySHA256: pairEligibilityHash, sourceIdentity: dirtyCandidateContent)
            _ = try store.store(PerformancePartialPair(fixtureProfile: profile, pairIndex: index, order: order, baseline: baseline, candidate: candidate))
        }

        let result = try PerformancePairExecutionFinalizer.finalize(
            partialDirectory: partialDirectory,
            baselineReportURL: output.appendingPathComponent("measurements/baseline.json"),
            candidateReportURL: output.appendingPathComponent("measurements/candidate.json"),
            outputDirectory: output,
            configuration: configuration,
            baselineRun: dirtyBaselineRun,
            candidateRun: dirtyCandidateRun,
            baselineBuild: dirtyBaselineBuild,
            candidateBuild: dirtyCandidateBuild,
            baselineIdentity: MeasurementIdentity(sourceCommitSHA: nil, contentManifestSHA256: PerformanceFixtures.sourceManifest, hostModel: PerformanceFixtures.host.machineIdentifier, macOSVersion: "14.6.1", xcodeVersion: "16.0", developerDirectory: "/Applications/Xcode.app/Contents/Developer", powerState: "ac", displayState: "one-display", buildConfiguration: "debug"),
            candidateIdentity: MeasurementIdentity(sourceCommitSHA: nil, contentManifestSHA256: dirtyCandidateContent.value, hostModel: PerformanceFixtures.host.machineIdentifier, macOSVersion: "14.6.1", xcodeVersion: "16.0", developerDirectory: "/Applications/Xcode.app/Contents/Developer", powerState: "ac", displayState: "one-display", buildConfiguration: "debug"),
            baselineRunProvenanceSHA256: baselineRunHash,
            candidateRunProvenanceSHA256: candidateRunHash,
            pairEligibilitySHA256: pairEligibilityHash
        )
        XCTAssertNil(result.baselineReport.identity.sourceCommitSHA)
        XCTAssertEqual(result.baselineReport.identity.contentManifestSHA256, PerformanceFixtures.sourceManifest)
        XCTAssertNil(result.candidateReport.identity.sourceCommitSHA)
        XCTAssertEqual(result.candidateReport.identity.contentManifestSHA256, dirtyCandidateContent.value)
        XCTAssertEqual(result.artifact.baselineID, dirtyBaselineRun.sourceRef)
        XCTAssertEqual(result.artifact.candidateID, dirtyCandidateRun.sourceRef)
        XCTAssertEqual(result.artifact.records.count, 30)
        XCTAssertEqual(try Data(contentsOf: result.baselineReportURL), try PerformanceCanonicalJSON.data(for: result.baselineReport))
        XCTAssertEqual(try Data(contentsOf: result.candidateReportURL), try PerformanceCanonicalJSON.data(for: result.candidateReport))
        XCTAssertEqual(try Data(contentsOf: result.artifactURL), try PerformancePairExecutionArtifact.canonicalData(for: result.artifact))
    }

    func testRealCLIFinalizePublishesThirtyPartialsForCleanAndDirtyRuns() throws {
        for isDirty in [false, true] {
            let root = try temporaryDirectory("pointer-cli-finalize-real")
            defer { try? FileManager.default.removeItem(at: root) }
            let profile = PerformanceFixtureProfile.standard12
            let configuration = PerformanceConfiguration.standard12
            let performanceRoot = root.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance", isDirectory: true)
            let profileRoot = performanceRoot.appendingPathComponent(profile.rawValue, isDirectory: true)
            let outputRoot = profileRoot
            let buildRoot = root.appendingPathComponent("build/\(profile.rawValue)", isDirectory: true)
            let partialDirectory = buildRoot.appendingPathComponent("pair-execution/partial", isDirectory: true)
            let baselineOutputRoot = buildRoot.appendingPathComponent("baseline", isDirectory: true).path
            let candidateOutputRoot = buildRoot.appendingPathComponent("candidate", isDirectory: true).path
            let baselineIdentity = isDirty
                ? SourceIdentity(kind: .contentManifestSHA256, value: PerformanceFixtures.sourceManifest)
                : PerformanceFixtures.baselineBuild.sourceIdentity
            let candidateIdentity = isDirty
                ? baselineIdentity
                : PerformanceFixtures.build.sourceIdentity
            let baselineBuild = BuildProvenance(
                sourceTreeStatus: isDirty ? .dirty : .clean,
                sourceIdentity: baselineIdentity,
                sourceManifestSHA256: PerformanceFixtures.sourceManifest,
                executableSHA256: PerformanceFixtures.baselineBuild.executableSHA256,
                bundleManifestSHA256: PerformanceFixtures.baselineBuild.bundleManifestSHA256,
                buildConfiguration: isDirty ? "debug" : "release",
                recordedAtUTC: PerformanceFixtures.recordedAtUTC,
                foundation: PerformanceFixtures.foundation,
                harnessVersion: configuration.harnessVersion,
                buildContractVersion: configuration.buildContractVersion,
                acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
            )
            let candidateBuild = BuildProvenance(
                sourceTreeStatus: isDirty ? .dirty : .clean,
                sourceIdentity: candidateIdentity,
                sourceManifestSHA256: PerformanceFixtures.sourceManifest,
                executableSHA256: PerformanceFixtures.build.executableSHA256,
                bundleManifestSHA256: PerformanceFixtures.build.bundleManifestSHA256,
                buildConfiguration: isDirty ? "debug" : "release",
                recordedAtUTC: PerformanceFixtures.recordedAtUTC,
                foundation: PerformanceFixtures.foundation,
                harnessVersion: configuration.harnessVersion,
                buildContractVersion: configuration.buildContractVersion,
                acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
            )
            let baselineRun = PerformanceRunProvenance(
                variant: "baseline",
                outputRoot: baselineOutputRoot,
                sourceRef: PerformanceFixtures.baselineCommit,
                build: baselineBuild,
                host: PerformanceFixtures.host,
                recordedAtUTC: PerformanceFixtures.recordedAtUTC,
                configuration: configuration,
                foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath,
                foundation: PerformanceFixtures.foundation,
                harnessVersion: configuration.harnessVersion,
                buildContractVersion: configuration.buildContractVersion,
                acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
            )
            let candidateRun = PerformanceRunProvenance(
                variant: "candidate",
                outputRoot: candidateOutputRoot,
                sourceRef: PerformanceFixtures.commit,
                build: candidateBuild,
                host: PerformanceFixtures.host,
                recordedAtUTC: PerformanceFixtures.recordedAtUTC,
                configuration: configuration,
                foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath,
                foundation: PerformanceFixtures.foundation,
                harnessVersion: configuration.harnessVersion,
                buildContractVersion: configuration.buildContractVersion,
                acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
            )
            let eligibility = PerformancePairEligibility(
                baselineRoot: baselineOutputRoot,
                candidateRoot: candidateOutputRoot,
                baselineCommitSHA: baselineRun.sourceRef,
                candidateCommitSHA: candidateRun.sourceRef,
                foundationProvenance: PerformanceFixtures.foundationProvenance
            )
            let baselineURL = buildRoot.appendingPathComponent("baseline/provenance.json")
            let candidateURL = buildRoot.appendingPathComponent("candidate/provenance.json")
            let eligibilityURL = profileRoot.appendingPathComponent("comparisons/pair-eligibility.json")
            let baselineData = try PerformanceCanonicalJSON.data(for: baselineRun)
            let candidateData = try PerformanceCanonicalJSON.data(for: candidateRun)
            let eligibilityData = try PerformanceCanonicalJSON.data(for: eligibility)
            try FileManager.default.createDirectory(at: baselineURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: candidateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try baselineData.write(to: baselineURL)
            try candidateData.write(to: candidateURL)
            try FileManager.default.createDirectory(at: eligibilityURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try eligibilityData.write(to: eligibilityURL)
            let baselineHash = sha256(baselineData)
            let candidateHash = sha256(candidateData)
            let eligibilityHash = sha256(eligibilityData)
            let store = PerformancePartialPairStore(directory: partialDirectory)
            for index in 0..<30 {
                let order: PairOrder = index < 15 ? .baselineFirst : .candidateFirst
                let baseline = makeResult(variant: .baseline, pairIndex: index, order: order, runProvenanceSHA256: baselineHash, pairEligibilitySHA256: eligibilityHash, sourceIdentity: baselineIdentity)
                let candidate = makeResult(variant: .candidate, pairIndex: index, order: order, runProvenanceSHA256: candidateHash, pairEligibilitySHA256: eligibilityHash, sourceIdentity: candidateIdentity)
                _ = try store.store(PerformancePartialPair(fixtureProfile: profile, pairIndex: index, order: order, baseline: baseline, candidate: candidate))
            }
            let args = [
                "--quality-performance", "--format", "json", "--operation", "finalize",
                "--fixture-profile", profile.rawValue,
                "--partial-pair-directory", partialDirectory.path,
                "--baseline-run-provenance-file", baselineURL.path,
                "--candidate-run-provenance-file", candidateURL.path,
                "--pair-eligibility-file", eligibilityURL.path,
                "--output-dir", outputRoot.path
            ]
            let transactionJournal = performanceRoot.appendingPathComponent(".benchmark-quality.transaction.\(profile.rawValue)")
            let backupOutput = performanceRoot.appendingPathComponent(".benchmark-quality.backup.\(profile.rawValue)/\(profile.rawValue)")
            for phase in [PerformancePublishPhase.prepared, .backedUp, .installed, .discardedBackup] {
                if phase != .prepared {
                    try FileManager.default.removeItem(at: outputRoot)
                    let preseedComparisons = outputRoot.appendingPathComponent("comparisons", isDirectory: true)
                    try FileManager.default.createDirectory(at: preseedComparisons, withIntermediateDirectories: true)
                    try eligibilityData.write(to: preseedComparisons.appendingPathComponent("pair-eligibility.json"))
                }
                PerformanceCLI.publishPhaseHook = { observedPhase in
                    return observedPhase == phase
                }
                var diagnostic = ""
                do {
                    try PerformanceCLI.run(arguments: args, outputDirectory: outputRoot)
                    XCTFail("expected injected publish interruption")
                } catch {
                    diagnostic = String(describing: error)
                }
                PerformanceCLI.publishPhaseHook = nil
                XCTAssertTrue(diagnostic.contains("interruption"), diagnostic)
                XCTAssertTrue(FileManager.default.fileExists(atPath: transactionJournal.path))
                XCTAssertTrue(
                    FileManager.default.fileExists(atPath: outputRoot.path)
                        || FileManager.default.fileExists(atPath: backupOutput.path)
                )
                if phase == .backedUp {
                    let originalJournalData = try Data(contentsOf: transactionJournal)
                    var forgedJournal = try XCTUnwrap(try JSONSerialization.jsonObject(with: originalJournalData) as? [String: Any])
                    forgedJournal["transactionID"] = UUID().uuidString
                    try JSONSerialization.data(withJSONObject: forgedJournal, options: [.sortedKeys]).write(to: transactionJournal)
                    XCTAssertThrowsError(try PerformanceCLI.run(arguments: args, outputDirectory: outputRoot))
                    XCTAssertTrue(FileManager.default.fileExists(atPath: backupOutput.path))
                    XCTAssertFalse(FileManager.default.fileExists(atPath: outputRoot.path))
                    try originalJournalData.write(to: transactionJournal)

                    let journalObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: originalJournalData) as? [String: Any])
                    let stagingPath = try XCTUnwrap(journalObject["stagingPath"] as? String)
                    let stagingRoot = URL(fileURLWithPath: stagingPath, isDirectory: true)
                    let stagedEligibility = stagingRoot.appendingPathComponent("comparisons/pair-eligibility.json")
                    let stagedEligibilityData = try Data(contentsOf: stagedEligibility)
                    try Data("{}".utf8).write(to: stagedEligibility)
                    XCTAssertThrowsError(try PerformanceCLI.run(arguments: args, outputDirectory: outputRoot))
                    XCTAssertTrue(FileManager.default.fileExists(atPath: backupOutput.path))
                    XCTAssertFalse(FileManager.default.fileExists(atPath: outputRoot.path))
                    try stagedEligibilityData.write(to: stagedEligibility)

                    let restoreJournalObject = try XCTUnwrap(try JSONSerialization.jsonObject(with: originalJournalData) as? [String: Any])
                    let restoreStagingPath = try XCTUnwrap(restoreJournalObject["stagingPath"] as? String)
                    let restoreStagingRoot = URL(fileURLWithPath: restoreStagingPath, isDirectory: true)
                    try FileManager.default.removeItem(at: restoreStagingRoot)
                    PerformanceCLI.publishPhaseHook = { observedPhase in
                        observedPhase == .restoredBackup
                    }
                    XCTAssertThrowsError(try PerformanceCLI.run(arguments: args, outputDirectory: outputRoot))
                    PerformanceCLI.publishPhaseHook = nil
                    XCTAssertTrue(FileManager.default.fileExists(atPath: outputRoot.path))
                    XCTAssertFalse(FileManager.default.fileExists(atPath: backupOutput.path))
                    XCTAssertTrue(FileManager.default.fileExists(atPath: backupOutput.deletingLastPathComponent().path))
                    try PerformanceCLI.run(arguments: args, outputDirectory: outputRoot)
                    XCTAssertFalse(FileManager.default.fileExists(atPath: transactionJournal.path))
                    XCTAssertFalse(FileManager.default.fileExists(atPath: backupOutput.deletingLastPathComponent().path))
                }
                try PerformanceCLI.run(arguments: args, outputDirectory: outputRoot)
                XCTAssertFalse(FileManager.default.fileExists(atPath: transactionJournal.path))
                XCTAssertFalse(FileManager.default.fileExists(atPath: backupOutput.path))
                XCTAssertFalse(FileManager.default.fileExists(atPath: backupOutput.deletingLastPathComponent().path))
            }
            try PerformanceCLI.run(arguments: args, outputDirectory: outputRoot)
            let baselineReportURL = outputRoot.appendingPathComponent("measurements/baseline.json")
            let candidateReportURL = outputRoot.appendingPathComponent("measurements/candidate.json")
            let artifactURL = outputRoot.appendingPathComponent("pair-execution/pair-execution.json")
            XCTAssertTrue(FileManager.default.fileExists(atPath: baselineReportURL.path), "baseline report missing")
            XCTAssertTrue(FileManager.default.fileExists(atPath: candidateReportURL.path), "candidate report missing")
            XCTAssertTrue(FileManager.default.fileExists(atPath: artifactURL.path), "pair artifact missing")
            let baselineReport = try PerformanceCanonicalJSON.decoded(PerformanceMeasurementReport.self, from: Data(contentsOf: baselineReportURL))
            let candidateReport = try PerformanceCanonicalJSON.decoded(PerformanceMeasurementReport.self, from: Data(contentsOf: candidateReportURL))
            let artifact = try PerformanceCanonicalJSON.decoded(PerformancePairExecutionArtifact.self, from: Data(contentsOf: artifactURL))
            XCTAssertEqual(baselineReport.identity.contentManifestSHA256, isDirty ? PerformanceFixtures.sourceManifest : nil)
            XCTAssertEqual(candidateReport.identity.contentManifestSHA256, isDirty ? PerformanceFixtures.sourceManifest : nil)
            XCTAssertEqual(baselineReport.disposition, .revise)
            XCTAssertEqual(candidateReport.disposition, .revise)
            XCTAssertEqual(artifact.baselineID, baselineRun.sourceRef)
            XCTAssertEqual(artifact.candidateID, candidateRun.sourceRef)
            XCTAssertEqual(artifact.records.count, 30)
            XCTAssertEqual(try Data(contentsOf: baselineReportURL), try PerformanceCanonicalJSON.data(for: baselineReport))
            XCTAssertEqual(try Data(contentsOf: candidateReportURL), try PerformanceCanonicalJSON.data(for: candidateReport))
            XCTAssertEqual(try Data(contentsOf: artifactURL), try PerformancePairExecutionArtifact.canonicalData(for: artifact))
            let outputParentEntries = try FileManager.default.contentsOfDirectory(at: outputRoot.deletingLastPathComponent(), includingPropertiesForKeys: nil)
            XCTAssertTrue(outputParentEntries.allSatisfy { !$0.lastPathComponent.hasPrefix(".standard12.pending") })
        }
    }

    func testCompleteSidecarCLIPathFinalizesAndWritesAcceptedComparison() throws {
        let root = try temporaryDirectory("pointer-cli-sidecar-complete")
        defer { try? FileManager.default.removeItem(at: root) }
        let profile = PerformanceFixtureProfile.standard12
        let configuration = PerformanceConfiguration.standard12
        let performanceRoot = root.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance", isDirectory: true)
        let profileRoot = performanceRoot.appendingPathComponent(profile.rawValue, isDirectory: true)
        let buildRoot = root.appendingPathComponent("build/\(profile.rawValue)", isDirectory: true)
        let partialDirectory = buildRoot.appendingPathComponent("pair-execution/partial", isDirectory: true)
        let outputRoot = profileRoot
        let sidecarRoot = profileRoot
        let baselineOutputRoot = buildRoot.appendingPathComponent("baseline", isDirectory: true).path
        let candidateOutputRoot = buildRoot.appendingPathComponent("candidate", isDirectory: true).path
        let baselineRun = PerformanceRunProvenance(
            variant: "baseline",
            outputRoot: baselineOutputRoot,
            sourceRef: PerformanceFixtures.baselineCommit,
            build: PerformanceFixtures.baselineBuild,
            host: PerformanceFixtures.host,
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            configuration: configuration,
            foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: configuration.harnessVersion,
            buildContractVersion: configuration.buildContractVersion,
            acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
        )
        let candidateRun = PerformanceRunProvenance(
            variant: "candidate",
            outputRoot: candidateOutputRoot,
            sourceRef: PerformanceFixtures.commit,
            build: PerformanceFixtures.build,
            host: PerformanceFixtures.host,
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            configuration: configuration,
            foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: configuration.harnessVersion,
            buildContractVersion: configuration.buildContractVersion,
            acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
        )
        let eligibility = PerformancePairEligibility(
            baselineRoot: baselineOutputRoot,
            candidateRoot: candidateOutputRoot,
            baselineCommitSHA: baselineRun.sourceRef,
            candidateCommitSHA: candidateRun.sourceRef,
            foundationProvenance: PerformanceFixtures.foundationProvenance
        )
        let baselineRunURL = buildRoot.appendingPathComponent("baseline/provenance.json")
        let candidateRunURL = buildRoot.appendingPathComponent("candidate/provenance.json")
        let eligibilityURL = profileRoot.appendingPathComponent("comparisons/pair-eligibility.json")
        let baselineRunData = try PerformanceCanonicalJSON.data(for: baselineRun)
        let candidateRunData = try PerformanceCanonicalJSON.data(for: candidateRun)
        let eligibilityData = try PerformanceCanonicalJSON.data(for: eligibility)
        try FileManager.default.createDirectory(at: baselineRunURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: candidateRunURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try baselineRunData.write(to: baselineRunURL)
        try candidateRunData.write(to: candidateRunURL)
        try FileManager.default.createDirectory(at: eligibilityURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try eligibilityData.write(to: eligibilityURL)
        let baselineHash = sha256(baselineRunData)
        let candidateHash = sha256(candidateRunData)
        let eligibilityHash = sha256(eligibilityData)
        let executor = RecordingTrialExecutor()
        PerformanceCLI.trialExecutor = executor
        defer { PerformanceCLI.trialExecutor = nil }

        func writeTrialSidecar(request: PerformanceTrialRequest, sourceIdentity: SourceIdentity, runHash: String, fileName: String) throws -> URL {
            let binding = PerformanceExternalTrialBinding(
                request: request,
                sourceIdentity: sourceIdentity,
                runProvenanceSHA256: runHash,
                pairEligibilitySHA256: eligibilityHash,
                startedAtUTC: "2026-01-01T00:00:00.123Z",
                endedAtUTC: "2027-01-01T00:00:00.123Z"
            )
            let measurements = PerformanceExternalTrialSidecar.requiredMetricIDs.map { metricID in
                let index = PerformanceMetricID.allCases.firstIndex(of: metricID)!
                return PerformanceExternalTrialScalarMeasurement(metricID: metricID, unit: metricID.canonicalUnit, status: .measured, value: Double(index + 1), diagnostic: nil)
            }
            let sidecar = PerformanceExternalTrialSidecar(binding: binding, measurements: measurements)
            let url = sidecarRoot.appendingPathComponent("external/trials/\(request.variant.rawValue)/\(request.pairIndex).json")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PerformanceCanonicalJSON.data(for: sidecar).write(to: url)
            return url
        }

        func runTrial(variant: PerformanceVariant, order: PairOrder, pairIndex: Int, sourceIdentity: SourceIdentity, runURL: URL, runHash: String) throws {
            let request = PerformanceTrialRequest(variant: variant, fixtureProfile: profile, pairIndex: pairIndex, order: order, sampleIndex: pairIndex)
            let sidecarURL = try writeTrialSidecar(request: request, sourceIdentity: sourceIdentity, runHash: runHash, fileName: "\(variant.rawValue)-\(pairIndex).json")
            let args = [
                "--quality-performance", "--format", "json", "--operation", "trial",
                "--fixture-profile", profile.rawValue,
                "--variant", variant.rawValue,
                "--pair-order", order.rawValue,
                "--pair-index", String(pairIndex),
                "--source-commit-sha", sourceIdentity.value,
                "--run-provenance-file", runURL.path,
                "--pair-eligibility-file", eligibilityURL.path,
                "--external-trial-sidecar", sidecarURL.path,
                "--partial-pair-directory", partialDirectory.path
            ]
            try PerformanceCLI.run(arguments: args, outputDirectory: root)
        }

        for index in 0..<15 {
            try runTrial(variant: .baseline, order: .baselineFirst, pairIndex: index, sourceIdentity: baselineRun.build.sourceIdentity, runURL: baselineRunURL, runHash: baselineHash)
            try runTrial(variant: .candidate, order: .baselineFirst, pairIndex: index, sourceIdentity: candidateRun.build.sourceIdentity, runURL: candidateRunURL, runHash: candidateHash)
        }
        for index in 15..<30 {
            try runTrial(variant: .candidate, order: .candidateFirst, pairIndex: index, sourceIdentity: candidateRun.build.sourceIdentity, runURL: candidateRunURL, runHash: candidateHash)
            try runTrial(variant: .baseline, order: .candidateFirst, pairIndex: index, sourceIdentity: baselineRun.build.sourceIdentity, runURL: baselineRunURL, runHash: baselineHash)
        }
        XCTAssertEqual(executor.sampleCount, 60)
        let partials = try PerformancePartialPairStore(directory: partialDirectory).loadAll(configuration: configuration)
        let baselineResults = partials.compactMap(\.baseline)
        let candidateResults = partials.compactMap(\.candidate)
        func aggregateSidecar(variant: PerformanceVariant, sourceIdentity: SourceIdentity, runHash: String, results: [PerformanceTrialResult]) throws -> URL {
            let hashes = try results.sorted { $0.request.sampleIndex < $1.request.sampleIndex }.map { try sha256(PerformanceCanonicalJSON.data(for: $0)) }
            let sidecar = PerformanceExternalAggregateSidecar(
                binding: PerformanceExternalAggregateBinding(variant: variant, fixtureProfile: profile, sourceIdentity: sourceIdentity, runProvenanceSHA256: runHash, pairEligibilitySHA256: eligibilityHash),
                resultSHA256s: hashes,
                memory: PerformanceFixtures.memory,
                resilience: PerformanceFixtures.resilience
            )
            let url = sidecarRoot.appendingPathComponent("external/aggregate/\(variant.rawValue).json")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try PerformanceCanonicalJSON.data(for: sidecar).write(to: url)
            return url
        }
        let baselineAggregateURL = try aggregateSidecar(variant: .baseline, sourceIdentity: baselineRun.build.sourceIdentity, runHash: baselineHash, results: baselineResults)
        let candidateAggregateURL = try aggregateSidecar(variant: .candidate, sourceIdentity: candidateRun.build.sourceIdentity, runHash: candidateHash, results: candidateResults)
        let finalizeArgs = [
            "--quality-performance", "--format", "json", "--operation", "finalize",
            "--fixture-profile", profile.rawValue,
            "--partial-pair-directory", partialDirectory.path,
            "--baseline-run-provenance-file", baselineRunURL.path,
            "--candidate-run-provenance-file", candidateRunURL.path,
            "--pair-eligibility-file", eligibilityURL.path,
            "--baseline-external-aggregate-sidecar", baselineAggregateURL.path,
            "--candidate-external-aggregate-sidecar", candidateAggregateURL.path,
            "--output-dir", outputRoot.path
        ]
        let baselineTrialZeroURL = profileRoot.appendingPathComponent("external/trials/baseline/0.json")
        let baselineTrialOneURL = profileRoot.appendingPathComponent("external/trials/baseline/1.json")
        let baselineTrialZeroData = try Data(contentsOf: baselineTrialZeroURL)
        let baselineTrialOneData = try Data(contentsOf: baselineTrialOneURL)
        try baselineTrialZeroData.write(to: baselineTrialOneURL)
        var renamedDiagnostic = ""
        XCTAssertThrowsError(try PerformanceCLI.run(arguments: finalizeArgs, outputDirectory: outputRoot)) { error in
            renamedDiagnostic = String(describing: error)
        }
        XCTAssertTrue(renamedDiagnostic.contains("slot") || renamedDiagnostic.contains("filename"), renamedDiagnostic)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputRoot.appendingPathComponent("measurements", isDirectory: true).path))
        try baselineTrialOneData.write(to: baselineTrialOneURL)

        let baselineTrial = try PerformanceCanonicalJSON.decoded(PerformanceExternalTrialSidecar.self, from: baselineTrialZeroData)
        let staleBinding = PerformanceExternalTrialBinding(
            request: baselineTrial.binding.request,
            sourceIdentity: baselineTrial.binding.sourceIdentity,
            runProvenanceSHA256: String(repeating: "f", count: 64),
            pairEligibilitySHA256: baselineTrial.binding.pairEligibilitySHA256,
            startedAtUTC: baselineTrial.binding.startedAtUTC,
            endedAtUTC: baselineTrial.binding.endedAtUTC
        )
        let staleSidecar = PerformanceExternalTrialSidecar(binding: staleBinding, measurements: baselineTrial.measurements)
        try PerformanceCanonicalJSON.data(for: staleSidecar).write(to: baselineTrialZeroURL)
        var staleDiagnostic = ""
        XCTAssertThrowsError(try PerformanceCLI.run(arguments: finalizeArgs, outputDirectory: outputRoot)) { error in
            staleDiagnostic = String(describing: error)
        }
        XCTAssertTrue(staleDiagnostic.contains("provenance hash") || staleDiagnostic.contains("stale"), staleDiagnostic)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputRoot.appendingPathComponent("measurements", isDirectory: true).path))
        try baselineTrialZeroData.write(to: baselineTrialZeroURL)
        try PerformanceCLI.run(arguments: finalizeArgs, outputDirectory: outputRoot)
        let baselineReportURL = outputRoot.appendingPathComponent("measurements/baseline.json")
        let candidateReportURL = outputRoot.appendingPathComponent("measurements/candidate.json")
        let pairURL = outputRoot.appendingPathComponent("pair-execution/pair-execution.json")
        let firstBaselineReportData = try Data(contentsOf: baselineReportURL)
        let firstTrialSidecarData = try Data(contentsOf: baselineTrialZeroURL)
        try PerformanceCLI.run(arguments: finalizeArgs, outputDirectory: outputRoot)
        XCTAssertEqual(try Data(contentsOf: baselineReportURL), firstBaselineReportData)
        XCTAssertEqual(try Data(contentsOf: baselineTrialZeroURL), firstTrialSidecarData)
        let baselineReport = try PerformanceCanonicalJSON.decoded(PerformanceMeasurementReport.self, from: Data(contentsOf: baselineReportURL))
        let candidateReport = try PerformanceCanonicalJSON.decoded(PerformanceMeasurementReport.self, from: Data(contentsOf: candidateReportURL))
        XCTAssertEqual(baselineReport.disposition, .acceptedNoRegression)
        XCTAssertEqual(candidateReport.disposition, .acceptedNoRegression)
        XCTAssertNoThrow(try baselineReport.validateCompletion())
        XCTAssertNoThrow(try candidateReport.validateCompletion())
        let manualDirectory = outputRoot.appendingPathComponent("comparisons/manual", isDirectory: true)
        try FileManager.default.createDirectory(at: manualDirectory, withIntermediateDirectories: true)
        let comparisonOutput = outputRoot.appendingPathComponent("comparisons", isDirectory: true)
        let compareArgs = [
            "--quality-compare", "--format", "json", "--fixture-profile", profile.rawValue,
            "--baseline-report", baselineReportURL.path,
            "--candidate-report", candidateReportURL.path,
            "--pair-eligibility-file", comparisonOutput.appendingPathComponent("pair-eligibility.json").path,
            "--pair-execution-artifact", pairURL.path,
            "--manual-evidence-dir", manualDirectory.path,
            "--output-dir", comparisonOutput.path
        ]
        try PerformanceCLI.run(arguments: compareArgs, outputDirectory: comparisonOutput)
        let comparisonURL = comparisonOutput.appendingPathComponent("paired-comparison.json")
        let comparison = try PerformanceCanonicalJSON.decoded(
            PerformanceComparisonReport.self,
            from: Data(contentsOf: comparisonURL)
        )
        XCTAssertEqual(comparison.disposition, .acceptedNoRegression)
        XCTAssertNoThrow(try comparison.validateCompletion())
        XCTAssertEqual(try Data(contentsOf: comparisonURL), try PerformanceCanonicalJSON.data(for: comparison))
    }

    func testFinalizerRejectsExternalAggregateResultHashMismatchBeforeOutput() throws {
        let root = try temporaryDirectory("pointer-finalizer-sidecar-hash")
        defer { try? FileManager.default.removeItem(at: root) }
        let partialDirectory = root.appendingPathComponent("standard12/pair-execution/partial", isDirectory: true)
        let store = PerformancePartialPairStore(directory: partialDirectory)
        for index in 0..<30 {
            let order: PairOrder = index < 15 ? .baselineFirst : .candidateFirst
            _ = try store.store(PerformancePartialPair(
                fixtureProfile: .standard12,
                pairIndex: index,
                order: order,
                baseline: makeResult(variant: .baseline, pairIndex: index, order: order),
                candidate: makeResult(variant: .candidate, pairIndex: index, order: order)
            ))
        }
        let sidecar = PerformanceExternalAggregateSidecar(
            binding: PerformanceExternalAggregateBinding(variant: .baseline, fixtureProfile: .standard12, sourceIdentity: PerformanceFixtures.baselineBuild.sourceIdentity, runProvenanceSHA256: String(repeating: "0", count: 64), pairEligibilitySHA256: String(repeating: "0", count: 64)),
            resultSHA256s: Array(repeating: String(repeating: "a", count: 64), count: 30),
            memory: PerformanceFixtures.memory,
            resilience: PerformanceFixtures.resilience
        )
        let output = root.appendingPathComponent("standard12", isDirectory: true)
        XCTAssertThrowsError(try PerformancePairExecutionFinalizer.finalize(
            partialDirectory: partialDirectory,
            baselineReportURL: output.appendingPathComponent("measurements/baseline.json"),
            candidateReportURL: output.appendingPathComponent("measurements/candidate.json"),
            outputDirectory: output,
            configuration: .standard12,
            baselineRun: PerformanceFixtures.baselineRun,
            candidateRun: PerformanceFixtures.run,
            baselineBuild: PerformanceFixtures.baselineBuild,
            candidateBuild: PerformanceFixtures.build,
            baselineIdentity: PerformanceFixtures.baselineIdentity,
            candidateIdentity: PerformanceFixtures.identity,
            baselineRunProvenanceSHA256: String(repeating: "0", count: 64),
            candidateRunProvenanceSHA256: String(repeating: "0", count: 64),
            pairEligibilitySHA256: String(repeating: "0", count: 64),
            baselineExternalAggregate: sidecar
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("measurements/baseline.json").path))
    }

    func testFinalizerRejectsModelChecksumMismatchBeforeAnyOutput() throws {
        let root = try temporaryDirectory("pointer-finalizer-checksum")
        defer { try? FileManager.default.removeItem(at: root) }
        let partialDirectory = root.appendingPathComponent("standard12/pair-execution/partial", isDirectory: true)
        let store = PerformancePartialPairStore(directory: partialDirectory)
        for index in 0..<30 {
            let order: PairOrder = index < 15 ? .baselineFirst : .candidateFirst
            let baselineChecksum = index == 4 ? "tampered" : "checksum"
            let baseline = makeResult(variant: .baseline, pairIndex: index, order: order, modelChecksum: baselineChecksum)
            let candidate = makeResult(variant: .candidate, pairIndex: index, order: order)
            _ = try store.store(PerformancePartialPair(fixtureProfile: .standard12, pairIndex: index, order: order, baseline: baseline, candidate: candidate))
        }
        let output = root.appendingPathComponent("standard12", isDirectory: true)
        XCTAssertThrowsError(try PerformancePairExecutionFinalizer.finalize(
            partialDirectory: partialDirectory,
            baselineReportURL: output.appendingPathComponent("measurements/baseline.json"),
            candidateReportURL: output.appendingPathComponent("measurements/candidate.json"),
            outputDirectory: output,
            configuration: .standard12,
            baselineRun: PerformanceFixtures.baselineRun,
            candidateRun: PerformanceFixtures.run,
            baselineBuild: PerformanceFixtures.baselineBuild,
            candidateBuild: PerformanceFixtures.build,
            baselineIdentity: PerformanceFixtures.baselineIdentity,
            candidateIdentity: PerformanceFixtures.identity,
            baselineRunProvenanceSHA256: String(repeating: "0", count: 64),
            candidateRunProvenanceSHA256: String(repeating: "0", count: 64),
            pairEligibilitySHA256: String(repeating: "0", count: 64)
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("measurements/baseline.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appendingPathComponent("pair-execution/pair-execution.json").path))
    }

    func testFinalizerPreservesAllFailedMetricStatusesAndEmptyRawArrays() throws {
        let failedSamples = metricSamples(status: .failed)
        let results = (0..<30).map { index in
            let order: PairOrder = index < 15 ? .baselineFirst : .candidateFirst
            return makeResult(variant: .baseline, pairIndex: index, order: order, samples: failedSamples)
        }
        let report = try PerformancePairExecutionFinalizer.aggregateReport(
            results: results,
            configuration: .standard12,
            build: PerformanceFixtures.baselineBuild,
            run: PerformanceFixtures.baselineRun,
            identity: PerformanceFixtures.baselineIdentity
        )
        XCTAssertEqual(report.model.status, .failed)
        XCTAssertEqual(report.renderer.status, .failed)
        XCTAssertEqual(report.compositor.status, .failed)
        XCTAssertEqual(report.launch.status, .failed)
        XCTAssertEqual(report.allocations.status, .failed)
        XCTAssertEqual(report.redrawLayout.status, .failed)
        XCTAssertEqual(report.responsiveness.status, .failed)
        XCTAssertEqual(report.inputToVisible.status, .failed)
        XCTAssertEqual(report.memory.status, .failed)
        XCTAssertTrue(report.model.trialNanoseconds.isEmpty)
        XCTAssertTrue(report.renderer.frameMilliseconds.isEmpty)
        XCTAssertTrue(report.compositor.frameMilliseconds.isEmpty)
        XCTAssertTrue(report.launch.coldMilliseconds.isEmpty)
        XCTAssertTrue(report.allocations.bytesPerGesture.isEmpty)
        XCTAssertTrue(report.redrawLayout.sampleMilliseconds.isEmpty)
        XCTAssertTrue(report.responsiveness.responseMilliseconds.isEmpty)
        XCTAssertTrue(report.inputToVisible.sampleMilliseconds.isEmpty)
        XCTAssertTrue(report.memory.samples.isEmpty)
        XCTAssertEqual(report.disposition, .revise)
        XCTAssertNoThrow(try report.validateStructure())
    }

    func testFinalizerPreservesOneFailedMetricAmongMeasuredWithoutMixingValues() throws {
        let samples = metricSamples(status: .measured, failedMetric: .renderer)
        let results = (0..<30).map { index in
            let order: PairOrder = index < 15 ? .baselineFirst : .candidateFirst
            return makeResult(variant: .baseline, pairIndex: index, order: order, samples: samples)
        }
        let report = try PerformancePairExecutionFinalizer.aggregateReport(
            results: results,
            configuration: .standard12,
            build: PerformanceFixtures.baselineBuild,
            run: PerformanceFixtures.baselineRun,
            identity: PerformanceFixtures.baselineIdentity
        )
        XCTAssertEqual(report.model.status, .measured)
        XCTAssertEqual(report.model.trialNanoseconds.count, 30)
        XCTAssertEqual(report.renderer.status, .failed)
        XCTAssertTrue(report.renderer.frameMilliseconds.isEmpty)
        XCTAssertEqual(report.compositor.status, .measured)
        XCTAssertEqual(report.compositor.frameMilliseconds.count, 30)
        XCTAssertEqual(report.launch.status, .measured)
        XCTAssertEqual(report.launch.coldMilliseconds.count, 30)
        XCTAssertEqual(report.inputToVisible.status, .measured)
        XCTAssertEqual(report.inputToVisible.sampleMilliseconds.count, 30)
        XCTAssertEqual(report.disposition, .revise)
        XCTAssertNoThrow(try report.validateStructure())
    }

    func testFinalizerPreservesUnmeasuredMetricStatusesAndEmptyRawArrays() throws {
        let unmeasuredSamples = metricSamples(status: .unmeasured)
        let results = (0..<30).map { index in
            let order: PairOrder = index < 15 ? .baselineFirst : .candidateFirst
            return makeResult(variant: .baseline, pairIndex: index, order: order, samples: unmeasuredSamples)
        }
        let report = try PerformancePairExecutionFinalizer.aggregateReport(
            results: results,
            configuration: .standard12,
            build: PerformanceFixtures.baselineBuild,
            run: PerformanceFixtures.baselineRun,
            identity: PerformanceFixtures.baselineIdentity
        )
        XCTAssertEqual(report.model.status, .unmeasured)
        XCTAssertEqual(report.renderer.status, .unmeasured)
        XCTAssertEqual(report.compositor.status, .unmeasured)
        XCTAssertEqual(report.launch.status, .unmeasured)
        XCTAssertEqual(report.allocations.status, .unmeasured)
        XCTAssertEqual(report.redrawLayout.status, .unmeasured)
        XCTAssertEqual(report.responsiveness.status, .unmeasured)
        XCTAssertEqual(report.inputToVisible.status, .unmeasured)
        XCTAssertEqual(report.memory.status, .unmeasured)
        XCTAssertTrue(report.model.trialNanoseconds.isEmpty)
        XCTAssertTrue(report.renderer.frameMilliseconds.isEmpty)
        XCTAssertTrue(report.launch.coldMilliseconds.isEmpty)
        XCTAssertTrue(report.inputToVisible.sampleMilliseconds.isEmpty)
        XCTAssertEqual(report.disposition, .revise)
        XCTAssertNoThrow(try report.validateStructure())
    }

    func testFinalizerDerivesAcceptedDispositionOnlyForCompleteMeasuredEvidence() throws {
        let results = (0..<30).map { index in
            let order: PairOrder = index < 15 ? .baselineFirst : .candidateFirst
            return makeResult(variant: .baseline, pairIndex: index, order: order)
        }
        let resultHashes = try results.map { try sha256(PerformanceCanonicalJSON.data(for: $0)) }
        let externalAggregate = PerformanceExternalAggregateSidecar(
            binding: PerformanceExternalAggregateBinding(
                variant: .baseline,
                fixtureProfile: .standard12,
                sourceIdentity: PerformanceFixtures.baselineBuild.sourceIdentity,
                runProvenanceSHA256: String(repeating: "0", count: 64),
                pairEligibilitySHA256: String(repeating: "0", count: 64)
            ),
            resultSHA256s: resultHashes,
            memory: PerformanceFixtures.memory,
            resilience: PerformanceFixtures.resilience
        )
        let report = try PerformancePairExecutionFinalizer.aggregateReport(
            results: results,
            configuration: .standard12,
            build: PerformanceFixtures.baselineBuild,
            run: PerformanceFixtures.baselineRun,
            identity: PerformanceFixtures.baselineIdentity,
            externalAggregate: externalAggregate
        )
        XCTAssertEqual(report.disposition, .acceptedNoRegression)
        XCTAssertNoThrow(try report.validateCompletion())
    }

    func testProductionScalarTurnsInvalidMeasuredPayloadIntoStableFailure() throws {
        let missing = ProductionPerformanceTrialExecutor.scalar(
            metricID: .renderer,
            unit: .milliseconds,
            status: .measured,
            value: nil,
            diagnostic: "ignored"
        )
        XCTAssertEqual(missing.status, .failed)
        XCTAssertNil(missing.value)
        XCTAssertEqual(missing.diagnostic, "trial-renderer-invalid-measured-scalar")
        let nonFinite = ProductionPerformanceTrialExecutor.scalar(
            metricID: .renderer,
            unit: .milliseconds,
            status: .measured,
            value: .infinity,
            diagnostic: "ignored"
        )
        XCTAssertEqual(nonFinite.status, .failed)
        XCTAssertEqual(nonFinite.diagnostic, "trial-renderer-invalid-measured-scalar")
    }

    func testTrialCLIRequiresCanonicalProvenanceEligibilityAndLeavesNoPartialOnFailure() throws {
        let root = try temporaryDirectory("pointer-cli-trust")
        defer { try? FileManager.default.removeItem(at: root) }
        let performanceRoot = root.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance", isDirectory: true)
        let profileRoot = performanceRoot.appendingPathComponent("standard12", isDirectory: true)
        let buildRoot = root.appendingPathComponent("build/standard12", isDirectory: true)
        let partialURL = buildRoot.appendingPathComponent("pair-execution/partial/0.json")
        let runURL = buildRoot.appendingPathComponent("baseline/provenance.json")
        let eligibilityURL = profileRoot.appendingPathComponent("comparisons/pair-eligibility.json")
        let args = [
            "--quality-performance", "--format", "json", "--operation", "trial",
            "--fixture-profile", "standard12", "--variant", "baseline",
            "--pair-order", "baselineFirst", "--pair-index", "0",
            "--source-commit-sha", PerformanceFixtures.baselineCommit,
            "--run-provenance-file", runURL.path,
            "--pair-eligibility-file", eligibilityURL.path,
            "--partial-pair-directory", partialURL.deletingLastPathComponent().path
        ]
        let executor = RecordingTrialExecutor()
        PerformanceCLI.trialExecutor = executor
        defer { PerformanceCLI.trialExecutor = nil }
        let validEligibility = PerformancePairEligibility(
            baselineRoot: buildRoot.appendingPathComponent("baseline", isDirectory: true).path,
            candidateRoot: buildRoot.appendingPathComponent("candidate", isDirectory: true).path,
            baselineCommitSHA: PerformanceFixtures.baselineCommit,
            candidateCommitSHA: PerformanceFixtures.commit,
            foundationProvenance: PerformanceFixtures.foundationProvenance
        )
        try FileManager.default.createDirectory(at: eligibilityURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PerformanceCanonicalJSON.data(for: validEligibility).write(to: eligibilityURL)
        try Data("{\"unknown\":true}".utf8).write(to: runURL)
        var firstDiagnostic = ""
        XCTAssertThrowsError(try PerformanceCLI.run(arguments: args, outputDirectory: root)) { error in
            firstDiagnostic = String(describing: error)
        }
        XCTAssertTrue(firstDiagnostic.contains("keyNotFound") || firstDiagnostic.contains("dataCorrupted"), firstDiagnostic)
        XCTAssertEqual(executor.sampleCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
        let validRun = PerformanceRunProvenance(
            variant: "baseline",
            outputRoot: buildRoot.appendingPathComponent("baseline", isDirectory: true).path,
            sourceRef: PerformanceFixtures.baselineCommit,
            build: PerformanceFixtures.baselineBuild,
            host: PerformanceFixtures.host,
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            configuration: PerformanceFixtures.configuration,
            foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: PerformanceFixtures.configuration.harnessVersion,
            buildContractVersion: PerformanceFixtures.configuration.buildContractVersion,
            acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
        )
        try PerformanceCanonicalJSON.data(for: validRun).write(to: runURL)
        try Data("{\"unknown\":true}".utf8).write(to: eligibilityURL)
        var secondDiagnostic = ""
        XCTAssertThrowsError(try PerformanceCLI.run(arguments: args, outputDirectory: root)) { error in
            secondDiagnostic = String(describing: error)
        }
        XCTAssertTrue(secondDiagnostic.contains("keyNotFound") || secondDiagnostic.contains("dataCorrupted"), secondDiagnostic)
        XCTAssertEqual(executor.sampleCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
    }

    func testTrialCLIRejectsRelativeDecodedBuildRootsBeforeMeasuring() throws {
        for relativeRunRoot in [true, false] {
            let root = try temporaryDirectory("pointer-cli-relative-wire-root")
            defer { try? FileManager.default.removeItem(at: root) }
            let performanceRoot = root.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance", isDirectory: true)
            let profileRoot = performanceRoot.appendingPathComponent("standard12", isDirectory: true)
            let buildRoot = root.appendingPathComponent("build/standard12", isDirectory: true)
            let baselineRoot = buildRoot.appendingPathComponent("baseline", isDirectory: true)
            let candidateRoot = buildRoot.appendingPathComponent("candidate", isDirectory: true)
            let partialDirectory = buildRoot.appendingPathComponent("pair-execution/partial", isDirectory: true)
            let runURL = baselineRoot.appendingPathComponent("provenance.json")
            let eligibilityURL = profileRoot.appendingPathComponent("comparisons/pair-eligibility.json")
            let run = PerformanceRunProvenance(
                variant: "baseline",
                outputRoot: relativeRunRoot ? "build/standard12/baseline" : baselineRoot.path,
                sourceRef: PerformanceFixtures.baselineCommit,
                build: PerformanceFixtures.baselineBuild,
                host: PerformanceFixtures.host,
                recordedAtUTC: PerformanceFixtures.recordedAtUTC,
                configuration: PerformanceFixtures.configuration,
                foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath,
                foundation: PerformanceFixtures.foundation,
                harnessVersion: PerformanceFixtures.configuration.harnessVersion,
                buildContractVersion: PerformanceFixtures.configuration.buildContractVersion,
                acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
            )
            let eligibility = PerformancePairEligibility(
                baselineRoot: relativeRunRoot ? baselineRoot.path : "build/standard12/baseline",
                candidateRoot: candidateRoot.path,
                baselineCommitSHA: PerformanceFixtures.baselineCommit,
                candidateCommitSHA: PerformanceFixtures.commit,
                foundationProvenance: PerformanceFixtures.foundationProvenance
            )
            let runData = try PerformanceCanonicalJSON.data(for: run)
            let eligibilityData = try PerformanceCanonicalJSON.data(for: eligibility)
            try FileManager.default.createDirectory(at: runURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: eligibilityURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try runData.write(to: runURL)
            try eligibilityData.write(to: eligibilityURL)
            let args = [
                "--quality-performance", "--format", "json", "--operation", "trial",
                "--fixture-profile", "standard12", "--variant", "baseline",
                "--pair-order", "baselineFirst", "--pair-index", "0",
                "--source-commit-sha", PerformanceFixtures.baselineCommit,
                "--run-provenance-file", runURL.path,
                "--pair-eligibility-file", eligibilityURL.path,
                "--partial-pair-directory", partialDirectory.path
            ]
            let executor = RecordingTrialExecutor()
            PerformanceCLI.trialExecutor = executor
            defer { PerformanceCLI.trialExecutor = nil }
            XCTAssertThrowsError(try PerformanceCLI.run(arguments: args, outputDirectory: root), "relative decoded root (relativeRunRoot) must be rejected")
            XCTAssertEqual(executor.sampleCount, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: partialDirectory.appendingPathComponent("0.json").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: profileRoot.appendingPathComponent("measurements", isDirectory: true).path))
        }
    }

    func testTrialCLIAcceptsDiagnosticContentManifestIdentityBoundToRunCommit() throws {
        let root = try temporaryDirectory("pointer-cli-content-identity")
        defer { try? FileManager.default.removeItem(at: root) }
        let performanceRoot = root.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance", isDirectory: true)
        let profileRoot = performanceRoot.appendingPathComponent("standard12", isDirectory: true)
        let buildRoot = root.appendingPathComponent("build/standard12", isDirectory: true)
        let partialDirectory = buildRoot.appendingPathComponent("pair-execution/partial", isDirectory: true)
        let eligibilityURL = profileRoot.appendingPathComponent("comparisons/pair-eligibility.json")
        let runURL = buildRoot.appendingPathComponent("candidate/provenance.json")
        let contentIdentity = SourceIdentity(kind: .contentManifestSHA256, value: PerformanceFixtures.sourceManifest)
        let dirtyBuild = BuildProvenance(
            sourceTreeStatus: .dirty,
            sourceIdentity: contentIdentity,
            sourceManifestSHA256: PerformanceFixtures.sourceManifest,
            executableSHA256: PerformanceFixtures.executable,
            bundleManifestSHA256: PerformanceFixtures.bundle,
            buildConfiguration: "debug",
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: PerformanceFixtures.configuration.harnessVersion,
            buildContractVersion: PerformanceFixtures.configuration.buildContractVersion,
            acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
        )
        let run = PerformanceRunProvenance(
            variant: "candidate",
            outputRoot: buildRoot.appendingPathComponent("candidate", isDirectory: true).path,
            sourceRef: PerformanceFixtures.commit,
            build: dirtyBuild,
            host: PerformanceFixtures.host,
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            configuration: PerformanceFixtures.configuration,
            foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: PerformanceFixtures.configuration.harnessVersion,
            buildContractVersion: PerformanceFixtures.configuration.buildContractVersion,
            acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
        )
        let eligibility = PerformancePairEligibility(
            baselineRoot: buildRoot.appendingPathComponent("baseline", isDirectory: true).path,
            candidateRoot: run.outputRoot,
            baselineCommitSHA: PerformanceFixtures.baselineCommit,
            candidateCommitSHA: PerformanceFixtures.commit,
            foundationProvenance: PerformanceFixtures.foundationProvenance
        )
        let runData = try PerformanceCanonicalJSON.data(for: run)
        let eligibilityData = try PerformanceCanonicalJSON.data(for: eligibility)
        try FileManager.default.createDirectory(at: eligibilityURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try runData.write(to: runURL)
        try eligibilityData.write(to: eligibilityURL)
        let request = PerformanceTrialRequest(variant: .candidate, fixtureProfile: .standard12, pairIndex: 15, order: .candidateFirst, sampleIndex: 15)
        let sidecar = PerformanceExternalTrialSidecar(
            binding: PerformanceExternalTrialBinding(
                request: request,
                sourceIdentity: contentIdentity,
                runProvenanceSHA256: sha256(runData),
                pairEligibilitySHA256: sha256(eligibilityData),
                startedAtUTC: "2026-01-01T00:00:00.123Z",
                endedAtUTC: "2027-01-01T00:00:00.123Z"
            ),
            measurements: PerformanceExternalTrialSidecar.requiredMetricIDs.enumerated().map { index, metricID in
                PerformanceExternalTrialScalarMeasurement(metricID: metricID, unit: metricID.canonicalUnit, status: .measured, value: Double(index + 1), diagnostic: nil)
            }
        )
        let sidecarURL = profileRoot.appendingPathComponent("external/trials/candidate/15.json")
        try FileManager.default.createDirectory(at: sidecarURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let sidecarData = try PerformanceCanonicalJSON.data(for: sidecar)
        try sidecarData.write(to: sidecarURL)
        let badSidecar = PerformanceExternalTrialSidecar(
            binding: PerformanceExternalTrialBinding(
                request: request,
                sourceIdentity: SourceIdentity(kind: .contentManifestSHA256, value: String(repeating: "c", count: 64)),
                runProvenanceSHA256: sha256(runData),
                pairEligibilitySHA256: sha256(eligibilityData),
                startedAtUTC: "2026-01-01T00:00:00.123Z",
                endedAtUTC: "2027-01-01T00:00:00.123Z"
            ),
            measurements: sidecar.measurements
        )
        try PerformanceCanonicalJSON.data(for: badSidecar).write(to: sidecarURL)
        let executor = RecordingTrialExecutor()
        PerformanceCLI.trialExecutor = executor
        defer { PerformanceCLI.trialExecutor = nil }
        let args = [
            "--quality-performance", "--format", "json", "--operation", "trial",
            "--fixture-profile", "standard12", "--variant", "candidate",
            "--pair-order", "candidateFirst", "--pair-index", "15",
            "--content-manifest-sha256", PerformanceFixtures.sourceManifest,
            "--run-provenance-file", runURL.path,
            "--pair-eligibility-file", eligibilityURL.path,
            "--external-trial-sidecar", sidecarURL.path,
            "--partial-pair-directory", partialDirectory.path
        ]
        XCTAssertThrowsError(try PerformanceCLI.run(arguments: args, outputDirectory: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialDirectory.appendingPathComponent("15.json").path))
        XCTAssertEqual(executor.sampleCount, 0)
        let outsideSidecar = PerformanceExternalTrialSidecar(
            binding: PerformanceExternalTrialBinding(
                request: request,
                sourceIdentity: contentIdentity,
                runProvenanceSHA256: sha256(runData),
                pairEligibilitySHA256: sha256(eligibilityData),
                startedAtUTC: "2999-01-01T00:00:00.123Z",
                endedAtUTC: "2999-01-01T00:00:01.123Z"
            ),
            measurements: sidecar.measurements
        )
        let outsideSidecarURL = profileRoot.appendingPathComponent("external/trials/candidate/outside-15.json")
        try PerformanceCanonicalJSON.data(for: outsideSidecar).write(to: outsideSidecarURL)
        let outsideArgs = args.map { value in
            value == sidecarURL.path ? outsideSidecarURL.path : value
        }
        XCTAssertThrowsError(try PerformanceCLI.run(arguments: outsideArgs, outputDirectory: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialDirectory.appendingPathComponent("15.json").path))
        XCTAssertEqual(executor.sampleCount, 0)
        try sidecarData.write(to: sidecarURL)
        try PerformanceCLI.run(arguments: args, outputDirectory: root)
        let partial = try PerformancePartialPairStore(directory: partialDirectory).load(pairOrder: .candidateFirst, pairIndex: 15)
        XCTAssertEqual(partial.candidate?.sourceIdentity, contentIdentity)
        XCTAssertNotEqual(partial.candidate?.startedAtUTC, "2026-01-01T00:00:00.123Z")
        XCTAssertNotEqual(partial.candidate?.endedAtUTC, "2027-01-01T00:00:00.123Z")
        let actualStart = try XCTUnwrap(PerformanceTimestamp.date(from: partial.candidate!.startedAtUTC))
        let actualEnd = try XCTUnwrap(PerformanceTimestamp.date(from: partial.candidate!.endedAtUTC))
        XCTAssertGreaterThanOrEqual(actualStart, try XCTUnwrap(PerformanceTimestamp.date(from: "2026-01-01T00:00:00.123Z")))
        XCTAssertLessThanOrEqual(actualEnd, try XCTUnwrap(PerformanceTimestamp.date(from: "2027-01-01T00:00:00.123Z")))
        XCTAssertEqual(partial.candidate?.samples.first(where: { $0.metricID == .compositor })?.value, 1)
        XCTAssertEqual(partial.candidate?.samples.first(where: { $0.metricID == .memoryRSS })?.status, .measured)
        XCTAssertEqual(executor.sampleCount, 1)
    }

    func testTrialCLIRetryReturnsExistingResultWithoutMeasuring() throws {
        let root = try temporaryDirectory("pointer-cli-retry")
        defer { try? FileManager.default.removeItem(at: root) }
        let performanceRoot = root.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance", isDirectory: true)
        let profileRoot = performanceRoot.appendingPathComponent("standard12", isDirectory: true)
        let buildRoot = root.appendingPathComponent("build/standard12", isDirectory: true)
        let partialDirectory = buildRoot.appendingPathComponent("pair-execution/partial", isDirectory: true)
        let eligibilityURL = profileRoot.appendingPathComponent("comparisons/pair-eligibility.json")
        let runURL = buildRoot.appendingPathComponent("baseline/provenance.json")
        let baselineRoot = buildRoot.appendingPathComponent("baseline", isDirectory: true).path
        let candidateRoot = buildRoot.appendingPathComponent("candidate", isDirectory: true).path
        let run = PerformanceRunProvenance(
            variant: "baseline",
            outputRoot: baselineRoot,
            sourceRef: PerformanceFixtures.baselineCommit,
            build: PerformanceFixtures.baselineBuild,
            host: PerformanceFixtures.host,
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            configuration: PerformanceFixtures.configuration,
            foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: PerformanceFixtures.configuration.harnessVersion,
            buildContractVersion: PerformanceFixtures.configuration.buildContractVersion,
            acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
        )
        let eligibility = PerformancePairEligibility(
            baselineRoot: baselineRoot,
            candidateRoot: candidateRoot,
            baselineCommitSHA: PerformanceFixtures.baselineCommit,
            candidateCommitSHA: PerformanceFixtures.commit,
            foundationProvenance: PerformanceFixtures.foundationProvenance
        )
        let runData = try PerformanceCanonicalJSON.data(for: run)
        let eligibilityData = try PerformanceCanonicalJSON.data(for: eligibility)
        try FileManager.default.createDirectory(at: eligibilityURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try runData.write(to: runURL)
        try eligibilityData.write(to: eligibilityURL)
        let runHash = sha256(runData)
        let eligibilityHash = sha256(eligibilityData)
        let existingSamples = PerformanceMetricID.allCases.enumerated().map { index, metricID in
            if PerformanceExternalTrialSidecar.requiredMetricIDs.contains(metricID) {
                return PerformanceTrialMetricSample(metricID: metricID, unit: metricID.canonicalUnit, status: .unmeasured, value: nil, diagnostic: "external-\(metricID.rawValue)-unavailable")
            }
            return PerformanceTrialMetricSample(metricID: metricID, unit: metricID.canonicalUnit, status: .measured, value: Double(index + 1), diagnostic: nil)
        }
        let existing = makeResult(
            variant: .baseline,
            pairIndex: 0,
            order: .baselineFirst,
            runProvenanceSHA256: runHash,
            pairEligibilitySHA256: eligibilityHash,
            samples: existingSamples
        )
        _ = try PerformancePartialPairStore(directory: partialDirectory).store(
            PerformancePartialPair(fixtureProfile: .standard12, pairIndex: 0, order: .baselineFirst, baseline: existing)
        )
        let executor = RecordingTrialExecutor()
        PerformanceCLI.trialExecutor = executor
        defer { PerformanceCLI.trialExecutor = nil }
        let args = [
            "--quality-performance", "--format", "json", "--operation", "trial",
            "--fixture-profile", "standard12", "--variant", "baseline",
            "--pair-order", "baselineFirst", "--pair-index", "0",
            "--source-commit-sha", PerformanceFixtures.baselineCommit,
            "--run-provenance-file", runURL.path,
            "--pair-eligibility-file", eligibilityURL.path,
            "--partial-pair-directory", partialDirectory.path
        ]
        try PerformanceCLI.run(arguments: args, outputDirectory: root)
        let loaded = try PerformancePartialPairStore(directory: partialDirectory).load(pairOrder: .baselineFirst, pairIndex: 0)
        XCTAssertEqual(executor.warmupCount, 0)
        XCTAssertEqual(executor.sampleCount, 0)
        XCTAssertEqual(loaded.baseline, existing)
    }

    func testTrialCLIRetryResolvesExternalSidecarSamplesAndBindingWithoutMeasuring() throws {
        let root = try temporaryDirectory("pointer-cli-retry-sidecar")
        defer { try? FileManager.default.removeItem(at: root) }
        let performanceRoot = root.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance", isDirectory: true)
        let profileRoot = performanceRoot.appendingPathComponent("standard12", isDirectory: true)
        let buildRoot = root.appendingPathComponent("build/standard12", isDirectory: true)
        let partialDirectory = buildRoot.appendingPathComponent("pair-execution/partial", isDirectory: true)
        let eligibilityURL = profileRoot.appendingPathComponent("comparisons/pair-eligibility.json")
        let runURL = buildRoot.appendingPathComponent("baseline/provenance.json")
        let baselineRoot = buildRoot.appendingPathComponent("baseline", isDirectory: true).path
        let candidateRoot = buildRoot.appendingPathComponent("candidate", isDirectory: true).path
        let run = PerformanceRunProvenance(
            variant: "baseline",
            outputRoot: baselineRoot,
            sourceRef: PerformanceFixtures.baselineCommit,
            build: PerformanceFixtures.baselineBuild,
            host: PerformanceFixtures.host,
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            configuration: PerformanceFixtures.configuration,
            foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: PerformanceFixtures.configuration.harnessVersion,
            buildContractVersion: PerformanceFixtures.configuration.buildContractVersion,
            acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
        )
        let eligibility = PerformancePairEligibility(
            baselineRoot: baselineRoot,
            candidateRoot: candidateRoot,
            baselineCommitSHA: PerformanceFixtures.baselineCommit,
            candidateCommitSHA: PerformanceFixtures.commit,
            foundationProvenance: PerformanceFixtures.foundationProvenance
        )
        let runData = try PerformanceCanonicalJSON.data(for: run)
        let eligibilityData = try PerformanceCanonicalJSON.data(for: eligibility)
        try FileManager.default.createDirectory(at: eligibilityURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try runData.write(to: runURL)
        try eligibilityData.write(to: eligibilityURL)
        let runHash = sha256(runData)
        let eligibilityHash = sha256(eligibilityData)
        let existing = makeResult(variant: .baseline, pairIndex: 0, order: .baselineFirst, runProvenanceSHA256: runHash, pairEligibilitySHA256: eligibilityHash)
        _ = try PerformancePartialPairStore(directory: partialDirectory).store(
            PerformancePartialPair(fixtureProfile: .standard12, pairIndex: 0, order: .baselineFirst, baseline: existing)
        )
        let sidecarMeasurements = PerformanceExternalTrialSidecar.requiredMetricIDs.map { metricID in
            let sample = existing.samples.first { $0.metricID == metricID }!
            return PerformanceExternalTrialScalarMeasurement(metricID: metricID, unit: sample.unit, status: sample.status, value: sample.value, diagnostic: sample.diagnostic)
        }
        let binding = PerformanceExternalTrialBinding(
            request: existing.request,
            sourceIdentity: existing.sourceIdentity,
            runProvenanceSHA256: runHash,
            pairEligibilitySHA256: eligibilityHash,
            startedAtUTC: "2026-01-01T00:00:00.123Z",
            endedAtUTC: "2027-01-01T00:00:00.123Z"
        )
        let sidecar = PerformanceExternalTrialSidecar(binding: binding, measurements: sidecarMeasurements)
        let sidecarURL = profileRoot.appendingPathComponent("external/trials/baseline/0.json")
        try FileManager.default.createDirectory(at: sidecarURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PerformanceCanonicalJSON.data(for: sidecar).write(to: sidecarURL)
        let changedSidecar = PerformanceExternalTrialSidecar(
            binding: binding,
            measurements: sidecarMeasurements.enumerated().map { index, measurement in
                index == 0
                    ? PerformanceExternalTrialScalarMeasurement(metricID: measurement.metricID, unit: measurement.unit, status: .measured, value: (measurement.value ?? 0) + 1, diagnostic: nil)
                    : measurement
            }
        )
        let changedSidecarURL = profileRoot.appendingPathComponent("external/trials/baseline/changed-0.json")
        try PerformanceCanonicalJSON.data(for: changedSidecar).write(to: changedSidecarURL)
        let executor = RecordingTrialExecutor()
        PerformanceCLI.trialExecutor = executor
        defer { PerformanceCLI.trialExecutor = nil }
        let args = [
            "--quality-performance", "--format", "json", "--operation", "trial",
            "--fixture-profile", "standard12", "--variant", "baseline",
            "--pair-order", "baselineFirst", "--pair-index", "0",
            "--source-commit-sha", PerformanceFixtures.baselineCommit,
            "--run-provenance-file", runURL.path,
            "--pair-eligibility-file", eligibilityURL.path,
            "--external-trial-sidecar", sidecarURL.path,
            "--partial-pair-directory", partialDirectory.path
        ]
        try PerformanceCLI.run(arguments: args, outputDirectory: root)
        XCTAssertEqual(executor.sampleCount, 0)
        let changedArgs = args.map { $0 == sidecarURL.path ? changedSidecarURL.path : $0 }
        XCTAssertThrowsError(try PerformanceCLI.run(arguments: changedArgs, outputDirectory: root))
        XCTAssertEqual(executor.sampleCount, 0)
        let omittedArgs = args.filter { $0 != "--external-trial-sidecar" && $0 != sidecarURL.path }
        XCTAssertThrowsError(try PerformanceCLI.run(arguments: omittedArgs, outputDirectory: root))
        XCTAssertEqual(executor.sampleCount, 0)
        XCTAssertEqual(try PerformancePartialPairStore(directory: partialDirectory).load(pairOrder: .baselineFirst, pairIndex: 0).baseline, existing)
    }

    func testTrialCLIPremeasureAuditRejectsEveryExistingIllegalPartialBeforeExecutor() throws {
        for scenario in ["malformed", "noncanonical", "wrong-profile", "symlink"] {
            let root = try temporaryDirectory("pointer-cli-premeasure-(scenario)")
            defer { try? FileManager.default.removeItem(at: root) }
            let performanceRoot = root.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance", isDirectory: true)
            let profileRoot = performanceRoot.appendingPathComponent("standard12", isDirectory: true)
            let buildRoot = root.appendingPathComponent("build/standard12", isDirectory: true)
            let partialDirectory = buildRoot.appendingPathComponent("pair-execution/partial", isDirectory: true)
            let baselineURL = buildRoot.appendingPathComponent("baseline/provenance.json")
            let candidateURL = buildRoot.appendingPathComponent("candidate/provenance.json")
            let eligibilityURL = profileRoot.appendingPathComponent("comparisons/pair-eligibility.json")
            let baselineRun = PerformanceRunProvenance(
                variant: "baseline",
                outputRoot: buildRoot.appendingPathComponent("baseline", isDirectory: true).path,
                sourceRef: PerformanceFixtures.baselineCommit,
                build: PerformanceFixtures.baselineBuild,
                host: PerformanceFixtures.host,
                recordedAtUTC: PerformanceFixtures.recordedAtUTC,
                configuration: PerformanceFixtures.configuration,
                foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath,
                foundation: PerformanceFixtures.foundation,
                harnessVersion: PerformanceFixtures.configuration.harnessVersion,
                buildContractVersion: PerformanceFixtures.configuration.buildContractVersion,
                acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
            )
            let candidateRun = PerformanceRunProvenance(
                variant: "candidate",
                outputRoot: buildRoot.appendingPathComponent("candidate", isDirectory: true).path,
                sourceRef: PerformanceFixtures.commit,
                build: PerformanceFixtures.build,
                host: PerformanceFixtures.host,
                recordedAtUTC: PerformanceFixtures.recordedAtUTC,
                configuration: PerformanceFixtures.configuration,
                foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath,
                foundation: PerformanceFixtures.foundation,
                harnessVersion: PerformanceFixtures.configuration.harnessVersion,
                buildContractVersion: PerformanceFixtures.configuration.buildContractVersion,
                acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
            )
            let eligibility = PerformancePairEligibility(
                baselineRoot: baselineRun.outputRoot,
                candidateRoot: candidateRun.outputRoot,
                baselineCommitSHA: baselineRun.sourceRef,
                candidateCommitSHA: candidateRun.sourceRef,
                foundationProvenance: PerformanceFixtures.foundationProvenance
            )
            let baselineData = try PerformanceCanonicalJSON.data(for: baselineRun)
            let candidateData = try PerformanceCanonicalJSON.data(for: candidateRun)
            let eligibilityData = try PerformanceCanonicalJSON.data(for: eligibility)
            try FileManager.default.createDirectory(at: baselineURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: candidateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try baselineData.write(to: baselineURL)
            try candidateData.write(to: candidateURL)
            try FileManager.default.createDirectory(at: eligibilityURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try eligibilityData.write(to: eligibilityURL)
            let baselineHash = sha256(baselineData)
            let eligibilityHash = sha256(eligibilityData)
            let store = PerformancePartialPairStore(directory: partialDirectory)
            _ = try store.store(PerformancePartialPair(
                fixtureProfile: .standard12,
                pairIndex: 0,
                order: .baselineFirst,
                baseline: makeResult(variant: .baseline, pairIndex: 0, order: .baselineFirst, runProvenanceSHA256: baselineHash, pairEligibilitySHA256: eligibilityHash)
            ))
            let illegalURL = partialDirectory.appendingPathComponent("1.json")
            switch scenario {
            case "malformed":
                try Data("{}".utf8).write(to: illegalURL)
            case "noncanonical":
                let valid = PerformancePartialPair(
                    fixtureProfile: .standard12,
                    pairIndex: 1,
                    order: .baselineFirst,
                    baseline: makeResult(variant: .baseline, pairIndex: 1, order: .baselineFirst, runProvenanceSHA256: baselineHash, pairEligibilitySHA256: eligibilityHash)
                )
                var bytes = try PerformanceCanonicalJSON.data(for: valid)
                bytes.append(10)
                try bytes.write(to: illegalURL)
            case "wrong-profile":
                let request = PerformanceTrialRequest(variant: .baseline, fixtureProfile: .dense1000, pairIndex: 1, order: .baselineFirst, sampleIndex: 1)
                _ = try store.store(PerformancePartialPair(
                    fixtureProfile: .dense1000,
                    pairIndex: 1,
                    order: .baselineFirst,
                    baseline: makeResult(variant: .baseline, pairIndex: 1, order: .baselineFirst, runProvenanceSHA256: baselineHash, pairEligibilitySHA256: eligibilityHash, request: request)
                ))
            case "symlink":
                let target = root.appendingPathComponent("partial-target.json")
                let valid = PerformancePartialPair(
                    fixtureProfile: .standard12,
                    pairIndex: 1,
                    order: .baselineFirst,
                    baseline: makeResult(variant: .baseline, pairIndex: 1, order: .baselineFirst, runProvenanceSHA256: baselineHash, pairEligibilitySHA256: eligibilityHash)
                )
                try PerformanceCanonicalJSON.data(for: valid).write(to: target)
                try FileManager.default.createSymbolicLink(at: illegalURL, withDestinationURL: target)
            default:
                XCTFail("unhandled premeasure scenario")
            }
            let executor = RecordingTrialExecutor()
            PerformanceCLI.trialExecutor = executor
            let args = [
                "--quality-performance", "--format", "json", "--operation", "trial",
                "--fixture-profile", "standard12", "--variant", "candidate",
                "--pair-order", "candidateFirst", "--pair-index", "15",
                "--source-commit-sha", PerformanceFixtures.commit,
                "--run-provenance-file", candidateURL.path,
                "--pair-eligibility-file", eligibilityURL.path,
                "--partial-pair-directory", partialDirectory.path
            ]
            XCTAssertThrowsError(try PerformanceCLI.run(arguments: args, outputDirectory: root), scenario)
            XCTAssertEqual(executor.sampleCount, 0, scenario)
            XCTAssertFalse(FileManager.default.fileExists(atPath: partialDirectory.appendingPathComponent("15.json").path), scenario)
            PerformanceCLI.trialExecutor = nil
        }
    }

    func testTrialCLIRejectsSymlinkedCanonicalPartialDirectoryBeforeExecutor() throws {
        let root = try temporaryDirectory("pointer-cli-partial-symlink")
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.appendingPathComponent("outside-partial", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let performanceRoot = root.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance", isDirectory: true)
        let profileRoot = performanceRoot.appendingPathComponent("standard12", isDirectory: true)
        let buildRoot = root.appendingPathComponent("build/standard12", isDirectory: true)
        let partialParent = buildRoot.appendingPathComponent("pair-execution", isDirectory: true)
        let partialDirectory = partialParent.appendingPathComponent("partial", isDirectory: true)
        try FileManager.default.createDirectory(at: partialParent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: partialDirectory, withDestinationURL: outside)
        let baselineRoot = buildRoot.appendingPathComponent("baseline", isDirectory: true)
        let candidateRoot = buildRoot.appendingPathComponent("candidate", isDirectory: true)
        let runURL = baselineRoot.appendingPathComponent("provenance.json")
        let eligibilityURL = profileRoot.appendingPathComponent("comparisons/pair-eligibility.json")
        let run = PerformanceRunProvenance(
            variant: "baseline",
            outputRoot: baselineRoot.path,
            sourceRef: PerformanceFixtures.baselineCommit,
            build: PerformanceFixtures.baselineBuild,
            host: PerformanceFixtures.host,
            recordedAtUTC: PerformanceFixtures.recordedAtUTC,
            configuration: PerformanceFixtures.configuration,
            foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath,
            foundation: PerformanceFixtures.foundation,
            harnessVersion: PerformanceFixtures.configuration.harnessVersion,
            buildContractVersion: PerformanceFixtures.configuration.buildContractVersion,
            acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
        )
        let eligibility = PerformancePairEligibility(
            baselineRoot: baselineRoot.path,
            candidateRoot: candidateRoot.path,
            baselineCommitSHA: PerformanceFixtures.baselineCommit,
            candidateCommitSHA: PerformanceFixtures.commit,
            foundationProvenance: PerformanceFixtures.foundationProvenance
        )
        try FileManager.default.createDirectory(at: runURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: eligibilityURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PerformanceCanonicalJSON.data(for: run).write(to: runURL)
        try PerformanceCanonicalJSON.data(for: eligibility).write(to: eligibilityURL)
        let args = [
            "--quality-performance", "--format", "json", "--operation", "trial",
            "--fixture-profile", "standard12", "--variant", "baseline",
            "--pair-order", "baselineFirst", "--pair-index", "0",
            "--source-commit-sha", PerformanceFixtures.baselineCommit,
            "--run-provenance-file", runURL.path,
            "--pair-eligibility-file", eligibilityURL.path,
            "--partial-pair-directory", partialDirectory.path
        ]
        let executor = RecordingTrialExecutor()
        PerformanceCLI.trialExecutor = executor
        defer { PerformanceCLI.trialExecutor = nil }
        var diagnostic = ""
        XCTAssertThrowsError(try PerformanceCLI.run(arguments: args, outputDirectory: root)) { error in
            diagnostic = String(describing: error)
        }
        XCTAssertTrue(diagnostic.contains("symbolic") || diagnostic.contains("directory"), diagnostic)
        XCTAssertEqual(executor.sampleCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("0.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("0.json.lock").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("0.json.tmp").path))
    }

    func testPartialStoreLoadAllRejectsPostTrialSymlinkSwap() throws {
        let root = try temporaryDirectory("pointer-partial-post-trial-symlink")
        defer { try? FileManager.default.removeItem(at: root) }
        let partialDirectory = root.appendingPathComponent("partial", isDirectory: true)
        let store = PerformancePartialPairStore(directory: partialDirectory)
        for index in 0..<30 {
            let order: PairOrder = index < 15 ? .baselineFirst : .candidateFirst
            _ = try store.store(PerformancePartialPair(
                fixtureProfile: .standard12,
                pairIndex: index,
                order: order,
                baseline: makeResult(variant: .baseline, pairIndex: index, order: order),
                candidate: makeResult(variant: .candidate, pairIndex: index, order: order)
            ))
        }
        let swappedURL = partialDirectory.appendingPathComponent("4.json")
        let targetURL = root.appendingPathComponent("swapped-target.json")
        try Data(contentsOf: swappedURL).write(to: targetURL)
        try FileManager.default.removeItem(at: swappedURL)
        try FileManager.default.createSymbolicLink(at: swappedURL, withDestinationURL: targetURL)
        var diagnostic = ""
        XCTAssertThrowsError(try store.loadAll(configuration: .standard12)) { error in
            diagnostic = String(describing: error)
        }
        XCTAssertTrue(diagnostic.contains("regular file"), diagnostic)
    }

    func testCLIParsesExactTrialFinalizeAndComparePathContracts() throws {
        let root = try temporaryDirectory("pointer-cli-grammar")
        defer { try? FileManager.default.removeItem(at: root) }
        let performanceRoot = root.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance", isDirectory: true)
        let profileRoot = performanceRoot.appendingPathComponent("standard12", isDirectory: true)
        let buildRoot = root.appendingPathComponent("build/standard12", isDirectory: true)
        let trialArgs = [
            "--quality-performance", "--format", "json", "--operation", "trial",
            "--fixture-profile", "standard12", "--variant", "baseline",
            "--pair-order", "baselineFirst", "--pair-index", "0",
            "--source-commit-sha", PerformanceFixtures.baselineCommit,
            "--run-provenance-file", buildRoot.appendingPathComponent("baseline/provenance.json").path,
            "--pair-eligibility-file", profileRoot.appendingPathComponent("comparisons/pair-eligibility.json").path,
            "--partial-pair-directory", buildRoot.appendingPathComponent("pair-execution/partial").path
        ]
        guard case let .trial(trial) = try PerformanceCLI.parse(arguments: trialArgs, outputDirectory: root) else {
            return XCTFail("expected trial invocation")
        }
        XCTAssertEqual(trial.pairIndex, 0)
        XCTAssertEqual(trial.sampleIndex, 0)
        XCTAssertThrowsError(try PerformanceCLI.parse(arguments: trialArgs + ["--trial-request", root.appendingPathComponent("request.json").path], outputDirectory: root))

        let output = profileRoot
        let finalizeArgs = [
            "--quality-performance", "--format", "json", "--operation", "finalize",
            "--fixture-profile", "standard12",
            "--partial-pair-directory", buildRoot.appendingPathComponent("pair-execution/partial").path,
            "--baseline-run-provenance-file", buildRoot.appendingPathComponent("baseline/provenance.json").path,
            "--candidate-run-provenance-file", buildRoot.appendingPathComponent("candidate/provenance.json").path,
            "--pair-eligibility-file", profileRoot.appendingPathComponent("comparisons/pair-eligibility.json").path,
            "--output-dir", output.path
        ]
        guard case let .finalize(finalize) = try PerformanceCLI.parse(arguments: finalizeArgs, outputDirectory: output) else {
            return XCTFail("expected finalize invocation")
        }
        XCTAssertEqual(finalize.outputDirectory.path, output.path)

        let comparePerformanceRoot = root.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance")
        let compareProfileRoot = comparePerformanceRoot.appendingPathComponent("standard12")
        let compareOutput = compareProfileRoot.appendingPathComponent("comparisons")
        let compareArgs = [
            "--quality-compare", "--format", "json", "--fixture-profile", "standard12",
            "--baseline-report", compareProfileRoot.appendingPathComponent("measurements/baseline.json").path,
            "--candidate-report", compareProfileRoot.appendingPathComponent("measurements/candidate.json").path,
            "--pair-eligibility-file", compareProfileRoot.appendingPathComponent("comparisons/pair-eligibility.json").path,
            "--pair-execution-artifact", compareProfileRoot.appendingPathComponent("pair-execution/pair-execution.json").path,
            "--manual-evidence-dir", compareProfileRoot.appendingPathComponent("comparisons/manual").path,
            "--output-dir", compareOutput.path
        ]
        guard case let .compare(compare) = try PerformanceCLI.parse(arguments: compareArgs, outputDirectory: compareOutput) else {
            return XCTFail("expected compare invocation")
        }
        XCTAssertEqual(compare.profile, .standard12)
        XCTAssertThrowsError(try PerformanceCLI.parse(arguments: compareArgs.map { $0.replacingOccurrences(of: "standard12", with: "dense1000") }, outputDirectory: compareOutput))
    }

    func testCLIRejectsRawMalformedURLValuesForEveryQualityCommand() throws {
        let repoRoot = try temporaryDirectory("pointer-cli-raw-paths")
        defer { try? FileManager.default.removeItem(at: repoRoot) }
        let performanceRoot = repoRoot.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance", isDirectory: true)
        let profileRoot = performanceRoot.appendingPathComponent("standard12", isDirectory: true)
        let buildRoot = repoRoot.appendingPathComponent("build/standard12", isDirectory: true)
        let trialArgs = [
            "--quality-performance", "--format", "json", "--operation", "trial",
            "--fixture-profile", "standard12", "--variant", "baseline",
            "--pair-order", "baselineFirst", "--pair-index", "0",
            "--source-commit-sha", PerformanceFixtures.baselineCommit,
            "--run-provenance-file", buildRoot.appendingPathComponent("baseline/provenance.json").path,
            "--pair-eligibility-file", profileRoot.appendingPathComponent("comparisons/pair-eligibility.json").path,
            "--external-trial-sidecar", profileRoot.appendingPathComponent("external/trials/baseline/0.json").path,
            "--partial-pair-directory", buildRoot.appendingPathComponent("pair-execution/partial").path
        ]
        let finalizeArgs = [
            "--quality-performance", "--format", "json", "--operation", "finalize",
            "--fixture-profile", "standard12",
            "--partial-pair-directory", buildRoot.appendingPathComponent("pair-execution/partial").path,
            "--baseline-run-provenance-file", buildRoot.appendingPathComponent("baseline/provenance.json").path,
            "--candidate-run-provenance-file", buildRoot.appendingPathComponent("candidate/provenance.json").path,
            "--pair-eligibility-file", profileRoot.appendingPathComponent("comparisons/pair-eligibility.json").path,
            "--baseline-external-aggregate-sidecar", profileRoot.appendingPathComponent("external/aggregate/baseline.json").path,
            "--candidate-external-aggregate-sidecar", profileRoot.appendingPathComponent("external/aggregate/candidate.json").path,
            "--output-dir", profileRoot.path
        ]
        let comparisonOutput = profileRoot.appendingPathComponent("comparisons", isDirectory: true)
        let compareArgs = [
            "--quality-compare", "--format", "json", "--fixture-profile", "standard12",
            "--baseline-report", profileRoot.appendingPathComponent("measurements/baseline.json").path,
            "--candidate-report", profileRoot.appendingPathComponent("measurements/candidate.json").path,
            "--pair-eligibility-file", profileRoot.appendingPathComponent("comparisons/pair-eligibility.json").path,
            "--pair-execution-artifact", profileRoot.appendingPathComponent("pair-execution/pair-execution.json").path,
            "--manual-evidence-dir", profileRoot.appendingPathComponent("comparisons/manual", isDirectory: true).path,
            "--output-dir", comparisonOutput.path
        ]
        let campaignArgs = [
            "--quality-campaign-complete", "--format", "json",
            "--standard12-comparison", profileRoot.appendingPathComponent("comparisons/paired-comparison.json").path,
            "--dense1000-comparison", performanceRoot.appendingPathComponent("dense1000/comparisons/paired-comparison.json").path,
            "--output-file", performanceRoot.appendingPathComponent("campaign-completion/manifest.json").path
        ]
        let commandCases: [([String], URL, String)] = [
            (trialArgs, repoRoot, "--run-provenance-file"),
            (trialArgs, repoRoot, "--pair-eligibility-file"),
            (trialArgs, repoRoot, "--external-trial-sidecar"),
            (trialArgs, repoRoot, "--partial-pair-directory"),
            (finalizeArgs, profileRoot, "--partial-pair-directory"),
            (finalizeArgs, profileRoot, "--baseline-run-provenance-file"),
            (finalizeArgs, profileRoot, "--candidate-run-provenance-file"),
            (finalizeArgs, profileRoot, "--pair-eligibility-file"),
            (finalizeArgs, profileRoot, "--baseline-external-aggregate-sidecar"),
            (finalizeArgs, profileRoot, "--candidate-external-aggregate-sidecar"),
            (finalizeArgs, profileRoot, "--output-dir"),
            (compareArgs, comparisonOutput, "--baseline-report"),
            (compareArgs, comparisonOutput, "--candidate-report"),
            (compareArgs, comparisonOutput, "--pair-eligibility-file"),
            (compareArgs, comparisonOutput, "--pair-execution-artifact"),
            (compareArgs, comparisonOutput, "--manual-evidence-dir"),
            (compareArgs, comparisonOutput, "--output-dir"),
            (campaignArgs, repoRoot, "--standard12-comparison"),
            (campaignArgs, repoRoot, "--dense1000-comparison"),
            (campaignArgs, repoRoot, "--output-file")
        ]
        func replacing(_ args: [String], flag: String, value: String) -> [String] {
            guard let index = args.firstIndex(of: flag), args.indices.contains(args.index(after: index)) else {
                return args
            }
            var replaced = args
            replaced[args.index(after: index)] = value
            return replaced
        }
        for malformed in ["foo/../bar", "./", "/x/../y"] {
            for (args, output, flag) in commandCases {
                XCTAssertThrowsError(try PerformanceCLI.parse(arguments: replacing(args, flag: flag, value: malformed), outputDirectory: output), "expected raw path rejection for \(flag) and \(malformed)")
            }
        }
        let executor = RecordingTrialExecutor()
        PerformanceCLI.trialExecutor = executor
        defer { PerformanceCLI.trialExecutor = nil }
        XCTAssertThrowsError(try PerformanceCLI.run(arguments: replacing(trialArgs, flag: "--partial-pair-directory", value: "foo/../bar"), outputDirectory: repoRoot))
        XCTAssertEqual(executor.sampleCount, 0)
    }

    func testCLIRejectsCrossRootAndProfileScopedPathSplices() throws {
        let repoRoot = try temporaryDirectory("pointer-cli-path-context")
        defer { try? FileManager.default.removeItem(at: repoRoot) }
        let foreignRoot = try temporaryDirectory("pointer-cli-foreign-context")
        defer { try? FileManager.default.removeItem(at: foreignRoot) }
        let performanceRoot = repoRoot.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance", isDirectory: true)
        let profileRoot = performanceRoot.appendingPathComponent("standard12", isDirectory: true)
        let buildRoot = repoRoot.appendingPathComponent("build/standard12", isDirectory: true)
        let foreignPerformanceRoot = foreignRoot.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance", isDirectory: true)
        let foreignProfileRoot = foreignPerformanceRoot.appendingPathComponent("standard12", isDirectory: true)
        let foreignBuildRoot = foreignRoot.appendingPathComponent("build/standard12", isDirectory: true)
        let trialArgs = [
            "--quality-performance", "--format", "json", "--operation", "trial",
            "--fixture-profile", "standard12", "--variant", "baseline",
            "--pair-order", "baselineFirst", "--pair-index", "0",
            "--source-commit-sha", PerformanceFixtures.baselineCommit,
            "--run-provenance-file", buildRoot.appendingPathComponent("baseline/provenance.json").path,
            "--pair-eligibility-file", profileRoot.appendingPathComponent("comparisons/pair-eligibility.json").path,
            "--external-trial-sidecar", profileRoot.appendingPathComponent("external/trials/baseline/0.json").path,
            "--partial-pair-directory", buildRoot.appendingPathComponent("pair-execution/partial").path
        ]
        let finalizeArgs = [
            "--quality-performance", "--format", "json", "--operation", "finalize",
            "--fixture-profile", "standard12",
            "--partial-pair-directory", buildRoot.appendingPathComponent("pair-execution/partial").path,
            "--baseline-run-provenance-file", buildRoot.appendingPathComponent("baseline/provenance.json").path,
            "--candidate-run-provenance-file", buildRoot.appendingPathComponent("candidate/provenance.json").path,
            "--pair-eligibility-file", profileRoot.appendingPathComponent("comparisons/pair-eligibility.json").path,
            "--baseline-external-aggregate-sidecar", profileRoot.appendingPathComponent("external/aggregate/baseline.json").path,
            "--candidate-external-aggregate-sidecar", profileRoot.appendingPathComponent("external/aggregate/candidate.json").path,
            "--output-dir", profileRoot.path
        ]
        let compareOutput = profileRoot.appendingPathComponent("comparisons", isDirectory: true)
        let compareArgs = [
            "--quality-compare", "--format", "json", "--fixture-profile", "standard12",
            "--baseline-report", profileRoot.appendingPathComponent("measurements/baseline.json").path,
            "--candidate-report", profileRoot.appendingPathComponent("measurements/candidate.json").path,
            "--pair-eligibility-file", profileRoot.appendingPathComponent("comparisons/pair-eligibility.json").path,
            "--pair-execution-artifact", profileRoot.appendingPathComponent("pair-execution/pair-execution.json").path,
            "--manual-evidence-dir", compareOutput.appendingPathComponent("manual", isDirectory: true).path,
            "--output-dir", compareOutput.path
        ]
        let campaignArgs = [
            "--quality-campaign-complete", "--format", "json",
            "--standard12-comparison", profileRoot.appendingPathComponent("comparisons/paired-comparison.json").path,
            "--dense1000-comparison", performanceRoot.appendingPathComponent("dense1000/comparisons/paired-comparison.json").path,
            "--output-file", performanceRoot.appendingPathComponent("campaign-completion/manifest.json").path
        ]
        func replacing(_ args: [String], flag: String, value: String) -> [String] {
            guard let index = args.firstIndex(of: flag), args.indices.contains(args.index(after: index)) else { return args }
            var replaced = args
            replaced[args.index(after: index)] = value
            return replaced
        }
        let contextCases: [([String], URL, String, String)] = [
            (trialArgs, repoRoot, "--run-provenance-file", foreignBuildRoot.appendingPathComponent("baseline/provenance.json").path),
            (trialArgs, repoRoot, "--pair-eligibility-file", foreignProfileRoot.appendingPathComponent("comparisons/pair-eligibility.json").path),
            (trialArgs, repoRoot, "--external-trial-sidecar", foreignProfileRoot.appendingPathComponent("external/trial.json").path),
            (trialArgs, repoRoot, "--partial-pair-directory", foreignBuildRoot.appendingPathComponent("pair-execution/partial").path),
            (trialArgs, repoRoot, "--partial-pair-directory", repoRoot.appendingPathComponent("build/other/standard12/pair-execution/partial").path),
            (finalizeArgs, profileRoot, "--baseline-run-provenance-file", foreignBuildRoot.appendingPathComponent("baseline/provenance.json").path),
            (finalizeArgs, profileRoot, "--candidate-run-provenance-file", foreignBuildRoot.appendingPathComponent("candidate/provenance.json").path),
            (finalizeArgs, profileRoot, "--pair-eligibility-file", foreignProfileRoot.appendingPathComponent("comparisons/pair-eligibility.json").path),
            (finalizeArgs, profileRoot, "--baseline-external-aggregate-sidecar", foreignProfileRoot.appendingPathComponent("external/baseline.json").path),
            (finalizeArgs, profileRoot, "--output-dir", foreignProfileRoot.path),
            (finalizeArgs, profileRoot, "--output-dir", repoRoot.appendingPathComponent("evidence/other/standard12").path),
            (compareArgs, compareOutput, "--baseline-report", foreignProfileRoot.appendingPathComponent("measurements/baseline.json").path),
            (compareArgs, compareOutput, "--candidate-report", foreignProfileRoot.appendingPathComponent("measurements/candidate.json").path),
            (compareArgs, compareOutput, "--pair-eligibility-file", foreignProfileRoot.appendingPathComponent("comparisons/pair-eligibility.json").path),
            (compareArgs, compareOutput, "--pair-execution-artifact", foreignProfileRoot.appendingPathComponent("pair-execution/pair-execution.json").path),
            (compareArgs, compareOutput, "--manual-evidence-dir", foreignProfileRoot.appendingPathComponent("comparisons/manual", isDirectory: true).path),
            (compareArgs, compareOutput, "--output-dir", foreignProfileRoot.appendingPathComponent("comparisons", isDirectory: true).path),
            (compareArgs, compareOutput, "--manual-evidence-dir", repoRoot.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance/other/standard12/comparisons/manual", isDirectory: true).path),
            (campaignArgs, repoRoot, "--standard12-comparison", foreignProfileRoot.appendingPathComponent("comparisons/paired-comparison.json").path),
            (campaignArgs, repoRoot, "--dense1000-comparison", foreignPerformanceRoot.appendingPathComponent("dense1000/comparisons/paired-comparison.json").path),
            (campaignArgs, repoRoot, "--output-file", foreignPerformanceRoot.appendingPathComponent("campaign-completion/manifest.json").path)
        ]
        for (args, output, flag, value) in contextCases {
            XCTAssertThrowsError(try PerformanceCLI.parse(arguments: replacing(args, flag: flag, value: value), outputDirectory: output), "expected context rejection for \(flag)")
        }
    }

    func testCampaignManifestBindsExactReportHashesAndRejectsMutationOrSwap() throws {
        let root = try temporaryDirectory("pointer-manifest")
        defer { try? FileManager.default.removeItem(at: root) }
        let performanceRoot = campaignPerformanceRoot(root)
        let standardURL = performanceRoot.appendingPathComponent("standard12/comparisons/paired-comparison.json")
        let denseURL = performanceRoot.appendingPathComponent("dense1000/comparisons/paired-comparison.json")
        try FileManager.default.createDirectory(at: standardURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: denseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let standardData = try PerformanceCanonicalJSON.data(for: PerformanceFixtures.comparison())
        let denseData = try denseComparisonData()
        try standardData.write(to: standardURL)
        try denseData.write(to: denseURL)
        let manifestURL = performanceRoot.appendingPathComponent("campaign-completion/manifest.json")
        let manifest = try PerformanceCampaignCompletion.writeManifest(standard12ComparisonURL: standardURL, dense1000ComparisonURL: denseURL, outputURL: manifestURL)
        XCTAssertEqual(manifest.standard12ComparisonSHA256, sha256(standardData))
        XCTAssertEqual(manifest.dense1000ComparisonSHA256, sha256(denseData))
        XCTAssertNoThrow(try PerformanceCampaignCompletion.validate(manifest: manifest, repoRoot: root))
        XCTAssertEqual(try PerformanceCampaignCompletion.load(from: manifestURL), manifest)
        var mutated = manifest
        mutated = PerformanceCampaignCompletionManifest(schemaVersion: 1, standard12ComparisonPath: manifest.standard12ComparisonPath, standard12ComparisonSHA256: String(repeating: "0", count: 64), dense1000ComparisonPath: manifest.dense1000ComparisonPath, dense1000ComparisonSHA256: manifest.dense1000ComparisonSHA256)
        XCTAssertThrowsError(try PerformanceCampaignCompletion.validate(manifest: mutated, repoRoot: root))
        let swapped = PerformanceCampaignCompletionManifest(schemaVersion: 1, standard12ComparisonPath: manifest.dense1000ComparisonPath, standard12ComparisonSHA256: manifest.dense1000ComparisonSHA256, dense1000ComparisonPath: manifest.standard12ComparisonPath, dense1000ComparisonSHA256: manifest.standard12ComparisonSHA256)
        XCTAssertThrowsError(try PerformanceCampaignCompletion.validate(manifest: swapped, repoRoot: root))
    }

    func testCampaignManifestUsesCanonicalRepoRelativePathsAndRejectsArbitraryRoots() throws {
        let repoRoot = try temporaryDirectory("pointer-campaign-repo")
        defer { try? FileManager.default.removeItem(at: repoRoot) }
        let performanceRoot = campaignPerformanceRoot(repoRoot)
        let standardURL = performanceRoot.appendingPathComponent("standard12/comparisons/paired-comparison.json")
        let denseURL = performanceRoot.appendingPathComponent("dense1000/comparisons/paired-comparison.json")
        let outputURL = performanceRoot.appendingPathComponent("campaign-completion/manifest.json")
        try FileManager.default.createDirectory(at: standardURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: denseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PerformanceCanonicalJSON.data(for: PerformanceFixtures.comparison()).write(to: standardURL)
        try denseComparisonData().write(to: denseURL)
        let manifest = try PerformanceCampaignCompletion.writeManifest(standard12ComparisonURL: standardURL, dense1000ComparisonURL: denseURL, outputURL: outputURL)
        XCTAssertEqual(manifest.standard12ComparisonPath, ".codex/sdd/reports/quality-campaign/performance/standard12/comparisons/paired-comparison.json")
        XCTAssertEqual(manifest.dense1000ComparisonPath, ".codex/sdd/reports/quality-campaign/performance/dense1000/comparisons/paired-comparison.json")
        XCTAssertEqual(try PerformanceCampaignCompletion.load(from: outputURL), manifest)
        let traversalOutputURL = URL(fileURLWithPath: repoRoot.path + "/alias/../.codex/sdd/reports/quality-campaign/performance/campaign-completion/manifest.json")
        XCTAssertThrowsError(try PerformanceCampaignCompletion.load(from: traversalOutputURL))
        XCTAssertThrowsError(try PerformanceCampaignCompletion.writeManifest(standard12ComparisonURL: standardURL, dense1000ComparisonURL: denseURL, outputURL: traversalOutputURL))
        let aliasURL = repoRoot.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: repoRoot.appendingPathComponent(".codex", isDirectory: true))
        let symlinkedOutputURL = aliasURL.appendingPathComponent("sdd/reports/quality-campaign/performance/campaign-completion/manifest.json")
        XCTAssertThrowsError(try PerformanceCampaignCompletion.load(from: symlinkedOutputURL))
        XCTAssertThrowsError(try PerformanceCampaignCompletion.writeManifest(standard12ComparisonURL: standardURL, dense1000ComparisonURL: denseURL, outputURL: symlinkedOutputURL))
        let absolutePathManifest = PerformanceCampaignCompletionManifest(
            standard12ComparisonPath: standardURL.path,
            standard12ComparisonSHA256: manifest.standard12ComparisonSHA256,
            dense1000ComparisonPath: manifest.dense1000ComparisonPath,
            dense1000ComparisonSHA256: manifest.dense1000ComparisonSHA256
        )
        try PerformanceCanonicalJSON.data(for: absolutePathManifest).write(to: outputURL)
        XCTAssertThrowsError(try PerformanceCampaignCompletion.load(from: outputURL))

        let arbitraryRoot = try temporaryDirectory("pointer-campaign-arbitrary")
        defer { try? FileManager.default.removeItem(at: arbitraryRoot) }
        let arbitraryStandardURL = arbitraryRoot.appendingPathComponent("standard12/comparisons/paired-comparison.json")
        let arbitraryDenseURL = arbitraryRoot.appendingPathComponent("dense1000/comparisons/paired-comparison.json")
        let arbitraryOutputURL = arbitraryRoot.appendingPathComponent("campaign-completion/manifest.json")
        try FileManager.default.createDirectory(at: arbitraryStandardURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: arbitraryDenseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PerformanceCanonicalJSON.data(for: PerformanceFixtures.comparison()).write(to: arbitraryStandardURL)
        try denseComparisonData().write(to: arbitraryDenseURL)
        XCTAssertThrowsError(try PerformanceCampaignCompletion.writeManifest(standard12ComparisonURL: arbitraryStandardURL, dense1000ComparisonURL: arbitraryDenseURL, outputURL: arbitraryOutputURL))

        for malformed in [
            repoRoot.path + "/.codex/sdd/reports/quality-campaign/performance/./campaign-completion/manifest.json",
            repoRoot.path + "//.codex/sdd/reports/quality-campaign/performance/campaign-completion/manifest.json",
            repoRoot.path + "/.codex/sdd/reports/quality-campaign/performance/campaign-completion/manifest.json/"
        ] {
            let malformedURL = URL(fileURLWithPath: malformed)
            XCTAssertThrowsError(try PerformanceCampaignCompletion.load(from: malformedURL), malformed)
            XCTAssertThrowsError(try PerformanceCampaignCompletion.writeManifest(standard12ComparisonURL: standardURL, dense1000ComparisonURL: denseURL, outputURL: malformedURL), malformed)
        }
    }

    func testCampaignManifestRejectsCrossProfileIdentitySplice() throws {
        let root = try temporaryDirectory("pointer-manifest-identity")
        defer { try? FileManager.default.removeItem(at: root) }
        let performanceRoot = campaignPerformanceRoot(root)
        let standardURL = performanceRoot.appendingPathComponent("standard12/comparisons/paired-comparison.json")
        let denseURL = performanceRoot.appendingPathComponent("dense1000/comparisons/paired-comparison.json")
        try FileManager.default.createDirectory(at: standardURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: denseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let standardData = try PerformanceCanonicalJSON.data(for: PerformanceFixtures.comparison())
        let denseData = try denseComparisonData(hostMachine: "other-machine")
        try standardData.write(to: standardURL)
        try denseData.write(to: denseURL)
        let manifestURL = performanceRoot.appendingPathComponent("campaign-completion/manifest.json")
        XCTAssertThrowsError(try PerformanceCampaignCompletion.writeManifest(standard12ComparisonURL: standardURL, dense1000ComparisonURL: denseURL, outputURL: manifestURL))
    }

    func testCampaignCompletionCLIUsesExactAcceptedComparisonBindingsAndIsIdempotent() throws {
        let root = try temporaryDirectory("pointer-campaign-cli")
        defer { try? FileManager.default.removeItem(at: root) }
        let performanceRoot = campaignPerformanceRoot(root)
        let standardURL = performanceRoot.appendingPathComponent("standard12/comparisons/paired-comparison.json")
        let denseURL = performanceRoot.appendingPathComponent("dense1000/comparisons/paired-comparison.json")
        try FileManager.default.createDirectory(at: standardURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: denseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let standardData = try PerformanceCanonicalJSON.data(for: PerformanceFixtures.comparison())
        let denseData = try denseComparisonData()
        try standardData.write(to: standardURL)
        try denseData.write(to: denseURL)
        let outputURL = performanceRoot.appendingPathComponent("campaign-completion/manifest.json")
        let args = [
            "--quality-campaign-complete", "--format", "json",
            "--standard12-comparison", standardURL.path,
            "--dense1000-comparison", denseURL.path,
            "--output-file", outputURL.path
        ]
        guard case let .campaignComplete(invocation) = try PerformanceCLI.parse(arguments: args, outputDirectory: root) else {
            return XCTFail("expected campaign completion invocation")
        }
        XCTAssertEqual(invocation.outputURL, outputURL)
        try PerformanceCLI.run(arguments: args, outputDirectory: root)
        let firstBytes = try Data(contentsOf: outputURL)
        try PerformanceCLI.run(arguments: args, outputDirectory: root)
        XCTAssertEqual(try Data(contentsOf: outputURL), firstBytes)
        XCTAssertNoThrow(try PerformanceCampaignCompletion.load(from: outputURL))
    }

    func testCampaignCompletionCLIAcceptsComparisonsWrittenByRealWriterUnderSharedRoot() throws {
        let root = try temporaryDirectory("pointer-campaign-real-writer")
        defer { try? FileManager.default.removeItem(at: root) }
        let standardURL = try writeRealComparison(profile: .standard12, root: root)
        let denseURL = try writeRealComparison(profile: .dense1000, root: root)
        let outputURL = campaignPerformanceRoot(root).appendingPathComponent("campaign-completion/manifest.json")
        let args = [
            "--quality-campaign-complete", "--format", "json",
            "--standard12-comparison", standardURL.path,
            "--dense1000-comparison", denseURL.path,
            "--output-file", outputURL.path
        ]
        try PerformanceCLI.run(arguments: args, outputDirectory: root)
        let manifest = try PerformanceCampaignCompletion.load(from: outputURL)
        XCTAssertEqual(manifest.standard12ComparisonPath, ".codex/sdd/reports/quality-campaign/performance/standard12/comparisons/paired-comparison.json")
        XCTAssertEqual(manifest.dense1000ComparisonPath, ".codex/sdd/reports/quality-campaign/performance/dense1000/comparisons/paired-comparison.json")
        let standardReport = try PerformanceCanonicalJSON.decoded(PerformanceComparisonReport.self, from: Data(contentsOf: standardURL))
        XCTAssertEqual(try Data(contentsOf: standardURL), try PerformanceCanonicalJSON.data(for: standardReport))
        let denseReport = try PerformanceCanonicalJSON.decoded(PerformanceComparisonReport.self, from: Data(contentsOf: denseURL))
        XCTAssertEqual(try Data(contentsOf: denseURL), try PerformanceCanonicalJSON.data(for: denseReport))
    }

    func testCampaignCompletionRejectsDifferentPhysicalRootsAndIgnoredOutputDirectory() throws {
        let root = try temporaryDirectory("pointer-campaign-root")
        defer { try? FileManager.default.removeItem(at: root) }
        let foreignRoot = try temporaryDirectory("pointer-campaign-foreign-root")
        defer { try? FileManager.default.removeItem(at: foreignRoot) }
        let standardURL = try writeRealComparison(profile: .standard12, root: root)
        let denseURL = try writeRealComparison(profile: .dense1000, root: foreignRoot)
        let manifestURL = campaignPerformanceRoot(root).appendingPathComponent("campaign-completion/manifest.json")
        XCTAssertThrowsError(try PerformanceCampaignCompletion.writeManifest(standard12ComparisonURL: standardURL, dense1000ComparisonURL: denseURL, outputURL: manifestURL))

        let localDenseURL = try writeRealComparison(profile: .dense1000, root: root)
        let args = [
            "--quality-campaign-complete", "--format", "json",
            "--standard12-comparison", standardURL.path,
            "--dense1000-comparison", localDenseURL.path,
            "--output-file", campaignPerformanceRoot(root).appendingPathComponent("campaign-completion/manifest.json").path
        ]
        let ignoredOutputDirectory = try temporaryDirectory("pointer-campaign-wrong-output")
        defer { try? FileManager.default.removeItem(at: ignoredOutputDirectory) }
        XCTAssertThrowsError(try PerformanceCLI.run(arguments: args, outputDirectory: ignoredOutputDirectory))
    }

    func testCampaignCompletionRejectsCrossProfileEnvironmentSplices() throws {
        let root = try temporaryDirectory("pointer-campaign-lineage")
        defer { try? FileManager.default.removeItem(at: root) }
        let performanceRoot = campaignPerformanceRoot(root)
        let standardURL = performanceRoot.appendingPathComponent("standard12/comparisons/paired-comparison.json")
        let denseURL = performanceRoot.appendingPathComponent("dense1000/comparisons/paired-comparison.json")
        try FileManager.default.createDirectory(at: standardURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: denseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let standardData = try PerformanceCanonicalJSON.data(for: PerformanceFixtures.comparison())
        let standardReport = try PerformanceCanonicalJSON.decoded(PerformanceComparisonReport.self, from: standardData)
        XCTAssertNoThrow(try standardReport.validateCompletion())
        try standardData.write(to: standardURL)
        func mutateBuildField(_ object: inout [String: Any], field: String, value: String) {
            for key in ["baselineBuildProvenance", "candidateBuildProvenance"] {
                var build = object[key] as! [String: Any]
                build[field] = value
                object[key] = build
            }
            for key in ["baselineRunProvenance", "candidateRunProvenance"] {
                var run = object[key] as! [String: Any]
                var build = run["build"] as! [String: Any]
                build[field] = value
                run["build"] = build
                object[key] = run
            }
        }

        func mutateMeasurementField(_ object: inout [String: Any], field: String, value: String) {
            for key in ["baselineMeasurementIdentity", "candidateMeasurementIdentity"] {
                var identity = object[key] as! [String: Any]
                identity[field] = value
                object[key] = identity
            }
        }

        let mutations: [(String, (inout [String: Any]) -> Void)] = [
            ("source manifest", { object in
                let replacement = String(repeating: "8", count: 64)
                mutateBuildField(&object, field: "sourceManifestSHA256", value: replacement)
                var eligibility = object["pairEligibility"] as! [String: Any]
                var foundation = eligibility["foundationProvenance"] as! [String: Any]
                foundation["fullSourceManifestSHA256"] = replacement
                eligibility["foundationProvenance"] = foundation
                object["pairEligibility"] = eligibility
            }),
            ("executable", { object in
                mutateBuildField(&object, field: "executableSHA256", value: String(repeating: "8", count: 64))
            }),
            ("bundle", { object in
                mutateBuildField(&object, field: "bundleManifestSHA256", value: String(repeating: "8", count: 64))
            }),
            ("xcode", { object in
                mutateMeasurementField(&object, field: "xcodeVersion", value: "17.0")
            }),
            ("power", { object in
                mutateMeasurementField(&object, field: "powerState", value: "battery")
            }),
            ("macOS", { object in
                mutateMeasurementField(&object, field: "macOSVersion", value: "15.0")
            }),
            ("display", { object in
                mutateMeasurementField(&object, field: "displayState", value: "two-displays")
                for key in ["baselineRunProvenance", "candidateRunProvenance"] {
                    var run = object[key] as! [String: Any]
                    var host = run["host"] as! [String: Any]
                    host["connectedDisplayUUIDs"] = ["other-display"]
                    run["host"] = host
                    object[key] = run
                }
            })
        ]
        for (label, mutation) in mutations {
            let denseData = try denseComparisonData(mutation: mutation)
            let denseReport = try PerformanceCanonicalJSON.decoded(PerformanceComparisonReport.self, from: denseData)
            XCTAssertNoThrow(try denseReport.validateCompletion(), label)
            try denseData.write(to: denseURL)
            XCTAssertThrowsError(try PerformanceCampaignCompletion.writeManifest(
                standard12ComparisonURL: standardURL,
                dense1000ComparisonURL: denseURL,
                outputURL: performanceRoot.appendingPathComponent("campaign-completion/manifest.json")
            ), label)
        }
    }

    private func makeResult(
        variant: PerformanceVariant,
        pairIndex: Int,
        order: PairOrder,
        values: [Double] = Array(1...11).map(Double.init),
        modelChecksum: String = "checksum",
        runProvenanceSHA256: String = String(repeating: "0", count: 64),
        pairEligibilitySHA256: String = String(repeating: "0", count: 64),
        sourceIdentity: SourceIdentity? = nil,
        request: PerformanceTrialRequest? = nil,
        samples: [PerformanceTrialMetricSample]? = nil
    ) -> PerformanceTrialResult {
        let request = request ?? PerformanceTrialRequest(variant: variant, fixtureProfile: .standard12, pairIndex: pairIndex, order: order, sampleIndex: pairIndex)
        let samples = samples ?? PerformanceMetricID.allCases.enumerated().map { index, metricID in
            PerformanceTrialMetricSample(metricID: metricID, unit: metricID.canonicalUnit, status: .measured, value: values[index], diagnostic: nil)
        }
        let pairStart = pairIndex * 10
        let variantOffset: Int
        switch (order, variant) {
        case (.baselineFirst, .baseline), (.candidateFirst, .candidate):
            variantOffset = 1
        case (.baselineFirst, .candidate), (.candidateFirst, .baseline):
            variantOffset = 3
        }
        let start = timestamp(pairStart + variantOffset)
        let end = timestamp(pairStart + variantOffset + 1)
        return PerformanceTrialResult(schemaVersion: 1, request: request, sourceIdentity: sourceIdentity ?? (variant == .baseline ? PerformanceFixtures.baselineBuild.sourceIdentity : PerformanceFixtures.build.sourceIdentity), runProvenanceSHA256: runProvenanceSHA256, pairEligibilitySHA256: pairEligibilitySHA256, startedAtUTC: start, endedAtUTC: end, warmupCountExecuted: 5, samples: samples, modelEvidence: PerformanceModelTrialEvidence(publicationCount: 2, modelChecksum: modelChecksum, finalStateValid: true), rendererEvidence: PerformanceRendererTrialEvidence(frameCount: 1, missedFrameCount: 0, instrumentationStatus: "fixture", semanticPass: true))
    }

    private func metricValues(offset: Double) -> [Double] {
        Array(1...11).map { Double($0) + offset }
    }

    private func metricSamples(status: MeasurementStatus, failedMetric: PerformanceMetricID? = nil) -> [PerformanceTrialMetricSample] {
        PerformanceMetricID.allCases.enumerated().map { index, metricID in
            let sampleStatus: MeasurementStatus = metricID == failedMetric ? .failed : status
            if sampleStatus == .measured {
                return PerformanceTrialMetricSample(metricID: metricID, unit: metricID.canonicalUnit, status: .measured, value: Double(index + 1), diagnostic: nil)
            }
            return PerformanceTrialMetricSample(metricID: metricID, unit: metricID.canonicalUnit, status: sampleStatus, value: nil, diagnostic: "fixture-\(metricID.rawValue)-\(sampleStatus.rawValue)")
        }
    }

    private func timestamp(_ offset: Int) -> String {
        String(format: "2026-09-01T00:%02d:%02d.%03dZ", offset / 60, offset % 60, 100 + (offset % 800))
    }

    private func temporaryDirectory(_ name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func campaignPerformanceRoot(_ repoRoot: URL) -> URL {
        repoRoot.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance", isDirectory: true)
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func makeArtifact(baselineData: Data, candidateData: Data) -> PerformancePairExecutionArtifact {
        PerformancePairExecutionArtifact(
            baselineID: PerformanceFixtures.baselineCommit,
            candidateID: PerformanceFixtures.commit,
            baselineMeasurementReportSHA256: sha256(baselineData),
            candidateMeasurementReportSHA256: sha256(candidateData),
            records: PerformanceFixtures.executionArtifact.records
        )
    }

    private func denseComparisonData(hostMachine: String? = nil, mutation: ((inout [String: Any]) -> Void)? = nil) throws -> Data {
        let source = try JSONEncoder().encode(PerformanceFixtures.comparison())
        var object = try XCTUnwrap(try JSONSerialization.jsonObject(with: source) as? [String: Any])
        for key in ["baselineFixture", "candidateFixture"] {
            var fixture = try XCTUnwrap(object[key] as? [String: Any])
            fixture["identifier"] = PerformanceFixtureProfile.dense1000.identifier
            fixture["fixtureProfile"] = PerformanceFixtureProfile.dense1000.rawValue
            fixture["fixtureVersion"] = PerformanceFixtureProfile.dense1000.version
            fixture["markCount"] = PerformanceFixtureProfile.dense1000.markCount
            object[key] = fixture
        }
        for key in ["baselineRunProvenance", "candidateRunProvenance"] {
            var run = try XCTUnwrap(object[key] as? [String: Any])
            var configuration = try XCTUnwrap(run["configuration"] as? [String: Any])
            configuration["fixtureMarkCount"] = PerformanceFixtureProfile.dense1000.markCount
            configuration["fixtureProfile"] = PerformanceFixtureProfile.dense1000.rawValue
            configuration["fixtureVersion"] = PerformanceFixtureProfile.dense1000.version
            run["configuration"] = configuration
            if let hostMachine {
                var host = try XCTUnwrap(run["host"] as? [String: Any])
                host["machineIdentifier"] = hostMachine
                run["host"] = host
            }
            object[key] = run
        }
        if let hostMachine {
            var metrics = try XCTUnwrap(object["metrics"] as? [[String: Any]])
            for index in metrics.indices {
                guard var manualEvidence = metrics[index]["manualEvidence"] as? [String: Any],
                      var evidence = manualEvidence["evidence"] as? [String: Any]
                else { continue }
                for key in ["baseline", "candidate"] {
                    var variant = try XCTUnwrap(evidence[key] as? [String: Any])
                    variant["host"] = hostMachine
                    evidence[key] = variant
                }
                manualEvidence["evidence"] = evidence
                metrics[index]["manualEvidence"] = manualEvidence
            }
            object["metrics"] = metrics
        }
        mutation?(&object)
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return try PerformanceCanonicalJSON.data(for: JSONDecoder().decode(PerformanceComparisonReport.self, from: data))
    }

    private func writeRealComparison(profile: PerformanceFixtureProfile, root: URL) throws -> URL {
        let configuration = profile == .standard12 ? PerformanceConfiguration.standard12 : PerformanceConfiguration.dense1000
        let performanceRoot = campaignPerformanceRoot(root)
        let baseline: PerformanceMeasurementReport
        let candidate: PerformanceMeasurementReport
        if profile == .standard12 {
            baseline = PerformanceFixtures.baseline
            candidate = PerformanceFixtures.candidate
        } else {
            let denseFixture = FixtureIdentity(
                identifier: PerformanceFixtureProfile.dense1000.identifier,
                fixtureProfile: .dense1000,
                fixtureVersion: PerformanceFixtureProfile.dense1000.version,
                markCount: configuration.fixtureMarkCount,
                continuationSamples: configuration.samplesPerGesture,
                warmupCount: configuration.warmupCount,
                trialCount: configuration.trialCount,
                seed: PerformanceFixtures.fixture.seed
            )
            let denseBaselineRun = PerformanceRunProvenance(
                variant: "baseline",
                outputRoot: performanceRoot.appendingPathComponent("dense1000/baseline", isDirectory: true).path,
                sourceRef: PerformanceFixtures.baselineCommit,
                build: PerformanceFixtures.baselineBuild,
                host: PerformanceFixtures.host,
                recordedAtUTC: PerformanceFixtures.recordedAtUTC,
                configuration: configuration,
                foundationProvenancePath: PerformanceFixtures.baselineRun.foundationProvenancePath,
                foundation: PerformanceFixtures.foundation,
                harnessVersion: configuration.harnessVersion,
                buildContractVersion: configuration.buildContractVersion,
                acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
            )
            let denseCandidateRun = PerformanceRunProvenance(
                variant: "candidate",
                outputRoot: performanceRoot.appendingPathComponent("dense1000/candidate", isDirectory: true).path,
                sourceRef: PerformanceFixtures.commit,
                build: PerformanceFixtures.build,
                host: PerformanceFixtures.host,
                recordedAtUTC: PerformanceFixtures.recordedAtUTC,
                configuration: configuration,
                foundationProvenancePath: PerformanceFixtures.run.foundationProvenancePath,
                foundation: PerformanceFixtures.foundation,
                harnessVersion: configuration.harnessVersion,
                buildContractVersion: configuration.buildContractVersion,
                acceptedFoundationArtifactSHA256: PerformanceFixtures.foundationArtifact
            )
            baseline = PerformanceFixtures.report(identity: PerformanceFixtures.baselineIdentity, build: PerformanceFixtures.baselineBuild, run: denseBaselineRun, fixture: denseFixture)
            candidate = PerformanceFixtures.report(identity: PerformanceFixtures.identity, build: PerformanceFixtures.build, run: denseCandidateRun, fixture: denseFixture)
        }
        let baselineData = try PerformanceCanonicalJSON.data(for: baseline)
        let candidateData = try PerformanceCanonicalJSON.data(for: candidate)
        let baselineURL = performanceRoot.appendingPathComponent("\(profile.rawValue)/measurements/baseline.json")
        let candidateURL = performanceRoot.appendingPathComponent("\(profile.rawValue)/measurements/candidate.json")
        try FileManager.default.createDirectory(at: baselineURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try baselineData.write(to: baselineURL)
        try candidateData.write(to: candidateURL)
        let pairArtifact = makeArtifact(baselineData: baselineData, candidateData: candidateData)
        let pairData = try PerformancePairExecutionArtifact.canonicalData(for: pairArtifact)
        let pairURL = performanceRoot.appendingPathComponent("\(profile.rawValue)/pair-execution/pair-execution.json")
        try FileManager.default.createDirectory(at: pairURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try pairData.write(to: pairURL)
        let manualDirectory = performanceRoot.appendingPathComponent("\(profile.rawValue)/comparisons/manual", isDirectory: true)
        try FileManager.default.createDirectory(at: manualDirectory, withIntermediateDirectories: true)
        let eligibility = PerformancePairEligibility(
            baselineRoot: baseline.runProvenance.outputRoot,
            candidateRoot: candidate.runProvenance.outputRoot,
            baselineCommitSHA: baseline.runProvenance.sourceRef,
            candidateCommitSHA: candidate.runProvenance.sourceRef,
            foundationProvenance: PerformanceFixtures.foundationProvenance
        )
        let draft = try PerformanceComparisonHarness.compare(
            baseline: baseline,
            candidate: candidate,
            configuration: configuration,
            eligibility: eligibility,
            pairExecutionArtifact: pairArtifact,
            manualEvidenceDirectory: manualDirectory,
            pairExecutionArtifactSHA256: sha256(pairData)
        )
        let outputDirectory = performanceRoot.appendingPathComponent("\(profile.rawValue)/comparisons", isDirectory: true)
        _ = try PerformanceComparisonHarness.writeComparison(
            draft: draft,
            baselineURL: baselineURL,
            candidateURL: candidateURL,
            pairExecutionURL: pairURL,
            manualEvidenceDirectory: manualDirectory,
            outputDirectory: outputDirectory,
            configuration: configuration,
            eligibility: eligibility
        )
        return outputDirectory.appendingPathComponent("paired-comparison.json")
    }
}

@MainActor
private final class RecordingTrialExecutor: PerformanceTrialExecuting {
    private(set) var warmupCount = 0
    private(set) var sampleCount = 0

    func warmup(request: PerformanceTrialRequest) throws {
        warmupCount += 1
    }

    func sample(request: PerformanceTrialRequest) throws -> PerformanceTrialSample {
        sampleCount += 1
        let samples = PerformanceMetricID.allCases.enumerated().map { index, metricID in
            PerformanceTrialMetricSample(metricID: metricID, unit: metricID.canonicalUnit, status: .measured, value: Double(index + 1), diagnostic: nil)
        }
        return PerformanceTrialSample(
            samples: samples,
            modelEvidence: PerformanceModelTrialEvidence(publicationCount: 2, modelChecksum: "checksum", finalStateValid: true),
            rendererEvidence: PerformanceRendererTrialEvidence(frameCount: 1, missedFrameCount: 0, instrumentationStatus: "fixture", semanticPass: true)
        )
    }
}
