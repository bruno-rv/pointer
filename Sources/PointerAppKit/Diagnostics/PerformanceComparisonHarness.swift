import Foundation
import CryptoKit

@MainActor
public enum PerformanceComparisonHarness {
    internal static func preflight(
        baseline: PerformanceMeasurementReport,
        candidate: PerformanceMeasurementReport,
        configuration: PerformanceConfiguration,
        eligibility: PerformancePairEligibility
    ) throws {
        // Completion validation is deliberately before any comparison object or
        // output path is touched. A diagnostic report cannot be promoted into a
        // paired result by filling failed values with defaults.
        try baseline.validateCompletion()
        try candidate.validateCompletion()

        try require(configuration.isCanonical, "comparison requires a canonical configuration")
        try require(baseline.reportKind == .measurement && candidate.reportKind == .measurement, "comparison inputs must be measurement reports")
        try require(baseline.runProvenance.variant == "baseline", "baseline run variant must be baseline")
        try require(candidate.runProvenance.variant == "candidate", "candidate run variant must be candidate")
        try require(baseline.fixture == candidate.fixture, "baseline/candidate fixture mismatch")
        try require(baseline.host == candidate.host, "baseline/candidate host mismatch")
        try require(baseline.harnessVersion == candidate.harnessVersion, "baseline/candidate harness mismatch")
        try require(baseline.foundationIdentity == candidate.foundationIdentity, "baseline/candidate foundation mismatch")
        try require(baseline.buildContractVersion == candidate.buildContractVersion, "baseline/candidate build contract mismatch")
        try require(baseline.identity.sourceCommitSHA == baseline.buildProvenance.sourceIdentity.value, "baseline measurement identity does not match build provenance")
        try require(candidate.identity.sourceCommitSHA == candidate.buildProvenance.sourceIdentity.value, "candidate measurement identity does not match build provenance")
        try require(baseline.identity.contentManifestSHA256 == nil && candidate.identity.contentManifestSHA256 == nil, "comparison requires commit measurement identities")
        try require(baseline.identity.buildConfiguration == "release" && candidate.identity.buildConfiguration == "release", "comparison requires Release measurement identities")
        try require(sameMeasurementEnvironment(baseline.identity, candidate.identity), "baseline/candidate measurement environment mismatch")
        try require(baseline.runProvenance.configuration == configuration, "baseline configuration mismatch")
        try require(candidate.runProvenance.configuration == configuration, "candidate configuration mismatch")
        try require(baseline.identity.sourceCommitSHA != nil && candidate.identity.sourceCommitSHA != nil, "comparison requires immutable commit identities")
        try require(baseline.identity.sourceCommitSHA != candidate.identity.sourceCommitSHA, "baseline and candidate commits must differ")

        try PerformanceComparisonReportValidator.validateEligibility(
            eligibility,
            baseline: baseline.runProvenance,
            candidate: candidate.runProvenance,
            foundation: baseline.foundationIdentity,
            harnessVersion: baseline.harnessVersion,
            buildContractVersion: baseline.buildContractVersion
        )
        try require(eligibility.baselineCommitSHA == baseline.identity.sourceCommitSHA, "baseline eligibility does not match measurement identity")
        try require(eligibility.candidateCommitSHA == candidate.identity.sourceCommitSHA, "candidate eligibility does not match measurement identity")
        try require(baseline.runProvenance.acceptedFoundationArtifactSHA256 == candidate.runProvenance.acceptedFoundationArtifactSHA256, "baseline/candidate foundation artifact mismatch")
    }

