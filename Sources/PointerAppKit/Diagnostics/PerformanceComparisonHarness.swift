import Foundation
import CryptoKit

@MainActor
public enum PerformanceComparisonHarness {
    public static func preflight(
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

        try require(configuration == .standard, "comparison requires the standard configuration")
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
        manualEvidenceDirectory: URL
    ) throws -> PerformanceComparisonDraft {
        try preflight(baseline: baseline, candidate: candidate, configuration: configuration, eligibility: eligibility)
        let pairCount = configuration.totalPairs
        try require(configuration.pairsPerOrder == 15 && pairCount == 30, "comparison requires fifteen pairs per order")
        let manualEvidence = try loadManualEvidence(
            from: manualEvidenceDirectory,
            host: baseline.host.machineIdentifier,
            pairCount: pairCount
        )

        let metrics = try PerformanceMetricID.allCases.map { metricID in
            let baselineSamples = try samples(for: metricID, report: baseline, pairCount: pairCount)
            let candidateSamples: [Double]
            let evidence: ManualMetricEvidence?
            let evidenceClass: MetricEvidenceClass
            if let manual = manualEvidence[metricID] {
                candidateSamples = manual.samples
                evidence = manual
                evidenceClass = .manual
            } else {
                candidateSamples = try samples(for: metricID, report: candidate, pairCount: pairCount)
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
                pairOrders: PairOrder.canonicalSequence(pairCount: pairCount),
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
        manualEvidenceDirectory: URL,
        outputDirectory: URL,
        configuration: PerformanceConfiguration,
        eligibility: PerformancePairEligibility
    ) throws -> PerformanceComparisonReport {
        try _writeComparison(
            draft: draft,
            baselineURL: baselineURL,
            candidateURL: candidateURL,
            manualEvidenceDirectory: manualEvidenceDirectory,
            outputDirectory: outputDirectory,
            configuration: configuration,
            eligibility: eligibility
        )
    }

    private static func _writeComparison(
        draft: PerformanceComparisonDraft,
        baselineURL: URL,
        candidateURL: URL,
        manualEvidenceDirectory: URL,
        outputDirectory: URL,
        configuration: PerformanceConfiguration,
        eligibility: PerformancePairEligibility
    ) throws -> PerformanceComparisonReport {
        let baselineData = try Data(contentsOf: baselineURL)
        let candidateData = try Data(contentsOf: candidateURL)
        let baseline = try JSONDecoder().decode(PerformanceMeasurementReport.self, from: baselineData)
        let candidate = try JSONDecoder().decode(PerformanceMeasurementReport.self, from: candidateData)
        try preflight(baseline: baseline, candidate: candidate, configuration: configuration, eligibility: eligibility)
        let expectedDraft = try compare(
            baseline: baseline,
            candidate: candidate,
            configuration: configuration,
            eligibility: eligibility,
            manualEvidenceDirectory: manualEvidenceDirectory
        )
        try require(draft == expectedDraft, "comparison draft does not match decoded measurements")
        let baselineHash = sha256(baselineData)
        let candidateHash = sha256(candidateData)
        let report = PerformanceComparisonReport(draft: draft, baselineMeasurementReportSHA256: baselineHash, candidateMeasurementReportSHA256: candidateHash)
        try report.validateCompletion()

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let outputURL = outputDirectory.appendingPathComponent("paired-comparison.json")
        let comparisonData = try JSONEncoder().encode(report)
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
        pairCount: Int
    ) throws -> [PerformanceMetricID: ManualMetricEvidence] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        try require(fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue, "manual evidence directory is required")
        let allowed: Set<PerformanceMetricID> = [.compositor, .inputToVisible]
        var result: [PerformanceMetricID: ManualMetricEvidence] = [:]
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
            let adapter = try JSONDecoder().decode(ManualMetricAdapter.self, from: data)
            let evidence = adapter.evidence
            try require(evidence.metricID == metricID, "manual evidence metric does not match its file")
            try require(evidence.evidenceClass == .manual, "manual evidence class is invalid")
            try require(evidence.host == host, "manual evidence host mismatch")
            try require(!evidence.recordedAt.isEmpty && evidence.recordedAt.hasSuffix("Z"), "manual evidence timestamp is required")
            try require(ISO8601DateFormatter().date(from: evidence.recordedAt) != nil, "manual evidence timestamp is invalid")
            try require(!evidence.permissions.isEmpty && evidence.permissions.allSatisfy { !$0.isEmpty }, "manual evidence permissions are required")
            try require(!evidence.steps.isEmpty && !evidence.result.isEmpty, "manual evidence steps and result are required")
            try require(evidence.samples.count == pairCount && evidence.samples.allSatisfy { $0.isFinite && $0 > 0 }, "manual evidence samples must contain exactly totalPairs positive values")
            try require(!evidence.evidencePath.hasPrefix("/") && !evidence.evidencePath.split(separator: "/").contains(".."), "manual evidence path must be relative")
            try require(evidence.evidencePath == entry.lastPathComponent, "manual evidence path does not match its file")
            result[metricID] = evidence
        }
        return result
    }

    private static func validateManualJSONShape(_ data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any],
              Set(root.keys) == ["evidence"],
              let evidence = root["evidence"] as? [String: Any]
        else {
            throw PerformanceValidationError.invalid("manual evidence JSON envelope is invalid")
        }
        let expectedKeys: Set<String> = ["metricID", "evidenceClass", "host", "recordedAt", "permissions", "steps", "samples", "result", "evidencePath"]
        try require(Set(evidence.keys) == expectedKeys, "manual evidence JSON fields are invalid")
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