    static func compare(
        baseline: PerformanceMeasurementReport,
        candidate: PerformanceMeasurementReport,
        configuration: PerformanceConfiguration,
        eligibility: PerformancePairEligibility,
        pairExecutionArtifact: PerformancePairExecutionArtifact,
        manualEvidenceDirectory: URL,
        pairExecutionArtifactSHA256: String,
        baselineMeasurementReportSHA256: String? = nil,
        candidateMeasurementReportSHA256: String? = nil
    ) throws -> PerformanceComparisonDraft {
        try preflight(baseline: baseline, candidate: candidate, configuration: configuration, eligibility: eligibility)
        let pairCount = configuration.totalPairs
        try require(configuration.pairsPerOrder == 15 && pairCount == 30, "comparison requires fifteen pairs per order")
        let artifactHash = pairExecutionArtifactSHA256
        let baselineReportHash = baselineMeasurementReportSHA256 ?? pairExecutionArtifact.baselineMeasurementReportSHA256
        let candidateReportHash = candidateMeasurementReportSHA256 ?? pairExecutionArtifact.candidateMeasurementReportSHA256
        try pairExecutionArtifact.validate(
            expectedBaselineID: baseline.identity.sourceCommitSHA!,
            expectedCandidateID: candidate.identity.sourceCommitSHA!,
            expectedBaselineReportHash: baselineMeasurementReportSHA256,
            expectedCandidateReportHash: candidateMeasurementReportSHA256,
            expectedArtifactHash: artifactHash,
            pairCount: pairCount
        )
        let manualEvidence = try loadManualEvidence(
            from: manualEvidenceDirectory,
            host: baseline.host.machineIdentifier,
            pairCount: pairCount,
            baselineID: baseline.identity.sourceCommitSHA!,
            candidateID: candidate.identity.sourceCommitSHA!,
            baselineReportHash: baselineReportHash,
            candidateReportHash: candidateReportHash,
            artifactHash: artifactHash,
            pairOrders: pairExecutionArtifact.records.sorted { $0.pairIndex < $1.pairIndex }.map(\.order)
        )
        let records = pairExecutionArtifact.records.sorted { $0.pairIndex < $1.pairIndex }

        let metrics = try PerformanceMetricID.allCases.map { metricID in
            let baselineValues = try samples(for: metricID, report: baseline, pairCount: pairCount)
            let baselineSamples = records.map { baselineValues[$0.baselineSampleIndex] }
            let candidateValues = try samples(for: metricID, report: candidate, pairCount: pairCount)
            let observedCandidateSamples = records.map { candidateValues[$0.candidateSampleIndex] }
            let candidateSamples: [Double]
            let evidence: ManualMetricEvidencePair?
            let evidenceClass: MetricEvidenceClass
            if let manual = manualEvidence[metricID] {
                try require(manual.baseline.samples.count == pairCount && manual.candidate.samples.count == pairCount, "manual evidence pair sample count does not match totalPairs")
                try require(manual.baseline.samples == baselineSamples && manual.candidate.samples == observedCandidateSamples, "manual evidence samples do not match pair execution")
                candidateSamples = manual.candidate.samples
                evidence = manual
                evidenceClass = .manual
            } else {
                candidateSamples = observedCandidateSamples
                evidence = nil
                evidenceClass = .deterministic
            }
            try require(baselineSamples.count == pairCount && candidateSamples.count == pairCount, "comparison sample count does not match totalPairs")
            try require(baselineSamples.allSatisfy { $0.isFinite && $0 > 0 } && candidateSamples.allSatisfy { $0.isFinite && $0 > 0 }, "comparison samples must be finite and positive")
            let ratios = zip(baselineSamples, candidateSamples).map { $1 / $0 }
            let deltas = zip(baselineSamples, candidateSamples).map { $1 - $0 }
            let interval = bootstrapInterval(deltas: deltas, seed: configuration.bootstrapSeed, resampleCount: configuration.bootstrapResamples)
            let disposition = metricDisposition(
                metricID: metricID,
                candidateSamples: candidateSamples,
                ratios: ratios
            )
            return MetricComparison(
                metricID: metricID,
                evidenceClass: evidenceClass,
                unit: metricID.canonicalUnit,
                baselineID: baseline.identity.sourceCommitSHA!,
                candidateID: candidate.identity.sourceCommitSHA!,
                baselineSamples: baselineSamples,
                candidateSamples: candidateSamples,
                ratios: ratios,
                deltas: deltas,
                budgetLimit: metricID.canonicalBudgetLimit,
                bootstrapInterval: interval,
                manualEvidence: evidence,
                disposition: disposition,
                improvementClaimed: interval.upperDelta < 0
            )
        }

        let resilience = try mapResilience(baseline: baseline.resilience, candidate: candidate.resilience)
        let rendererP95 = nearestRankP95(metrics.first { $0.metricID == .renderer }!.candidateSamples)
        let compositorP95 = nearestRankP95(metrics.first { $0.metricID == .compositor }!.candidateSamples)
        let combinedFrameP95 = nearestRankP95(metrics.first { $0.metricID == .combinedFrame }!.candidateSamples)
        let frameBudgetPasses = rendererP95 + compositorP95 <= 16.7
            && combinedFrameP95 <= 16.7
        let disposition: Disposition = metrics.allSatisfy { $0.disposition == .acceptedNoRegression }
            && resilience.disposition == .acceptedNoRegression
            && frameBudgetPasses
            ? .acceptedNoRegression
            : .revise

        return PerformanceComparisonDraft(
            harnessVersion: baseline.harnessVersion,
            foundationIdentity: baseline.foundationIdentity,
            buildContractVersion: baseline.buildContractVersion,
            baselineBuildProvenance: baseline.buildProvenance,
            candidateBuildProvenance: candidate.buildProvenance,
            baselineRunProvenance: baseline.runProvenance,
            candidateRunProvenance: candidate.runProvenance,
            pairEligibility: eligibility,
            pairExecutionArtifact: pairExecutionArtifact,
            pairExecutionArtifactSHA256: artifactHash,
            baselineFixture: baseline.fixture,
            candidateFixture: candidate.fixture,
            baselineMeasurementIdentity: baseline.identity,
            candidateMeasurementIdentity: candidate.identity,
            baselineID: baseline.identity.sourceCommitSHA!,
            candidateID: candidate.identity.sourceCommitSHA!,
            metrics: metrics,
            resilience: resilience,
            seed: configuration.bootstrapSeed,
            resampleCount: configuration.bootstrapResamples,
            disposition: disposition
        )
    }

    internal static func bootstrapInterval(deltas: [Double], seed: UInt64, resampleCount: Int) -> BootstrapInterval {
        PerformanceComparisonBootstrap.interval(deltas: deltas, seed: seed, resampleCount: resampleCount)
    }

    public static func writeComparison(
        draft: PerformanceComparisonDraft,
        baselineURL: URL,
        candidateURL: URL,
        pairExecutionURL: URL,
        manualEvidenceDirectory: URL,
        outputDirectory: URL,
        configuration: PerformanceConfiguration,
        eligibility: PerformancePairEligibility
    ) throws -> PerformanceComparisonReport {
        let baselineData = try Data(contentsOf: baselineURL)
        let candidateData = try Data(contentsOf: candidateURL)
        let pairExecutionData = try Data(contentsOf: pairExecutionURL)
        let baselineHash = sha256(baselineData)
        let candidateHash = sha256(candidateData)
        let canonicalPairExecutionData = try PerformancePairExecutionArtifact.canonicalData(from: pairExecutionData)
        try require(pairExecutionData == canonicalPairExecutionData, "pair execution artifact bytes are not canonical")
        let pairExecutionHash = sha256(canonicalPairExecutionData)
        let baseline = try JSONDecoder().decode(PerformanceMeasurementReport.self, from: baselineData)
        let candidate = try JSONDecoder().decode(PerformanceMeasurementReport.self, from: candidateData)
        let pairExecutionArtifact = try JSONDecoder().decode(PerformancePairExecutionArtifact.self, from: pairExecutionData)
        try preflight(baseline: baseline, candidate: candidate, configuration: configuration, eligibility: eligibility)
        let expectedDraft = try compare(
            baseline: baseline,
            candidate: candidate,
            configuration: configuration,
            eligibility: eligibility,
            pairExecutionArtifact: pairExecutionArtifact,
            manualEvidenceDirectory: manualEvidenceDirectory,
            pairExecutionArtifactSHA256: pairExecutionHash,
            baselineMeasurementReportSHA256: baselineHash,
            candidateMeasurementReportSHA256: candidateHash
        )
        try require(expectedDraft.pairExecutionArtifactSHA256 == pairExecutionHash, "pair execution artifact hash does not match exact input bytes")
        try require(pairExecutionArtifact.baselineMeasurementReportSHA256 == baselineHash, "pair execution baseline report hash mismatch")
        try require(pairExecutionArtifact.candidateMeasurementReportSHA256 == candidateHash, "pair execution candidate report hash mismatch")
        try require(draft == expectedDraft, "comparison draft does not match decoded measurements")
        let report = PerformanceComparisonReport(draft: draft, baselineMeasurementReportSHA256: baselineHash, candidateMeasurementReportSHA256: candidateHash)
        try report.validateCompletion()

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory.appendingPathComponent("paired-comparison.json")
        let comparisonData = try PerformanceCanonicalJSON.data(for: report)
        try comparisonData.write(to: outputURL, options: .atomic)
        return report
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw PerformanceValidationError.invalid(message)
        }
    }

    private static func samples(
        for metricID: PerformanceMetricID,
        report: PerformanceMeasurementReport,
        pairCount: Int
    ) throws -> [Double] {
        let values: [Double]
        switch metricID {
        case .model:
            values = report.model.trialNanoseconds
        case .renderer:
            values = report.renderer.frameMilliseconds
        case .compositor:
            values = report.compositor.frameMilliseconds
        case .combinedFrame:
            values = report.combinedFrame.frameMilliseconds
        case .launchCold:
            values = report.launch.coldMilliseconds
        case .launchWarm:
            values = report.launch.warmMilliseconds
        case .allocations:
            values = report.allocations.bytesPerGesture.map(Double.init)
        case .redrawLayout:
            values = report.redrawLayout.sampleMilliseconds
        case .responsiveness:
            values = report.responsiveness.responseMilliseconds
        case .inputToVisible:
            values = report.inputToVisible.sampleMilliseconds
        case .memoryRSS:
            values = report.memory.samples
                .filter { $0.phase == .running }
                .prefix(pairCount)
                .map { Double($0.rssBytes) }
        }
        try require(values.count == pairCount, "measurement does not contain exactly totalPairs samples for \(metricID.rawValue)")
        return Array(values.prefix(pairCount))
    }

    private static func metricDisposition(
        metricID: PerformanceMetricID,
        candidateSamples: [Double],
        ratios: [Double]
    ) -> Disposition {
        let ratioPasses = median(ratios) <= 1.10 && nearestRankP95(ratios) <= 1.10
        let budgetPasses = metricID.canonicalBudgetLimit.map { nearestRankP95(candidateSamples) <= $0 } ?? true
        return ratioPasses && budgetPasses ? .acceptedNoRegression : .revise
    }

    private static func mapResilience(
        baseline: ResilienceMeasurement,
        candidate: ResilienceMeasurement
    ) throws -> ResilienceMeasurement {
        try require(baseline.status == .measured && candidate.status == .measured, "comparison resilience must be measured")
        try require(baseline.cases.map(\.identifier) == candidate.cases.map(\.identifier), "baseline/candidate resilience cases mismatch")
        let healthy = baseline.disposition == .acceptedNoRegression
            && candidate.disposition == .acceptedNoRegression
            && baseline.cases.allSatisfy { $0.status == .measured && !$0.leakedResource && !$0.unexpectedGrowth }
            && candidate.cases.allSatisfy { $0.status == .measured && !$0.leakedResource && !$0.unexpectedGrowth }
        return ResilienceMeasurement(
            status: .measured,
            cases: candidate.cases,
            disposition: healthy ? .acceptedNoRegression : .revise
        )
    }

    private static func loadManualEvidence(
        from directory: URL,
        host: String,
        pairCount: Int,
        baselineID: String,
        candidateID: String,
        baselineReportHash: String,
        candidateReportHash: String,
        artifactHash: String,
        pairOrders: [PairOrder]
    ) throws -> [PerformanceMetricID: ManualMetricEvidencePair] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        try require(fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue, "manual evidence directory is required")
        let allowed: Set<PerformanceMetricID> = [.compositor, .inputToVisible]
        var result: [PerformanceMetricID: ManualMetricEvidencePair] = [:]
        let entries = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [])
        for entry in entries {
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            try require(values.isDirectory != true && values.isSymbolicLink != true, "manual evidence entries must be regular files")
            try require(entry.pathExtension == "json", "manual evidence directory contains an unexpected file")
            guard let metricID = PerformanceMetricID(rawValue: entry.deletingPathExtension().lastPathComponent) else {
                throw PerformanceValidationError.invalid("manual evidence contains an unknown metric file")
            }
            try require(allowed.contains(metricID), "deterministic metrics cannot load manual evidence")
            try require(result[metricID] == nil, "duplicate manual evidence metric")
            let data = try Data(contentsOf: entry)
            try validateManualJSONShape(data)
            let canonicalData = try ManualMetricAdapter.canonicalData(from: data)
            try require(data == canonicalData, "manual evidence bytes are not canonical")
            let adapter = try JSONDecoder().decode(ManualMetricAdapter.self, from: data)
            let evidence = adapter.evidence
            try require(evidence.pairOrders == pairOrders, "manual evidence pair order does not match execution artifact")
            try validateManualEvidencePair(evidence, metricID: metricID, host: host, baselineID: baselineID, candidateID: candidateID, baselineReportHash: baselineReportHash, candidateReportHash: candidateReportHash, artifactHash: artifactHash, pairCount: pairCount)
            try require(evidence.baseline.evidencePath == entry.lastPathComponent && evidence.candidate.evidencePath == entry.lastPathComponent, "manual evidence path does not match its file")
            result[metricID] = evidence
        }
        return result
    }

    private static func validateManualJSONShape(_ data: Data) throws {
        _ = try ManualMetricAdapter.canonicalData(from: data)
    }

    private static func validateManualEvidencePair(
        _ pair: ManualMetricEvidencePair,
        metricID: PerformanceMetricID,
        host: String,
        baselineID: String,
        candidateID: String,
        baselineReportHash: String,
        candidateReportHash: String,
        artifactHash: String,
        pairCount: Int
    ) throws {
        try require(!pair.procedureVersion.isEmpty, "manual evidence procedure version is required")
        try require(pair.baseline.permissions == pair.candidate.permissions, "manual evidence permissions differ between variants")
        try require(pair.baseline.steps == pair.candidate.steps, "manual evidence procedure steps differ between variants")
        try require(pair.baseline.evidencePath == pair.candidate.evidencePath, "manual evidence paths differ between variants")
        try validateManualEvidenceVariant(pair.baseline, expectedVariant: "baseline", expectedID: baselineID, expectedReportHash: baselineReportHash, artifactHash: artifactHash, metricID: metricID, host: host, pairCount: pairCount)
        try validateManualEvidenceVariant(pair.candidate, expectedVariant: "candidate", expectedID: candidateID, expectedReportHash: candidateReportHash, artifactHash: artifactHash, metricID: metricID, host: host, pairCount: pairCount)
    }

    private static func validateManualEvidenceVariant(
        _ evidence: ManualMetricEvidence,
        expectedVariant: String,
        expectedID: String,
        expectedReportHash: String,
        artifactHash: String,
        metricID: PerformanceMetricID,
        host: String,
        pairCount: Int
    ) throws {
        try require(evidence.variant == expectedVariant, "manual evidence variant mismatch")
        try require(evidence.sourceCommitSHA == expectedID, "manual evidence source identity mismatch")
        try require(evidence.measurementReportSHA256 == expectedReportHash, "manual evidence report hash mismatch")
        try require(evidence.pairExecutionArtifactSHA256 == artifactHash, "manual evidence artifact hash mismatch: expected \(artifactHash), got \(evidence.pairExecutionArtifactSHA256)")
        try require(evidence.metricID == metricID && evidence.evidenceClass == .manual, "manual evidence metric/class mismatch")
        try require(evidence.host == host, "manual evidence host mismatch")
        try require(!evidence.recordedAt.isEmpty && evidence.recordedAt.hasSuffix("Z"), "manual evidence timestamp is required")
        try require(ISO8601DateFormatter().date(from: evidence.recordedAt) != nil, "manual evidence timestamp is invalid")
        try require(!evidence.permissions.isEmpty && evidence.permissions.allSatisfy { !$0.isEmpty }, "manual evidence permissions are required")
        try require(!evidence.steps.isEmpty && !evidence.result.isEmpty, "manual evidence steps and result are required")
        try require(evidence.samples.count == pairCount && evidence.samples.allSatisfy { $0.isFinite && $0 > 0 }, "manual evidence samples must contain exactly totalPairs positive values")
        try require(evidence.evidencePath == "\(metricID.rawValue).json", "manual evidence path does not match its metric")
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func nearestRankP95(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let rank = max(1, Int(ceil(0.95 * Double(sorted.count))))
        return sorted[rank - 1]
    }


    private static func sameMeasurementEnvironment(_ baseline: MeasurementIdentity, _ candidate: MeasurementIdentity) -> Bool {
        baseline.hostModel == candidate.hostModel
            && baseline.macOSVersion == candidate.macOSVersion
            && baseline.xcodeVersion == candidate.xcodeVersion
            && baseline.developerDirectory == candidate.developerDirectory
            && baseline.powerState == candidate.powerState
            && baseline.displayState == candidate.displayState
            && baseline.buildConfiguration == candidate.buildConfiguration
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
