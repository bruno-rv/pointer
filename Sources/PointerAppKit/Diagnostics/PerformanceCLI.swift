import Foundation
import CryptoKit
import Darwin

internal enum PerformancePublishPhase: Equatable {
    case prepared
    case backedUp
    case installed
    case restoredBackup
    case discardedBackup
}

private enum PerformancePublishTransactionState: String, Codable {
    case prepared
    case backedUp = "backed-up"
    case installed
}

private struct PerformancePublishTransaction: Codable {
    let schemaVersion: Int
    let transactionID: String
    let state: PerformancePublishTransactionState
    let outputPath: String
    let backupPath: String
    let stagingPath: String
    let hadExistingOutput: Bool

    init(
        transactionID: String,
        state: PerformancePublishTransactionState,
        outputPath: String,
        backupPath: String,
        stagingPath: String,
        hadExistingOutput: Bool
    ) {
        self.schemaVersion = 1
        self.transactionID = transactionID
        self.state = state
        self.outputPath = outputPath
        self.backupPath = backupPath
        self.stagingPath = stagingPath
        self.hadExistingOutput = hadExistingOutput
    }

    func replacing(state: PerformancePublishTransactionState) -> PerformancePublishTransaction {
        PerformancePublishTransaction(
            transactionID: transactionID,
            state: state,
            outputPath: outputPath,
            backupPath: backupPath,
            stagingPath: stagingPath,
            hadExistingOutput: hadExistingOutput
        )
    }
}

@MainActor
public enum PerformanceCLI {
    internal static var trialExecutor: (any PerformanceTrialExecuting)?
    internal static var publishPhaseHook: ((PerformancePublishPhase) -> Bool)?

    public static func run(arguments: [String], outputDirectory: URL) throws {
        switch try parse(arguments: arguments, outputDirectory: outputDirectory) {
        case let .trial(invocation):
            try runTrial(invocation)
        case let .finalize(invocation):
            try runFinalize(invocation)
        case let .compare(invocation):
            try runComparison(invocation)
        case let .campaignComplete(invocation):
            try runCampaignComplete(invocation, outputDirectory: outputDirectory)
        }
    }

    internal enum Invocation: Equatable {
        case trial(TrialInvocation)
        case finalize(FinalizeInvocation)
        case compare(ComparisonInvocation)
        case campaignComplete(CampaignCompletionInvocation)
    }

    internal struct TrialInvocation: Equatable {
        let variant: PerformanceVariant
        let profile: PerformanceFixtureProfile
        let pairOrder: PairOrder
        let pairIndex: Int
        let sourceIdentity: SourceIdentity
        let runProvenanceURL: URL
        let pairEligibilityURL: URL
        let partialDirectory: URL
        let externalTrialSidecarURL: URL?

        var sampleIndex: Int { pairIndex }
    }

    internal struct FinalizeInvocation: Equatable {
        let profile: PerformanceFixtureProfile
        let partialDirectory: URL
        let baselineRunProvenanceURL: URL
        let candidateRunProvenanceURL: URL
        let pairEligibilityURL: URL
        let baselineExternalAggregateURL: URL?
        let candidateExternalAggregateURL: URL?
        let outputDirectory: URL
    }

    internal struct ComparisonInvocation: Equatable {
        let profile: PerformanceFixtureProfile
        let baselineURL: URL
        let candidateURL: URL
        let eligibilityURL: URL
        let pairExecutionURL: URL
        let manualEvidenceDirectory: URL
        let outputDirectory: URL
    }

    internal struct CampaignCompletionInvocation: Equatable {
        let standard12ComparisonURL: URL
        let dense1000ComparisonURL: URL
        let outputURL: URL
    }

    internal static func parse(
        arguments: [String],
        outputDirectory: URL
    ) throws -> Invocation {
        var parser = ArgumentParser(arguments: arguments)
        let command: QualityCommand
        if parser.consumeFlag("--quality-performance") {
            command = .performance
        } else if parser.consumeFlag("--quality-compare") {
            command = .compare
        } else if parser.consumeFlag("--quality-campaign-complete") {
            command = .campaignComplete
        } else {
            throw error("one quality command is required")
        }
        try parser.requireValue("--format", equals: "json")

        switch command {
        case .performance:
            let operation = try parser.requireOperation()
            let profile = try parser.requireProfile()
            switch operation {
            case .trial:
                let variant = try parser.requireVariant()
                let order = try parser.requirePairOrder()
                let pairIndex = try parser.requireInt("--pair-index")
                let sourceIdentity = try parser.requireSourceIdentity()
                let runProvenanceURL = try parser.requireURL("--run-provenance-file")
                let pairEligibilityURL = try parser.requireURL("--pair-eligibility-file")
                let externalTrialSidecarURL = try parser.consumeOptionalURL("--external-trial-sidecar")
                let partialDirectory = try parser.requireURL("--partial-pair-directory")
                try validateTrialPathContext(profile: profile, variant: variant, pairIndex: pairIndex, partialDirectory: partialDirectory, runProvenanceURL: runProvenanceURL, pairEligibilityURL: pairEligibilityURL, externalTrialSidecarURL: externalTrialSidecarURL)
                try require(pairIndex >= 0 && pairIndex < 30, "pair index is invalid")
                try require(order == (pairIndex < 15 ? .baselineFirst : .candidateFirst), "pair order does not match pair index")
                try parser.requireEnd()
                return .trial(TrialInvocation(variant: variant, profile: profile, pairOrder: order, pairIndex: pairIndex, sourceIdentity: sourceIdentity, runProvenanceURL: runProvenanceURL, pairEligibilityURL: pairEligibilityURL, partialDirectory: partialDirectory, externalTrialSidecarURL: externalTrialSidecarURL))
            case .finalize:
                let partialDirectory = try parser.requireURL("--partial-pair-directory")
                let baselineRunProvenanceURL = try parser.requireURL("--baseline-run-provenance-file")
                let candidateRunProvenanceURL = try parser.requireURL("--candidate-run-provenance-file")
                let pairEligibilityURL = try parser.requireURL("--pair-eligibility-file")
                let baselineExternalAggregateURL = try parser.consumeOptionalURL("--baseline-external-aggregate-sidecar")
                let candidateExternalAggregateURL = try parser.consumeOptionalURL("--candidate-external-aggregate-sidecar")
                let declaredOutput = try parser.requireURL("--output-dir")
                try require(declaredOutput.standardizedFileURL.path == outputDirectory.standardizedFileURL.path, "--output-dir does not match the output directory argument")
                try validateFinalizePathContext(profile: profile, partialDirectory: partialDirectory, baselineRunProvenanceURL: baselineRunProvenanceURL, candidateRunProvenanceURL: candidateRunProvenanceURL, pairEligibilityURL: pairEligibilityURL, baselineExternalAggregateURL: baselineExternalAggregateURL, candidateExternalAggregateURL: candidateExternalAggregateURL, outputDirectory: declaredOutput)
                try parser.requireEnd()
                return .finalize(FinalizeInvocation(profile: profile, partialDirectory: partialDirectory, baselineRunProvenanceURL: baselineRunProvenanceURL, candidateRunProvenanceURL: candidateRunProvenanceURL, pairEligibilityURL: pairEligibilityURL, baselineExternalAggregateURL: baselineExternalAggregateURL, candidateExternalAggregateURL: candidateExternalAggregateURL, outputDirectory: declaredOutput))
            }
        case .compare:
            let profile = try parser.requireProfile()
            let baselineURL = try parser.requireURL("--baseline-report")
            let candidateURL = try parser.requireURL("--candidate-report")
            let eligibilityURL = try parser.requireURL("--pair-eligibility-file")
            let pairExecutionURL = try parser.requireURL("--pair-execution-artifact")
            let manualEvidenceDirectory = try parser.requireURL("--manual-evidence-dir")
            let declaredOutput = try parser.requireURL("--output-dir")
            try require(declaredOutput.standardizedFileURL.path == outputDirectory.standardizedFileURL.path, "--output-dir does not match the output directory argument")
            try validateComparisonPaths(profile: profile, baselineURL: baselineURL, candidateURL: candidateURL, eligibilityURL: eligibilityURL, pairExecutionURL: pairExecutionURL, manualEvidenceDirectory: manualEvidenceDirectory, outputDirectory: declaredOutput)
            try parser.requireEnd()
            return .compare(ComparisonInvocation(profile: profile, baselineURL: baselineURL, candidateURL: candidateURL, eligibilityURL: eligibilityURL, pairExecutionURL: pairExecutionURL, manualEvidenceDirectory: manualEvidenceDirectory, outputDirectory: declaredOutput))
        case .campaignComplete:
            let standard12ComparisonURL = try parser.requireURL("--standard12-comparison")
            let dense1000ComparisonURL = try parser.requireURL("--dense1000-comparison")
            let outputURL = try parser.requireURL("--output-file")
            try PerformanceCampaignCompletion.validateSharedPerformanceRoot(standard12ComparisonURL: standard12ComparisonURL, dense1000ComparisonURL: dense1000ComparisonURL, outputURL: outputURL, outputDirectory: outputDirectory)
            try parser.requireEnd()
            return .campaignComplete(CampaignCompletionInvocation(standard12ComparisonURL: standard12ComparisonURL, dense1000ComparisonURL: dense1000ComparisonURL, outputURL: outputURL))
        }
    }

    private static func runTrial(_ invocation: TrialInvocation) throws {
        let repoRoot = try repositoryRoot(for: invocation.pairEligibilityURL, profile: invocation.profile, kind: .eligibility)
        try validatePartialDirectory(invocation.partialDirectory, profile: invocation.profile, repoRoot: repoRoot)
        let (run, runHash) = try loadCanonical(PerformanceRunProvenance.self, from: invocation.runProvenanceURL)
        let (eligibility, eligibilityHash) = try loadCanonical(PerformancePairEligibility.self, from: invocation.pairEligibilityURL)
        try run.validateStructure()
        try validateRunEnvelope(run, profile: invocation.profile, variant: invocation.variant, sourceIdentity: invocation.sourceIdentity, repoRoot: repoRoot)
        try validateEligibility(eligibility, run: run, profile: invocation.profile, sourceIdentity: invocation.sourceIdentity, repoRoot: repoRoot)
        let request = PerformanceTrialRequest(variant: invocation.variant, fixtureProfile: invocation.profile, pairIndex: invocation.pairIndex, order: invocation.pairOrder, sampleIndex: invocation.pairIndex)
        try request.validate()
        let externalSidecar = try loadExternalTrialSidecar(
            from: invocation.externalTrialSidecarURL,
            request: request,
            sourceIdentity: invocation.sourceIdentity,
            runProvenanceSHA256: runHash,
            pairEligibilitySHA256: eligibilityHash
        )
        let store = PerformancePartialPairStore(directory: invocation.partialDirectory)
        let partialDirectoryIdentity = try store.captureDirectoryIdentity(createIfMissing: true)
        try store.auditBeforeMeasurement(
            configuration: run.configuration,
            profile: invocation.profile,
            selectedVariant: invocation.variant,
            selectedSourceIdentity: invocation.sourceIdentity,
            selectedRunProvenanceSHA256: runHash,
            pairEligibilitySHA256: eligibilityHash,
            eligibility: eligibility
        )
        try store.validateDirectoryIdentity(partialDirectoryIdentity)
        let reservation = try store.reserve(
            request: request,
            sourceIdentity: invocation.sourceIdentity,
            runProvenanceSHA256: runHash,
            pairEligibilitySHA256: eligibilityHash,
            expectedDirectoryIdentity: partialDirectoryIdentity
        )
        defer { reservation.release() }
        if let existing = reservation.existing {
            let existingResult = invocation.variant == .baseline ? existing.baseline : existing.candidate
            if let existingResult {
                try validateRetryExternalEvidence(existingResult, sidecar: externalSidecar)
                return
            }
        }
        let executor = trialExecutor ?? ProductionPerformanceTrialExecutor()
        var result = try PerformanceTrialRunner.run(request: request, sourceIdentity: invocation.sourceIdentity, runProvenanceSHA256: runHash, pairEligibilitySHA256: eligibilityHash, executor: executor)
        if let externalSidecar {
            try validateExternalInterval(externalSidecar.binding, contains: result)
        }
        let externalMeasurements = externalSidecar?.measurements ?? synthesizedExternalMeasurements()
        let externalByMetric = Dictionary(uniqueKeysWithValues: externalMeasurements.map { ($0.metricID, $0) })
        let mergedSamples = try PerformanceMetricID.allCases.map { metricID -> PerformanceTrialMetricSample in
            if let measurement = externalByMetric[metricID] {
                return PerformanceTrialMetricSample(metricID: metricID, unit: measurement.unit, status: measurement.status, value: measurement.value, diagnostic: measurement.diagnostic)
            }
            guard let sample = result.samples.first(where: { $0.metricID == metricID }) else {
                throw PerformanceValidationError.invalid("trial executor omitted metric \(metricID.rawValue)")
            }
            return sample
        }
        result = result.replacing(
            samples: mergedSamples
        )
        try result.validate()
        let partial: PerformancePartialPair
        switch invocation.variant {
        case .baseline:
            partial = PerformancePartialPair(fixtureProfile: invocation.profile, pairIndex: invocation.pairIndex, order: invocation.pairOrder, baseline: result)
        case .candidate:
            partial = PerformancePartialPair(fixtureProfile: invocation.profile, pairIndex: invocation.pairIndex, order: invocation.pairOrder, candidate: result)
        }
        _ = try reservation.commit(partial)
    }

    private static func loadExternalTrialSidecar(
        from url: URL?,
        request: PerformanceTrialRequest,
        sourceIdentity: SourceIdentity,
        runProvenanceSHA256: String,
        pairEligibilitySHA256: String
    ) throws -> PerformanceExternalTrialSidecar? {
        guard let url else { return nil }
        let (sidecar, _) = try loadCanonical(PerformanceExternalTrialSidecar.self, from: url)
        try sidecar.validate()
        try require(sidecar.binding.request == request, "external trial request binding mismatch")
        try require(sidecar.binding.sourceIdentity == sourceIdentity, "external trial source identity binding mismatch")
        try require(sidecar.binding.runProvenanceSHA256 == runProvenanceSHA256, "external trial provenance binding mismatch")
        try require(sidecar.binding.pairEligibilitySHA256 == pairEligibilitySHA256, "external trial eligibility binding mismatch")
        return sidecar
    }

    private static func validateRetryExternalEvidence(
        _ result: PerformanceTrialResult,
        sidecar: PerformanceExternalTrialSidecar?
    ) throws {
        let expectedMeasurements = sidecar?.measurements ?? synthesizedExternalMeasurements()
        let actualMeasurements = expectedMeasurements.map { measurement in
            result.samples.first { $0.metricID == measurement.metricID }
        }
        try require(actualMeasurements.allSatisfy { $0 != nil }, "retry result is missing an external metric sample")
        for (measurement, actual) in zip(expectedMeasurements, actualMeasurements.compactMap({ $0 })) {
            try require(
                actual.metricID == measurement.metricID
                    && actual.unit == measurement.unit
                    && actual.status == measurement.status
                    && actual.value == measurement.value
                    && actual.diagnostic == measurement.diagnostic,
                "retry external metric evidence conflicts with the persisted result"
            )
        }
        if let sidecar {
            try validateExternalInterval(sidecar.binding, contains: result)
        }
    }

    private static func synthesizedExternalMeasurements() -> [PerformanceExternalTrialScalarMeasurement] {
        PerformanceExternalTrialSidecar.requiredMetricIDs.map { metricID in
            PerformanceExternalTrialScalarMeasurement(
                metricID: metricID,
                unit: metricID.canonicalUnit,
                status: .unmeasured,
                value: nil,
                diagnostic: "external-\(metricID.rawValue)-unavailable"
            )
        }
    }

    private static func validateExternalInterval(
        _ binding: PerformanceExternalTrialBinding,
        contains result: PerformanceTrialResult
    ) throws {
        guard let externalStart = PerformanceTimestamp.date(from: binding.startedAtUTC),
              let externalEnd = PerformanceTimestamp.date(from: binding.endedAtUTC),
              let actualStart = PerformanceTimestamp.date(from: result.startedAtUTC),
              let actualEnd = PerformanceTimestamp.date(from: result.endedAtUTC)
        else {
            throw PerformanceValidationError.invalid("external trial interval is not valid UTC")
        }
        try require(
            externalStart <= actualStart && actualStart <= actualEnd && actualEnd <= externalEnd,
            "external trial interval does not contain the in-process trial interval"
        )
    }

    private static func loadExternalAggregate(from url: URL?) throws -> PerformanceExternalAggregateSidecar? {
        guard let url else { return nil }
        let (sidecar, _) = try loadCanonical(PerformanceExternalAggregateSidecar.self, from: url)
        try sidecar.validate()
        return sidecar
    }

    private static func runFinalize(_ invocation: FinalizeInvocation) throws {
        for url in [
            invocation.partialDirectory,
            invocation.baselineRunProvenanceURL,
            invocation.candidateRunProvenanceURL,
            invocation.pairEligibilityURL,
            invocation.outputDirectory
        ] {
            try rejectTraversalOrSymlink(url)
        }
        if let baselineExternalAggregateURL = invocation.baselineExternalAggregateURL {
            try rejectTraversalOrSymlink(baselineExternalAggregateURL)
        }
        if let candidateExternalAggregateURL = invocation.candidateExternalAggregateURL {
            try rejectTraversalOrSymlink(candidateExternalAggregateURL)
        }
        let repoRoot = try repositoryRoot(for: invocation.pairEligibilityURL, profile: invocation.profile, kind: .eligibility)
        try validatePartialDirectory(invocation.partialDirectory, profile: invocation.profile, repoRoot: repoRoot)
        try recoverPublishTransaction(output: invocation.outputDirectory, profile: invocation.profile)
        let (baselineRun, baselineHash) = try loadCanonical(PerformanceRunProvenance.self, from: invocation.baselineRunProvenanceURL)
        let (candidateRun, candidateHash) = try loadCanonical(PerformanceRunProvenance.self, from: invocation.candidateRunProvenanceURL)
        let (eligibility, eligibilityHash) = try loadCanonical(PerformancePairEligibility.self, from: invocation.pairEligibilityURL)
        try baselineRun.validateStructure()
        try candidateRun.validateStructure()
        try require(baselineRun.variant == "baseline" && candidateRun.variant == "candidate", "finalize provenance variants are invalid")
        try require(baselineRun.configuration.isCanonical && baselineRun.configuration.fixtureProfile == invocation.profile && candidateRun.configuration == baselineRun.configuration, "finalize configuration/profile mismatch")
        try validateRunEnvelope(baselineRun, profile: invocation.profile, variant: .baseline, sourceIdentity: baselineRun.build.sourceIdentity, repoRoot: repoRoot)
        try validateRunEnvelope(candidateRun, profile: invocation.profile, variant: .candidate, sourceIdentity: candidateRun.build.sourceIdentity, repoRoot: repoRoot)
        try validateEligibilityPair(eligibility, baseline: baselineRun, candidate: candidateRun, profile: invocation.profile, repoRoot: repoRoot)
        try PerformanceComparisonReportValidator.validateEligibility(
            eligibility,
            baseline: baselineRun,
            candidate: candidateRun,
            foundation: baselineRun.foundation,
            harnessVersion: baselineRun.harnessVersion,
            buildContractVersion: baselineRun.buildContractVersion
        )
        let baselineExternalAggregate = try loadExternalAggregate(from: invocation.baselineExternalAggregateURL)
        let candidateExternalAggregate = try loadExternalAggregate(from: invocation.candidateExternalAggregateURL)
        let stagingOutputDirectory = invocation.outputDirectory.deletingLastPathComponent()
            .appendingPathComponent(".\(invocation.profile.rawValue).pending-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingOutputDirectory, withIntermediateDirectories: true)
        var preserveStagingForRecovery = false
        defer {
            if !preserveStagingForRecovery && FileManager.default.fileExists(atPath: stagingOutputDirectory.path) {
                try? FileManager.default.removeItem(at: stagingOutputDirectory)
            }
        }
        let stagingComparisons = stagingOutputDirectory.appendingPathComponent("comparisons", isDirectory: true)
        let stagingProvenance = stagingOutputDirectory.appendingPathComponent("provenance", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingComparisons, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stagingProvenance, withIntermediateDirectories: true)
        try PerformanceCanonicalJSON.data(for: eligibility).write(to: stagingComparisons.appendingPathComponent("pair-eligibility.json"), options: .atomic)
        try PerformanceCanonicalJSON.data(for: baselineRun).write(to: stagingProvenance.appendingPathComponent("baseline.json"), options: .atomic)
        try PerformanceCanonicalJSON.data(for: candidateRun).write(to: stagingProvenance.appendingPathComponent("candidate.json"), options: .atomic)
        _ = try PerformancePairExecutionFinalizer.finalize(
            partialDirectory: invocation.partialDirectory,
            baselineReportURL: stagingOutputDirectory.appendingPathComponent("measurements", isDirectory: true).appendingPathComponent("baseline.json"),
            candidateReportURL: stagingOutputDirectory.appendingPathComponent("measurements", isDirectory: true).appendingPathComponent("candidate.json"),
            outputDirectory: stagingOutputDirectory,
            configuration: baselineRun.configuration,
            baselineRun: baselineRun,
            candidateRun: candidateRun,
            baselineBuild: baselineRun.build,
            candidateBuild: candidateRun.build,
            baselineIdentity: measurementIdentity(for: baselineRun),
            candidateIdentity: measurementIdentity(for: candidateRun),
            baselineRunProvenanceSHA256: baselineHash,
            candidateRunProvenanceSHA256: candidateHash,
            pairEligibilitySHA256: eligibilityHash,
            baselineExternalAggregate: baselineExternalAggregate,
            candidateExternalAggregate: candidateExternalAggregate
        )
        let didPublish = try publishProfile(
            staging: stagingOutputDirectory,
            output: invocation.outputDirectory,
            profile: invocation.profile,
            baselineSourceIdentity: baselineRun.build.sourceIdentity,
            candidateSourceIdentity: candidateRun.build.sourceIdentity,
            baselineRunProvenanceSHA256: baselineHash,
            candidateRunProvenanceSHA256: candidateHash,
            pairEligibilitySHA256: eligibilityHash,
            preserveStaging: &preserveStagingForRecovery
        )
        if !didPublish {
            throw PerformanceValidationError.invalid("injected publish interruption")
        }
    }

    private static func publishProfile(
        staging: URL,
        output: URL,
        profile: PerformanceFixtureProfile,
        baselineSourceIdentity: SourceIdentity,
        candidateSourceIdentity: SourceIdentity,
        baselineRunProvenanceSHA256: String,
        candidateRunProvenanceSHA256: String,
        pairEligibilitySHA256: String,
        preserveStaging: inout Bool
    ) throws -> Bool {
        let fileManager = FileManager.default
        let outputExists = nodeExists(output)
        if outputExists {
            try validatePhysicalTree(output)
            var isDirectory: ObjCBool = false
            try require(fileManager.fileExists(atPath: output.path, isDirectory: &isDirectory) && isDirectory.boolValue, "existing finalize output is not a directory")
        }
        if outputExists,
           try isScriptPreseedDirectory(output) {
            return try installPublishTransaction(staging: staging, output: output, profile: profile, hadExistingOutput: true, preserveStaging: &preserveStaging)
        }
        if outputExists,
           try mergeExternalEvidencePreseed(
               staging: staging,
               output: output,
               profile: profile,
               baselineSourceIdentity: baselineSourceIdentity,
               candidateSourceIdentity: candidateSourceIdentity,
               baselineRunProvenanceSHA256: baselineRunProvenanceSHA256,
               candidateRunProvenanceSHA256: candidateRunProvenanceSHA256,
               pairEligibilitySHA256: pairEligibilitySHA256
           ) {
            if try directoryContentsEqual(staging, output) {
                try fileManager.removeItem(at: staging)
                return true
            }
            try require(!hasFinalizedOutputNodes(output), "finalize output conflicts with existing profile bytes")
            return try installPublishTransaction(staging: staging, output: output, profile: profile, hadExistingOutput: true, preserveStaging: &preserveStaging)
        }
        if outputExists {
            if try directoryContentsEqual(staging, output) {
                try fileManager.removeItem(at: staging)
                return true
            }
            throw PerformanceValidationError.invalid("finalize output conflicts with existing profile bytes")
        }
        return try installPublishTransaction(staging: staging, output: output, profile: profile, hadExistingOutput: false, preserveStaging: &preserveStaging)
    }

    private static func installPublishTransaction(
        staging: URL,
        output: URL,
        profile: PerformanceFixtureProfile,
        hadExistingOutput: Bool,
        preserveStaging: inout Bool
    ) throws -> Bool {
        let fileManager = FileManager.default
        let parent = output.deletingLastPathComponent().standardizedFileURL
        let journal = parent.appendingPathComponent(".benchmark-quality.transaction.\(profile.rawValue)")
        let backup = parent.appendingPathComponent(".benchmark-quality.backup.\(profile.rawValue)/\(output.lastPathComponent)")
        try require(!nodeExists(journal), "an unresolved finalize transaction already exists")
        try require(!nodeExists(backup), "an orphaned finalize backup requires recovery")
        if nodeExists(backup.deletingLastPathComponent()) {
            try validateEmptyDirectory(backup.deletingLastPathComponent(), label: "finalize backup container")
        }
        let transactionID = try transactionID(from: staging, profile: profile)
        let transaction = PerformancePublishTransaction(
            transactionID: transactionID,
            state: .prepared,
            outputPath: output.standardizedFileURL.path,
            backupPath: backup.standardizedFileURL.path,
            stagingPath: staging.standardizedFileURL.path,
            hadExistingOutput: hadExistingOutput
        )
        try writePublishTransaction(transaction, at: journal)
        preserveStaging = true
        if shouldInterruptPublish(.prepared) { return false }
        if hadExistingOutput {
            try fileManager.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: output, to: backup)
            try syncDirectory(parent)
            try syncDirectory(backup.deletingLastPathComponent())
            try writePublishTransaction(transaction.replacing(state: .backedUp), at: journal)
            if shouldInterruptPublish(.backedUp) { return false }
        }
        try fileManager.moveItem(at: staging, to: output)
        try validatePhysicalTree(output)
        try writePublishTransaction(transaction.replacing(state: .installed), at: journal)
        if shouldInterruptPublish(.installed) { return false }
        if nodeExists(backup) {
            try require(try discardBackup(backup), "injected publish interruption")
        }
        if nodeExists(journal) {
            try fileManager.removeItem(at: journal)
            try syncDirectory(parent)
        }
        preserveStaging = false
        return true
    }

    private static func recoverPublishTransaction(output: URL, profile: PerformanceFixtureProfile) throws {
        let fileManager = FileManager.default
        let parent = output.deletingLastPathComponent().standardizedFileURL
        let journal = parent.appendingPathComponent(".benchmark-quality.transaction.\(profile.rawValue)")
        let journalTemporary = journal.appendingPathExtension("tmp")
        let backup = parent.appendingPathComponent(".benchmark-quality.backup.\(profile.rawValue)/\(output.lastPathComponent)")
        if !nodeExists(journal) {
            if nodeExists(journalTemporary) {
                try validateRegularFile(journalTemporary, label: "finalize transaction journal temporary")
                try fileManager.removeItem(at: journalTemporary)
            }
            if nodeExists(backup) {
                throw PerformanceValidationError.invalid("orphaned finalize backup requires recovery")
            }
            try removeEmptyBackupContainer(backup)
            return
        }
        try validateRegularFile(journal, label: "finalize transaction journal")
        let data = try Data(contentsOf: journal)
        let transaction = try PerformanceCanonicalJSON.decoded(PerformancePublishTransaction.self, from: data)
        try require(transaction.schemaVersion == 1, "unsupported finalize transaction journal version")
        try require(UUID(uuidString: transaction.transactionID) != nil, "finalize transaction ID is invalid")
        try require(transaction.outputPath == output.standardizedFileURL.path, "finalize transaction output path does not match")
        try require(transaction.backupPath == backup.standardizedFileURL.path, "finalize transaction backup path does not match")
        try validateCanonicalAbsolutePath(transaction.outputPath, label: "finalize transaction output path")
        try validateCanonicalAbsolutePath(transaction.backupPath, label: "finalize transaction backup path")
        try validateCanonicalAbsolutePath(transaction.stagingPath, label: "finalize transaction staging path")
        let staging = URL(fileURLWithPath: transaction.stagingPath, isDirectory: true).standardizedFileURL
        try require(staging.deletingLastPathComponent().path == parent.path, "finalize transaction staging path is not same-parent")
        try require(staging.lastPathComponent == ".\(profile.rawValue).pending-\(transaction.transactionID)", "finalize transaction staging path does not match its transaction ID")
        let outputExists = nodeExists(output)
        let backupExists = nodeExists(backup)
        let stagingExists = nodeExists(staging)
        if outputExists { try validatePhysicalTree(output) }
        if backupExists { try validatePhysicalTree(backup) }
        if backupExists { try validateBackupContainer(backup) }
        if stagingExists { try validateStagedProfile(staging, profile: profile) }
        switch transaction.state {
        case .prepared:
            if backupExists {
                if outputExists { try fileManager.removeItem(at: output) }
                try require(try restoreBackup(backup, to: output), "injected publish interruption")
            } else if transaction.hadExistingOutput {
                try require(outputExists, "prepared finalize transaction lost its existing output")
            } else if outputExists {
                try fileManager.removeItem(at: output)
            }
            if stagingExists { try fileManager.removeItem(at: staging) }
        case .backedUp:
            if stagingExists {
                if outputExists { try fileManager.removeItem(at: output) }
                try fileManager.moveItem(at: staging, to: output)
                try validatePhysicalTree(output)
                if backupExists { try require(try discardBackup(backup), "injected publish interruption") }
            } else if backupExists {
                if outputExists { try fileManager.removeItem(at: output) }
                try require(try restoreBackup(backup, to: output), "injected publish interruption")
            } else {
                try require(outputExists, "backed-up finalize transaction lost both output and backup")
            }
        case .installed:
            if !outputExists {
                try require(backupExists, "installed finalize transaction lost both output and backup")
                try require(try restoreBackup(backup, to: output), "injected publish interruption")
            } else if backupExists {
                try require(try discardBackup(backup), "injected publish interruption")
            }
            if stagingExists { try fileManager.removeItem(at: staging) }
        }
        try removeEmptyBackupContainer(backup)
        if nodeExists(journal) {
            try fileManager.removeItem(at: journal)
            try syncDirectory(parent)
        }
        if nodeExists(journalTemporary) { try fileManager.removeItem(at: journalTemporary) }
    }

    private static func writePublishTransaction(_ transaction: PerformancePublishTransaction, at journal: URL) throws {
        let fileManager = FileManager.default
        let temporary = journal.appendingPathExtension("tmp")
        if nodeExists(journal) {
            try validateRegularFile(journal, label: "finalize transaction journal")
        }
        if nodeExists(temporary) {
            try validateRegularFile(temporary, label: "finalize transaction journal temporary")
            try fileManager.removeItem(at: temporary)
        }
        try PerformanceCanonicalJSON.data(for: transaction).write(to: temporary, options: .atomic)
        if nodeExists(journal) {
            _ = try fileManager.replaceItemAt(journal, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: journal)
        }
        try syncDirectory(journal.deletingLastPathComponent())
    }

    private static func transactionID(from staging: URL, profile: PerformanceFixtureProfile) throws -> String {
        let prefix = ".\(profile.rawValue).pending-"
        try require(staging.lastPathComponent.hasPrefix(prefix), "finalize staging path is not canonical")
        let id = String(staging.lastPathComponent.dropFirst(prefix.count))
        try require(UUID(uuidString: id) != nil, "finalize transaction ID is invalid")
        return id
    }

    private static func validateCanonicalAbsolutePath(_ value: String, label: String) throws {
        try require(value.hasPrefix("/") && !value.hasPrefix("//") && !value.hasSuffix("/") && !value.contains("//"), "\(label) is not canonical")
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        try require(components.dropFirst().allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }, "\(label) contains a traversal or dot component")
        try require(URL(fileURLWithPath: value).path == value, "\(label) is not canonically spelled")
    }

    private static func validateStagedProfile(_ root: URL, profile: PerformanceFixtureProfile) throws {
        try validatePhysicalTree(root)
        let mainDirectories: Set<String> = ["comparisons", "provenance", "measurements", "pair-execution"]
        var expectedTop = mainDirectories
        if nodeExists(root.appendingPathComponent("external", isDirectory: true)) {
            expectedTop.insert("external")
        }
        try require(try childNames(root) == expectedTop, "staged profile topology is not exact")
        try require(try childNames(root.appendingPathComponent("comparisons", isDirectory: true)) == ["pair-eligibility.json"], "staged comparisons topology is not exact")
        try require(try childNames(root.appendingPathComponent("provenance", isDirectory: true)) == ["baseline.json", "candidate.json"], "staged provenance topology is not exact")
        try require(try childNames(root.appendingPathComponent("measurements", isDirectory: true)) == ["baseline.json", "candidate.json"], "staged measurements topology is not exact")
        try require(try childNames(root.appendingPathComponent("pair-execution", isDirectory: true)) == ["pair-execution.json"], "staged pair execution topology is not exact")

        let eligibilityURL = root.appendingPathComponent("comparisons/pair-eligibility.json")
        let baselineProvenanceURL = root.appendingPathComponent("provenance/baseline.json")
        let candidateProvenanceURL = root.appendingPathComponent("provenance/candidate.json")
        let baselineReportURL = root.appendingPathComponent("measurements/baseline.json")
        let candidateReportURL = root.appendingPathComponent("measurements/candidate.json")
        let artifactURL = root.appendingPathComponent("pair-execution/pair-execution.json")
        let eligibilityData = try Data(contentsOf: eligibilityURL)
        let baselineProvenanceData = try Data(contentsOf: baselineProvenanceURL)
        let candidateProvenanceData = try Data(contentsOf: candidateProvenanceURL)
        let baselineReportData = try Data(contentsOf: baselineReportURL)
        let candidateReportData = try Data(contentsOf: candidateReportURL)
        let artifactData = try Data(contentsOf: artifactURL)
        let eligibility = try PerformanceCanonicalJSON.decoded(PerformancePairEligibility.self, from: eligibilityData)
        let baselineRun = try PerformanceCanonicalJSON.decoded(PerformanceRunProvenance.self, from: baselineProvenanceData)
        let candidateRun = try PerformanceCanonicalJSON.decoded(PerformanceRunProvenance.self, from: candidateProvenanceData)
        let baselineReport = try PerformanceCanonicalJSON.decoded(PerformanceMeasurementReport.self, from: baselineReportData)
        let candidateReport = try PerformanceCanonicalJSON.decoded(PerformanceMeasurementReport.self, from: candidateReportData)
        let artifact = try PerformanceCanonicalJSON.decoded(PerformancePairExecutionArtifact.self, from: artifactData)
        try baselineRun.validateStructure()
        try candidateRun.validateStructure()
        try require(baselineRun.configuration.fixtureProfile == profile && candidateRun.configuration.fixtureProfile == profile, "staged provenance profile does not match")
        try require(baselineRun.variant == PerformanceVariant.baseline.rawValue && candidateRun.variant == PerformanceVariant.candidate.rawValue, "staged provenance variants are invalid")
        try require(eligibility.baselineRoot == baselineRun.outputRoot && eligibility.candidateRoot == candidateRun.outputRoot, "staged eligibility roots do not bind to provenance")
        try require(eligibility.baselineCommitSHA == baselineRun.sourceRef && eligibility.candidateCommitSHA == candidateRun.sourceRef, "staged eligibility commits do not bind to provenance")
        try require(baselineReport.runProvenance == baselineRun && candidateReport.runProvenance == candidateRun, "staged measurements do not bind to provenance")
        try require(baselineReport.fixture.fixtureProfile == profile && candidateReport.fixture.fixtureProfile == profile, "staged measurement profile does not match")
        try require(baselineReport.runProvenance.variant == PerformanceVariant.baseline.rawValue && candidateReport.runProvenance.variant == PerformanceVariant.candidate.rawValue, "staged measurement variants are invalid")
        try baselineReport.validateStructure()
        try candidateReport.validateStructure()
        let baselineReportHash = sha256(baselineReportData)
        let candidateReportHash = sha256(candidateReportData)
        try artifact.validate(
            expectedBaselineID: baselineRun.sourceRef,
            expectedCandidateID: candidateRun.sourceRef,
            expectedBaselineReportHash: baselineReportHash,
            expectedCandidateReportHash: candidateReportHash,
            expectedArtifactHash: nil,
            pairCount: baselineRun.configuration.totalPairs
        )
        if nodeExists(root.appendingPathComponent("external", isDirectory: true)) {
            try validateStagedExternalEvidence(
                root: root,
                profile: profile,
                baselineRun: baselineRun,
                candidateRun: candidateRun,
                baselineRunProvenanceSHA256: sha256(baselineProvenanceData),
                candidateRunProvenanceSHA256: sha256(candidateProvenanceData),
                pairEligibilitySHA256: sha256(eligibilityData)
            )
        }
    }

    private static func validateStagedExternalEvidence(
        root: URL,
        profile: PerformanceFixtureProfile,
        baselineRun: PerformanceRunProvenance,
        candidateRun: PerformanceRunProvenance,
        baselineRunProvenanceSHA256: String,
        candidateRunProvenanceSHA256: String,
        pairEligibilitySHA256: String
    ) throws {
        let externalRoot = root.appendingPathComponent("external", isDirectory: true)
        try require(try childNames(externalRoot).isSubset(of: ["trials", "aggregate"]), "staged external topology is not exact")
        guard let enumerator = FileManager.default.enumerator(at: externalRoot, includingPropertiesForKeys: nil, options: []) else { return }
        for case let url as URL in enumerator {
            var info = stat()
            try require(lstat(url.path, &info) == 0, "staged external entry cannot be inspected")
            guard (info.st_mode & S_IFMT) == S_IFREG else { continue }
            guard let relative = relativePath(of: url, under: root) else {
                throw PerformanceValidationError.invalid("staged external evidence escaped its root")
            }
            let components = relative.split(separator: "/").map(String.init)
            let data = try Data(contentsOf: url)
            if components.count == 3, components[0] == "external", components[1] == "aggregate",
               components[2].hasSuffix(".json"),
               let variant = PerformanceVariant(rawValue: String(components[2].dropLast(5))) {
                let sidecar = try PerformanceCanonicalJSON.decoded(PerformanceExternalAggregateSidecar.self, from: data)
                try sidecar.validate()
                let run = variant == .baseline ? baselineRun : candidateRun
                let runHash = variant == .baseline ? baselineRunProvenanceSHA256 : candidateRunProvenanceSHA256
                try require(sidecar.binding.variant == variant && sidecar.binding.fixtureProfile == profile, "staged aggregate binding is invalid")
                try require(sidecar.binding.sourceIdentity == run.build.sourceIdentity && sidecar.binding.runProvenanceSHA256 == runHash && sidecar.binding.pairEligibilitySHA256 == pairEligibilitySHA256, "staged aggregate binding is stale")
                try require(data == PerformanceCanonicalJSON.data(for: sidecar), "staged aggregate is not canonical")
                continue
            }
            guard components.count == 4, components[0] == "external", components[1] == "trials",
                  let variant = PerformanceVariant(rawValue: components[2]), components[3].hasSuffix(".json"),
                  let index = Int(components[3].dropLast(5)), index >= 0, index < 30,
                  components[3] == "\(index).json"
            else {
                throw PerformanceValidationError.invalid("staged external path is not canonical")
            }
            let sidecar = try PerformanceCanonicalJSON.decoded(PerformanceExternalTrialSidecar.self, from: data)
            try sidecar.validate()
            let request = sidecar.binding.request
            let run = variant == .baseline ? baselineRun : candidateRun
            let runHash = variant == .baseline ? baselineRunProvenanceSHA256 : candidateRunProvenanceSHA256
            try require(request.fixtureProfile == profile && request.variant == variant && index == request.pairIndex && index == request.sampleIndex, "staged trial slot binding is invalid")
            try require(sidecar.binding.sourceIdentity == run.build.sourceIdentity && sidecar.binding.runProvenanceSHA256 == runHash && sidecar.binding.pairEligibilitySHA256 == pairEligibilitySHA256, "staged trial binding is stale")
            try require(data == PerformanceCanonicalJSON.data(for: sidecar), "staged trial sidecar is not canonical")
        }
    }

    private static func childNames(_ directory: URL) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).map(\.lastPathComponent))
    }

    private static func shouldInterruptPublish(_ phase: PerformancePublishPhase) -> Bool {
        publishPhaseHook?(phase) ?? false
    }

    private static func validateRegularFile(_ url: URL, label: String) throws {
        var info = stat()
        try require(lstat(url.path, &info) == 0, "\(label) cannot be inspected")
        try require((info.st_mode & S_IFMT) == S_IFREG, "\(label) must be a regular file")
    }

    private static func validatePhysicalTree(_ root: URL) throws {
        var info = stat()
        try require(lstat(root.path, &info) == 0, "finalize output cannot be inspected")
        try require((info.st_mode & S_IFMT) == S_IFDIR, "finalize output must be a directory")
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: []) else { return }
        for case let url as URL in enumerator {
            var entry = stat()
            try require(lstat(url.path, &entry) == 0, "finalize output entry cannot be inspected")
            let type = entry.st_mode & S_IFMT
            try require(type == S_IFDIR || type == S_IFREG, "finalize output contains a non-regular filesystem node")
        }
    }

    private static func validateBackupContainer(_ backup: URL) throws {
        let parent = backup.deletingLastPathComponent()
        try validatePhysicalTree(parent)
        let entries = try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
        try require(entries.count == 1 && entries.first.map { physicalPath($0) } == physicalPath(backup), "finalize backup container contains unexpected entries")
    }

    private static func validateEmptyDirectory(_ directory: URL, label: String) throws {
        try validatePhysicalTree(directory)
        try require(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).isEmpty, "\(label) contains unexpected entries")
    }

    private static func restoreBackup(_ backup: URL, to output: URL) throws -> Bool {
        let fileManager = FileManager.default
        try require(nodeExists(backup), "finalize backup is missing")
        if nodeExists(output) { try fileManager.removeItem(at: output) }
        try fileManager.moveItem(at: backup, to: output)
        try syncDirectory(output.deletingLastPathComponent())
        if shouldInterruptPublish(.restoredBackup) { return false }
        try removeBackupContainer(backup)
        try syncDirectory(output.deletingLastPathComponent())
        return true
    }

    private static func removeBackupContainer(_ backup: URL) throws {
        let parent = backup.deletingLastPathComponent()
        try validateEmptyDirectory(parent, label: "finalize backup container")
        try FileManager.default.removeItem(at: parent)
        try syncDirectory(parent.deletingLastPathComponent())
    }

    private static func discardBackup(_ backup: URL) throws -> Bool {
        try require(nodeExists(backup), "finalize backup is missing")
        try FileManager.default.removeItem(at: backup)
        try syncDirectory(backup.deletingLastPathComponent())
        if shouldInterruptPublish(.discardedBackup) { return false }
        try removeBackupContainer(backup)
        return true
    }

    private static func removeEmptyBackupContainer(_ backup: URL) throws {
        let parent = backup.deletingLastPathComponent()
        guard nodeExists(parent) else { return }
        try validateEmptyDirectory(parent, label: "finalize backup container")
        try FileManager.default.removeItem(at: parent)
        try syncDirectory(parent.deletingLastPathComponent())
    }

    private static func syncDirectory(_ directory: URL) throws {
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY)
        try require(descriptor >= 0, "finalize transaction directory cannot be opened")
        defer { close(descriptor) }
        try require(fsync(descriptor) == 0, "finalize transaction directory could not be synced")
    }

    private static func nodeExists(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0
    }

    private static func hasFinalizedOutputNodes(_ output: URL) -> Bool {
        ["measurements", "pair-execution"].contains { nodeExists(output.appendingPathComponent($0, isDirectory: true)) }
    }

    private static func mergeExternalEvidencePreseed(
        staging: URL,
        output: URL,
        profile: PerformanceFixtureProfile,
        baselineSourceIdentity: SourceIdentity,
        candidateSourceIdentity: SourceIdentity,
        baselineRunProvenanceSHA256: String,
        candidateRunProvenanceSHA256: String,
        pairEligibilitySHA256: String
    ) throws -> Bool {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: output, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
            return false
        }
        var files = Set<String>()
        for case let url as URL in enumerator {
            try rejectTraversalOrSymlink(url)
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard let type = attributes[.type] as? FileAttributeType else {
                throw PerformanceValidationError.invalid("external preseed has an unreadable filesystem node")
            }
            if type == .typeDirectory {
                continue
            }
            try require(type == .typeRegular, "external preseed must contain regular files")
            guard let relative = relativePath(of: url, under: output) else {
                throw PerformanceValidationError.invalid("external preseed escaped its root")
            }
            files.insert(relative)
        }
        let externalFiles = files.filter { $0.hasPrefix("external/") }
        guard !externalFiles.isEmpty else { return false }
        let finalizedFiles = Set([
            "comparisons/pair-eligibility.json",
            "provenance/baseline.json",
            "provenance/candidate.json",
            "measurements/baseline.json",
            "measurements/candidate.json",
            "pair-execution/pair-execution.json"
        ])
        for relative in files {
            let components = relative.split(separator: "/").map(String.init)
            if finalizedFiles.contains(relative) {
                continue
            }
            if components.count == 3, components[0] == "external", components[1] == "aggregate",
               components[2].hasSuffix(".json"),
               let variant = PerformanceVariant(rawValue: String(components[2].dropLast(5))) {
                let url = output.appendingPathComponent(relative)
                let data = try Data(contentsOf: url)
                let sidecar = try PerformanceCanonicalJSON.decoded(PerformanceExternalAggregateSidecar.self, from: data)
                try sidecar.validate()
                try require(sidecar.binding.fixtureProfile == profile && sidecar.binding.variant == variant, "external aggregate preseed binding is invalid")
                let expectedSourceIdentity = variant == .baseline ? baselineSourceIdentity : candidateSourceIdentity
                let expectedRunProvenanceSHA256 = variant == .baseline ? baselineRunProvenanceSHA256 : candidateRunProvenanceSHA256
                try require(sidecar.binding.sourceIdentity == expectedSourceIdentity, "external aggregate preseed source identity is stale")
                try require(sidecar.binding.runProvenanceSHA256 == expectedRunProvenanceSHA256, "external aggregate preseed provenance hash is stale")
                try require(sidecar.binding.pairEligibilitySHA256 == pairEligibilitySHA256, "external aggregate preseed eligibility hash is stale")
                try require(data == PerformanceCanonicalJSON.data(for: sidecar), "external aggregate preseed is not canonical")
                continue
            }
            guard components.count == 4, components[0] == "external", components[1] == "trials",
                  let variant = PerformanceVariant(rawValue: components[2]),
                  components[3].hasSuffix(".json"),
                  let index = Int(components[3].dropLast(5)), index >= 0, index < 30,
                  components[3] == "\(index).json"
            else {
                throw PerformanceValidationError.invalid("external preseed path is not canonical")
            }
            let url = output.appendingPathComponent(relative)
            let data = try Data(contentsOf: url)
            let sidecar = try PerformanceCanonicalJSON.decoded(PerformanceExternalTrialSidecar.self, from: data)
            try sidecar.validate()
            let request = sidecar.binding.request
            try require(request.fixtureProfile == profile && request.variant == variant, "external trial preseed binding is invalid")
            try require(index == request.pairIndex && index == request.sampleIndex, "external trial preseed slot does not match its filename")
            let expectedSourceIdentity = variant == .baseline ? baselineSourceIdentity : candidateSourceIdentity
            let expectedRunProvenanceSHA256 = variant == .baseline ? baselineRunProvenanceSHA256 : candidateRunProvenanceSHA256
            try require(sidecar.binding.sourceIdentity == expectedSourceIdentity, "external trial preseed source identity is stale")
            try require(sidecar.binding.runProvenanceSHA256 == expectedRunProvenanceSHA256, "external trial preseed provenance hash is stale")
            try require(sidecar.binding.pairEligibilitySHA256 == pairEligibilitySHA256, "external trial preseed eligibility hash is stale")
            try require(data == PerformanceCanonicalJSON.data(for: sidecar), "external trial preseed is not canonical")
        }
        for relative in externalFiles {
            let source = output.appendingPathComponent(relative)
            let destination = staging.appendingPathComponent(relative)
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
        }
        return true
    }

    private static func isScriptPreseedDirectory(_ output: URL) throws -> Bool {
        let parentName = output.deletingLastPathComponent().lastPathComponent
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: output, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
            return false
        }
        var files = Set<String>()
        for case let url as URL in enumerator {
            guard let relative = relativePath(of: url, under: output) else { return false }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory != true { files.insert(relative) }
        }
        let scriptPreseed = files == ["comparisons/pair-eligibility.json", "provenance/baseline.json", "provenance/candidate.json"]
            && parentName.hasPrefix(".benchmark-quality.pending.")
        return scriptPreseed || files == ["comparisons/pair-eligibility.json"]
    }

    private static func directoryContentsEqual(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let fileManager = FileManager.default
        func entries(_ root: URL) throws -> [String: Data] {
            guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
                return [:]
            }
            var result: [String: Data] = [:]
            for case let url as URL in enumerator {
                guard let relative = relativePath(of: url, under: root) else {
                    throw PerformanceValidationError.invalid("finalize output escaped its root")
                }
                let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                if values.isDirectory == true { continue }
                result[relative] = try Data(contentsOf: url)
            }
            return result
        }
        return try entries(lhs) == entries(rhs)
    }

    private static func relativePath(of url: URL, under root: URL) -> String? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let fileComponents = url.standardizedFileURL.pathComponents
        guard fileComponents.count >= rootComponents.count,
              Array(fileComponents.prefix(rootComponents.count)) == rootComponents
        else {
            return nil
        }
        return fileComponents.dropFirst(rootComponents.count).joined(separator: "/")
    }

    private static func runComparison(_ invocation: ComparisonInvocation) throws {
        let baselineData = try Data(contentsOf: invocation.baselineURL)
        let candidateData = try Data(contentsOf: invocation.candidateURL)
        let pairData = try Data(contentsOf: invocation.pairExecutionURL)
        var isDirectory: ObjCBool = false
        try require(FileManager.default.fileExists(atPath: invocation.manualEvidenceDirectory.path, isDirectory: &isDirectory) && isDirectory.boolValue, "manual evidence path must be an existing directory")
        let baseline = try JSONDecoder().decode(PerformanceMeasurementReport.self, from: baselineData)
        let candidate = try JSONDecoder().decode(PerformanceMeasurementReport.self, from: candidateData)
        let eligibility = try PerformanceCanonicalJSON.decoded(PerformancePairEligibility.self, from: Data(contentsOf: invocation.eligibilityURL))
        try require(baseline.runProvenance.configuration.fixtureProfile == invocation.profile && candidate.runProvenance.configuration.fixtureProfile == invocation.profile, "comparison fixture profile does not match CLI profile")
        try require(baseline.runProvenance.configuration == candidate.runProvenance.configuration, "comparison configurations do not match")
        let canonicalPairData = try PerformancePairExecutionArtifact.canonicalData(from: pairData)
        try require(pairData == canonicalPairData, "pair execution artifact bytes are not canonical")
        let pairArtifact = try JSONDecoder().decode(PerformancePairExecutionArtifact.self, from: pairData)
        let draft = try PerformanceComparisonHarness.compare(baseline: baseline, candidate: candidate, configuration: baseline.runProvenance.configuration, eligibility: eligibility, pairExecutionArtifact: pairArtifact, manualEvidenceDirectory: invocation.manualEvidenceDirectory, pairExecutionArtifactSHA256: sha256(pairData), baselineMeasurementReportSHA256: sha256(baselineData), candidateMeasurementReportSHA256: sha256(candidateData))
        _ = try PerformanceComparisonHarness.writeComparison(draft: draft, baselineURL: invocation.baselineURL, candidateURL: invocation.candidateURL, pairExecutionURL: invocation.pairExecutionURL, manualEvidenceDirectory: invocation.manualEvidenceDirectory, outputDirectory: invocation.outputDirectory, configuration: baseline.runProvenance.configuration, eligibility: eligibility)
    }

    private static func runCampaignComplete(_ invocation: CampaignCompletionInvocation, outputDirectory: URL) throws {
        try rejectTraversalOrSymlink(invocation.standard12ComparisonURL)
        try rejectTraversalOrSymlink(invocation.dense1000ComparisonURL)
        try rejectTraversalOrSymlink(invocation.outputURL)
        try PerformanceCampaignCompletion.validateSharedPerformanceRoot(
            standard12ComparisonURL: invocation.standard12ComparisonURL,
            dense1000ComparisonURL: invocation.dense1000ComparisonURL,
            outputURL: invocation.outputURL,
            outputDirectory: outputDirectory
        )
        _ = try PerformanceCampaignCompletion.writeManifest(
            standard12ComparisonURL: invocation.standard12ComparisonURL,
            dense1000ComparisonURL: invocation.dense1000ComparisonURL,
            outputURL: invocation.outputURL
        )
    }

    private static func loadCanonical<T: Codable>(_ type: T.Type, from url: URL) throws -> (T, String) {
        try rejectTraversalOrSymlink(url)
        let data = try Data(contentsOf: url)
        return (try PerformanceCanonicalJSON.decoded(type, from: data), sha256(data))
    }

    private static func validateRunEnvelope(_ run: PerformanceRunProvenance, profile: PerformanceFixtureProfile, variant: PerformanceVariant, sourceIdentity: SourceIdentity, repoRoot: URL) throws {
        try require(run.variant == variant.rawValue, "run provenance variant does not match CLI variant")
        try require(try resolveRepositoryPath(run.outputRoot, repoRoot: repoRoot).path == canonicalBuildRoot(repoRoot, profile: profile, variant: variant).path, "run output root is not the canonical build root")
        try require(run.configuration.isCanonical && run.configuration.fixtureProfile == profile && run.configuration.fixtureVersion == profile.version && run.configuration.fixtureMarkCount == profile.markCount, "run provenance fixture profile/configuration is invalid")
        try require(run.build.sourceIdentity == sourceIdentity, "run/build identity mismatch")
        try require(run.build.sourceTreeStatus == (sourceIdentity.kind == .sourceCommitSHA ? .clean : .dirty), "source identity/tree status mismatch")
        try require(sourceIdentity.value.isLowercaseHex(count: sourceIdentity.kind == .sourceCommitSHA ? 40 : 64), "source identity is invalid")
        if sourceIdentity.kind == .sourceCommitSHA {
            try require(run.sourceRef == sourceIdentity.value, "run source commit does not match selected identity")
        } else {
            try require(run.build.sourceManifestSHA256 == sourceIdentity.value, "content identity does not match source manifest")
            try require(run.sourceRef.isLowercaseHex(count: 40), "content diagnostic run must retain a canonical source commit")
        }
        try require(run.build.sourceManifestSHA256.isLowercaseHex(count: 64) && run.build.executableSHA256.isLowercaseHex(count: 64) && run.build.bundleManifestSHA256.isLowercaseHex(count: 64), "build hashes are invalid")
        try require(run.build.buildConfiguration == "release" || run.build.buildConfiguration == "debug", "build configuration is invalid")
        try require(!run.host.machineIdentifier.isEmpty && !run.host.processArchitecture.isEmpty && !run.host.connectedDisplayUUIDs.isEmpty, "host identity is incomplete")
        try validateUTC(run.recordedAtUTC)
        try validateUTC(run.build.recordedAtUTC)
        try require(run.foundation == run.build.foundation && run.foundation == run.configuration.foundationIdentity, "run/build foundation mismatch")
        try require(run.harnessVersion == run.build.harnessVersion && run.harnessVersion == run.configuration.harnessVersion, "run/build harness mismatch")
        try require(run.buildContractVersion == run.build.buildContractVersion && run.buildContractVersion == run.configuration.buildContractVersion, "run/build contract mismatch")
        try require(run.acceptedFoundationArtifactSHA256 == run.build.acceptedFoundationArtifactSHA256, "run/build foundation artifact mismatch")
        if let accepted = run.acceptedFoundationArtifactSHA256 {
            try require(accepted.isLowercaseHex(count: 64), "accepted foundation artifact hash is invalid")
        }
    }

    private static func validateEligibility(_ eligibility: PerformancePairEligibility, run: PerformanceRunProvenance, profile: PerformanceFixtureProfile, sourceIdentity: SourceIdentity, repoRoot: URL) throws {
        try require(!eligibility.baselineRoot.isEmpty && !eligibility.candidateRoot.isEmpty && eligibility.baselineRoot != eligibility.candidateRoot, "pair eligibility roots are invalid")
        try require(eligibility.baselineCommitSHA.isLowercaseHex(count: 40) && eligibility.candidateCommitSHA.isLowercaseHex(count: 40) && eligibility.baselineCommitSHA != eligibility.candidateCommitSHA, "pair eligibility commits are invalid")
        let expectedCommit = run.variant == "baseline" ? eligibility.baselineCommitSHA : eligibility.candidateCommitSHA
        let expectedRoot = run.variant == "baseline" ? eligibility.baselineRoot : eligibility.candidateRoot
        try require(run.sourceRef.isLowercaseHex(count: 40), "pair eligibility requires a canonical run source commit")
        let expectedVariant: PerformanceVariant
        switch run.variant {
        case PerformanceVariant.baseline.rawValue: expectedVariant = .baseline
        case PerformanceVariant.candidate.rawValue: expectedVariant = .candidate
        default: throw PerformanceValidationError.invalid("pair eligibility run variant is invalid")
        }
        let canonicalRoot = canonicalBuildRoot(repoRoot, profile: profile, variant: expectedVariant)
        try require(expectedCommit == run.sourceRef, "pair eligibility does not bind this run commit")
        try require(try resolveRepositoryPath(expectedRoot, repoRoot: repoRoot).path == canonicalRoot.path, "pair eligibility root is not the canonical build root")
        try require(try resolveRepositoryPath(run.outputRoot, repoRoot: repoRoot).path == canonicalRoot.path, "run output root is not the canonical build root")
        if sourceIdentity.kind == .contentManifestSHA256 {
            try require(run.build.sourceManifestSHA256 == sourceIdentity.value, "pair eligibility content identity does not match source manifest")
        } else {
            try require(run.build.sourceIdentity == sourceIdentity, "pair eligibility source commit identity does not match build")
        }
        try require(eligibility.foundationProvenance.foundation == run.foundation && eligibility.foundationProvenance.path == run.foundationProvenancePath, "eligibility foundation mismatch")
        try require(eligibility.foundationProvenance.checkpointCommitSHA.isLowercaseHex(count: 40) && eligibility.foundationProvenance.fullSourceManifestSHA256.isLowercaseHex(count: 64), "eligibility foundation hashes are invalid")
        try require(eligibility.foundationProvenance.harnessVersion == run.harnessVersion && eligibility.foundationProvenance.buildContractVersion == run.buildContractVersion, "eligibility contract mismatch")
    }

    private static func validateEligibilityPair(_ eligibility: PerformancePairEligibility, baseline: PerformanceRunProvenance, candidate: PerformanceRunProvenance, profile: PerformanceFixtureProfile, repoRoot: URL) throws {
        try validateEligibility(eligibility, run: baseline, profile: profile, sourceIdentity: baseline.build.sourceIdentity, repoRoot: repoRoot)
        try validateEligibility(eligibility, run: candidate, profile: profile, sourceIdentity: candidate.build.sourceIdentity, repoRoot: repoRoot)
    }

    private static func validateTrialPathContext(
        profile: PerformanceFixtureProfile,
        variant: PerformanceVariant,
        pairIndex: Int,
        partialDirectory: URL,
        runProvenanceURL: URL,
        pairEligibilityURL: URL,
        externalTrialSidecarURL: URL?
    ) throws {
        let root = try repositoryRoot(for: pairEligibilityURL, profile: profile, kind: .eligibility)
        try require(repositoryRoot(for: partialDirectory, profile: profile, kind: .partial) == root, "trial paths do not share one repository root")
        try validatePartialDirectory(partialDirectory, profile: profile, repoRoot: root)
        try validateEligibilityPath(pairEligibilityURL, profile: profile, repoRoot: root)
        try validateRunProvenancePath(runProvenanceURL, profile: profile, variant: variant, repoRoot: root)
        if let externalTrialSidecarURL {
            try validateTrialExternalSidecarPath(externalTrialSidecarURL, profile: profile, variant: variant, pairIndex: pairIndex, repoRoot: root)
        }
    }

    private static func validateFinalizePathContext(
        profile: PerformanceFixtureProfile,
        partialDirectory: URL,
        baselineRunProvenanceURL: URL,
        candidateRunProvenanceURL: URL,
        pairEligibilityURL: URL,
        baselineExternalAggregateURL: URL?,
        candidateExternalAggregateURL: URL?,
        outputDirectory: URL
    ) throws {
        let root = try repositoryRoot(for: pairEligibilityURL, profile: profile, kind: .eligibility)
        try require(repositoryRoot(for: partialDirectory, profile: profile, kind: .partial) == root, "finalize paths do not share one repository root")
        try validatePartialDirectory(partialDirectory, profile: profile, repoRoot: root)
        try validateEligibilityPath(pairEligibilityURL, profile: profile, repoRoot: root)
        try validateRunProvenancePath(baselineRunProvenanceURL, profile: profile, variant: .baseline, repoRoot: root)
        try validateRunProvenancePath(candidateRunProvenanceURL, profile: profile, variant: .candidate, repoRoot: root)
        if let baselineExternalAggregateURL {
            try validateAggregateExternalSidecarPath(baselineExternalAggregateURL, profile: profile, variant: .baseline, repoRoot: root)
        }
        if let candidateExternalAggregateURL {
            try validateAggregateExternalSidecarPath(candidateExternalAggregateURL, profile: profile, variant: .candidate, repoRoot: root)
        }
        try validateEvidenceOutputPath(outputDirectory, profile: profile, repoRoot: root)
    }

    private static func validateComparisonPaths(profile: PerformanceFixtureProfile, baselineURL: URL, candidateURL: URL, eligibilityURL: URL, pairExecutionURL: URL, manualEvidenceDirectory: URL, outputDirectory: URL) throws {
        for url in [baselineURL, candidateURL, eligibilityURL, pairExecutionURL, manualEvidenceDirectory, outputDirectory] {
            try rejectTraversalOrSymlink(url)
        }
        let root = try performanceRepositoryRoot(for: baselineURL)
        let expected: [(URL, String)] = [
            (baselineURL, ".codex/sdd/reports/quality-campaign/performance/\(profile.rawValue)/measurements/baseline.json"),
            (candidateURL, ".codex/sdd/reports/quality-campaign/performance/\(profile.rawValue)/measurements/candidate.json"),
            (eligibilityURL, ".codex/sdd/reports/quality-campaign/performance/\(profile.rawValue)/comparisons/pair-eligibility.json"),
            (pairExecutionURL, ".codex/sdd/reports/quality-campaign/performance/\(profile.rawValue)/pair-execution/pair-execution.json"),
            (manualEvidenceDirectory, ".codex/sdd/reports/quality-campaign/performance/\(profile.rawValue)/comparisons/manual"),
            (outputDirectory, ".codex/sdd/reports/quality-campaign/performance/\(profile.rawValue)/comparisons")
        ]
        for (url, relativePath) in expected {
            try require(url.standardizedFileURL.path == root.appendingPathComponent(relativePath).standardizedFileURL.path, "comparison path is not canonical for the selected profile")
        }
    }

    private enum ProfilePathKind {
        case partial
        case eligibility
    }

    private static func repositoryRoot(for url: URL, profile: PerformanceFixtureProfile, kind: ProfilePathKind) throws -> URL {
        let components = url.standardizedFileURL.pathComponents
        switch kind {
        case .partial:
            let suffix = ["build", profile.rawValue, "pair-execution", "partial"]
            guard Array(components.suffix(suffix.count)) == suffix,
                  let buildIndex = components.lastIndex(of: "build"), buildIndex > 1
            else { throw error("partial directory is not the canonical repository build path") }
            return rootURL(from: components, before: buildIndex)
        case .eligibility:
            let suffix = [".codex", "sdd", "reports", "quality-campaign", "performance", profile.rawValue, "comparisons", "pair-eligibility.json"]
            guard Array(components.suffix(suffix.count)) == suffix,
                  let codexIndex = components.lastIndex(of: ".codex"), codexIndex > 1
            else { throw error("pair eligibility is not the canonical repository evidence path") }
            return rootURL(from: components, before: codexIndex)
        }
    }

    private static func performanceRepositoryRoot(for url: URL) throws -> URL {
        let components = url.standardizedFileURL.pathComponents
        let codexIndices = components.indices.filter { components[$0] == ".codex" }
        try require(codexIndices.count == 1, "comparison paths must contain one .codex component")
        guard let codexIndex = codexIndices.first, codexIndex > 1 else {
            throw error("comparison path is not nested under a repository root")
        }
        return rootURL(from: components, before: codexIndex)
    }

    private static func rootURL(from components: [String], before index: Int) -> URL {
        var root = URL(fileURLWithPath: "/", isDirectory: true)
        for component in components.dropFirst().prefix(index - 1) {
            root.appendPathComponent(component)
        }
        return root.standardizedFileURL
    }

    private static func validatePartialDirectory(_ url: URL, profile: PerformanceFixtureProfile, repoRoot: URL) throws {
        let expected = canonicalPartialDirectory(repoRoot, profile: profile)
        try require(url.standardizedFileURL.path == expected.path, "partial directory is not canonical for the repository and profile")
        try require(physicalPath(url) == physicalPath(expected), "partial directory is not physically contained in the repository build tree")
        try validateDirectoryChain(url)
    }

    private static func validateEligibilityPath(_ url: URL, profile: PerformanceFixtureProfile, repoRoot: URL) throws {
        try require(url.standardizedFileURL.path == canonicalEligibilityPath(repoRoot, profile: profile).path, "pair eligibility path is not canonical for the repository and profile")
    }

    private static func validateRunProvenancePath(_ url: URL, profile: PerformanceFixtureProfile, variant: PerformanceVariant, repoRoot: URL) throws {
        try require(url.standardizedFileURL.path == canonicalProvenancePath(repoRoot, profile: profile, variant: variant).path, "run provenance path is not canonical for the repository, profile, and variant")
    }

    private static func validateTrialExternalSidecarPath(_ url: URL, profile: PerformanceFixtureProfile, variant: PerformanceVariant, pairIndex: Int, repoRoot: URL) throws {
        let expected = canonicalTrialExternalSidecarPath(repoRoot, profile: profile, variant: variant, pairIndex: pairIndex)
        try require(url.standardizedFileURL.path == expected.path, "external trial sidecar path is not canonical for the repository, profile, variant, and pair index")
    }

    private static func validateAggregateExternalSidecarPath(_ url: URL, profile: PerformanceFixtureProfile, variant: PerformanceVariant, repoRoot: URL) throws {
        let expected = canonicalAggregateExternalSidecarPath(repoRoot, profile: profile, variant: variant)
        try require(url.standardizedFileURL.path == expected.path, "external aggregate sidecar path is not canonical for the repository, profile, and variant")
    }

    private static func validateEvidenceOutputPath(_ url: URL, profile: PerformanceFixtureProfile, repoRoot: URL) throws {
        let final = canonicalProfileRoot(repoRoot, profile: profile)
        let pending = canonicalPendingProfileRoot(repoRoot, profile: profile)
        let path = url.standardizedFileURL.path
        try require(path == final.path || path == pending.path, "output directory is not canonical for the repository and profile")
    }

    private static func canonicalBuildRoot(_ repoRoot: URL, profile: PerformanceFixtureProfile, variant: PerformanceVariant) -> URL {
        repoRoot.appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent(profile.rawValue, isDirectory: true)
            .appendingPathComponent(variant.rawValue, isDirectory: true)
            .standardizedFileURL
    }

    private static func canonicalPartialDirectory(_ repoRoot: URL, profile: PerformanceFixtureProfile) -> URL {
        repoRoot.appendingPathComponent("build", isDirectory: true)
            .appendingPathComponent(profile.rawValue, isDirectory: true)
            .appendingPathComponent("pair-execution", isDirectory: true)
            .appendingPathComponent("partial", isDirectory: true)
            .standardizedFileURL
    }

    private static func canonicalEligibilityPath(_ repoRoot: URL, profile: PerformanceFixtureProfile) -> URL {
        canonicalProfileRoot(repoRoot, profile: profile)
            .appendingPathComponent("comparisons", isDirectory: true)
            .appendingPathComponent("pair-eligibility.json")
            .standardizedFileURL
    }

    private static func canonicalProvenancePath(_ repoRoot: URL, profile: PerformanceFixtureProfile, variant: PerformanceVariant) -> URL {
        canonicalBuildRoot(repoRoot, profile: profile, variant: variant)
            .appendingPathComponent("provenance.json")
            .standardizedFileURL
    }

    private static func canonicalProfileRoot(_ repoRoot: URL, profile: PerformanceFixtureProfile) -> URL {
        repoRoot.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance", isDirectory: true)
            .appendingPathComponent(profile.rawValue, isDirectory: true)
            .standardizedFileURL
    }

    private static func canonicalPendingProfileRoot(_ repoRoot: URL, profile: PerformanceFixtureProfile) -> URL {
        let performanceRoot = repoRoot.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance", isDirectory: true)
        return performanceRoot.appendingPathComponent(".benchmark-quality.pending.\(profile.rawValue)", isDirectory: true)
            .appendingPathComponent(profile.rawValue, isDirectory: true)
            .standardizedFileURL
    }

    private static func canonicalTrialExternalSidecarPath(_ repoRoot: URL, profile: PerformanceFixtureProfile, variant: PerformanceVariant, pairIndex: Int) -> URL {
        canonicalProfileRoot(repoRoot, profile: profile)
            .appendingPathComponent("external/trials", isDirectory: true)
            .appendingPathComponent(variant.rawValue, isDirectory: true)
            .appendingPathComponent("\(pairIndex).json")
            .standardizedFileURL
    }

    private static func canonicalAggregateExternalSidecarPath(_ repoRoot: URL, profile: PerformanceFixtureProfile, variant: PerformanceVariant) -> URL {
        canonicalProfileRoot(repoRoot, profile: profile)
            .appendingPathComponent("external/aggregate", isDirectory: true)
            .appendingPathComponent("\(variant.rawValue).json")
            .standardizedFileURL
    }

    private static func resolveRepositoryPath(_ value: String, repoRoot: URL) throws -> URL {
        _ = repoRoot
        try require(value.hasPrefix("/") && !value.isEmpty && !value.hasPrefix("//") && !value.hasSuffix("/") && !value.contains("//"), "repository path must be a canonical absolute path")
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        try require(components.dropFirst().allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }, "repository path contains a traversal or dot component")
        let rawURL = URL(fileURLWithPath: value)
        try require(rawURL.path == value, "absolute repository path is not canonically spelled")
        return rawURL.standardizedFileURL
    }

    private static func physicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func validateDirectoryChain(_ url: URL) throws {
        var current = URL(fileURLWithPath: "/")
        for component in url.standardizedFileURL.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            var info = stat()
            guard lstat(current.path, &info) == 0 else { break }
            let type = info.st_mode & S_IFMT
            if type == S_IFLNK {
                let allowedSystemAlias = current.path == "/var" || current.path == "/tmp"
                try require(allowedSystemAlias, "partial directory path contains a symbolic-link component")
                continue
            }
            try require(type == S_IFDIR, "partial directory path contains a non-directory component")
        }
    }

    private static func rejectTraversalOrSymlink(_ url: URL) throws {
        try require(!url.pathComponents.contains(".."), "path traversal is not allowed")
        var current = URL(fileURLWithPath: "/")
        for component in url.standardizedFileURL.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            guard FileManager.default.fileExists(atPath: current.path) else { continue }
            let attributes = try FileManager.default.attributesOfItem(atPath: current.path)
            let isSystemTemporaryAlias = current.path == "/var" || current.path == "/tmp"
            try require(
                isSystemTemporaryAlias || attributes[.type] as? FileAttributeType != .typeSymbolicLink,
                "symbolic-link paths are not allowed"
            )
        }
    }

    private static func measurementIdentity(for run: PerformanceRunProvenance) -> MeasurementIdentity {
        let environment = ProcessInfo.processInfo.environment
        return MeasurementIdentity(sourceCommitSHA: run.build.sourceTreeStatus == .clean ? run.sourceRef : nil, contentManifestSHA256: run.build.sourceTreeStatus == .dirty ? run.build.sourceManifestSHA256 : nil, hostModel: run.host.machineIdentifier, macOSVersion: ProcessInfo.processInfo.operatingSystemVersionString, xcodeVersion: environment["POINTER_XCODE_VERSION"] ?? "unavailable", developerDirectory: environment["DEVELOPER_DIR"] ?? "unavailable", powerState: environment["POINTER_POWER_STATE"] ?? "unavailable", displayState: run.host.connectedDisplayUUIDs.sorted().joined(separator: ","), buildConfiguration: run.build.buildConfiguration)
    }

    private static func validateUTC(_ value: String) throws {
        try require(value.hasSuffix("Z") && PerformanceTimestamp.date(from: value) != nil, "timestamp must be UTC ISO-8601")
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw PerformanceValidationError.invalid(message) }
    }

    private static func error(_ message: String) -> PerformanceValidationError {
        .invalid(message)
    }
}

private enum QualityCommand {
    case performance
    case compare
    case campaignComplete
}

@MainActor
private struct ArgumentParser {
    private let arguments: [String]
    private var index = 0
    private var seen = Set<String>()

    init(arguments: [String]) { self.arguments = arguments }

    mutating func consumeFlag(_ flag: String) -> Bool {
        guard index < arguments.count, arguments[index] == flag else { return false }
        index += 1
        seen.insert(flag)
        return true
    }

    mutating func requireValue(_ flag: String) throws -> String {
        guard index < arguments.count, arguments[index] == flag else { throw PerformanceValidationError.invalid("missing \(flag)") }
        try markSeen(flag)
        index += 1
        guard index < arguments.count, !arguments[index].hasPrefix("--") else { throw PerformanceValidationError.invalid("\(flag) requires a value") }
        let value = arguments[index]
        index += 1
        return value
    }

    mutating func requireValue(_ flag: String, equals expected: String) throws {
        let value = try requireValue(flag)
        guard value == expected else { throw PerformanceValidationError.invalid("\(flag) must be \(expected)") }
    }

    mutating func requireURL(_ flag: String) throws -> URL {
        let rawValue = try requireValue(flag)
        try requireCanonicalAbsolutePath(rawValue, flag: flag)
        return URL(fileURLWithPath: rawValue)
    }

    mutating func consumeOptionalURL(_ flag: String) throws -> URL? {
        guard index < arguments.count, arguments[index] == flag else { return nil }
        return try requireURL(flag)
    }

    mutating func requireInt(_ flag: String) throws -> Int {
        guard let value = Int(try requireValue(flag)) else { throw PerformanceValidationError.invalid("\(flag) must be an integer") }
        return value
    }

    mutating func requireOperation() throws -> PerformanceOperation {
        guard let operation = PerformanceOperation(rawValue: try requireValue("--operation")) else { throw PerformanceValidationError.invalid("--operation must be trial or finalize") }
        return operation
    }

    mutating func requireProfile() throws -> PerformanceFixtureProfile {
        guard let profile = PerformanceFixtureProfile(rawValue: try requireValue("--fixture-profile")) else { throw PerformanceValidationError.invalid("--fixture-profile must be standard12 or dense1000") }
        return profile
    }

    mutating func requireVariant() throws -> PerformanceVariant {
        guard let variant = PerformanceVariant(rawValue: try requireValue("--variant")) else { throw PerformanceValidationError.invalid("--variant must be baseline or candidate") }
        return variant
    }

    mutating func requirePairOrder() throws -> PairOrder {
        guard let order = PairOrder(rawValue: try requireValue("--pair-order")) else { throw PerformanceValidationError.invalid("--pair-order must be baselineFirst or candidateFirst") }
        return order
    }

    mutating func requireSourceIdentity() throws -> SourceIdentity {
        let flag = index < arguments.count ? arguments[index] : ""
        switch flag {
        case "--source-commit-sha":
            let value = try requireValue(flag)
            guard value.isLowercaseHex(count: 40) else { throw PerformanceValidationError.invalid("--source-commit-sha must be lowercase 40-hex") }
            if index < arguments.count, arguments[index] == "--content-manifest-sha256" { throw PerformanceValidationError.invalid("exactly one source identity flag is allowed") }
            return SourceIdentity(kind: .sourceCommitSHA, value: value)
        case "--content-manifest-sha256":
            let value = try requireValue(flag)
            guard value.isLowercaseHex(count: 64) else { throw PerformanceValidationError.invalid("--content-manifest-sha256 must be lowercase 64-hex") }
            if index < arguments.count, arguments[index] == "--source-commit-sha" { throw PerformanceValidationError.invalid("exactly one source identity flag is allowed") }
            return SourceIdentity(kind: .contentManifestSHA256, value: value)
        default:
            throw PerformanceValidationError.invalid("exactly one source identity flag is required")
        }
    }

    mutating func requireEnd() throws {
        guard index == arguments.count else { throw PerformanceValidationError.invalid("unexpected argument \(arguments[index])") }
    }

    private mutating func markSeen(_ flag: String) throws {
        guard seen.insert(flag).inserted else { throw PerformanceValidationError.invalid("duplicate \(flag)") }
    }

    private func requireCanonicalAbsolutePath(_ value: String, flag: String) throws {
        guard value.hasPrefix("/"), value.count > 1 else {
            throw PerformanceValidationError.invalid("\(flag) requires a canonical absolute path")
        }
        guard !value.hasPrefix("//"), !value.hasSuffix("/"), !value.contains("//") else {
            throw PerformanceValidationError.invalid("\(flag) contains a noncanonical path alias")
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard components.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw PerformanceValidationError.invalid("\(flag) contains a traversal or dot path component")
        }
        let url = URL(fileURLWithPath: value)
        guard url.path == value else {
            throw PerformanceValidationError.invalid("\(flag) is not canonically spelled")
        }
    }
}

private enum PerformanceOperation: String {
    case trial
    case finalize
}

private extension String {
    func isLowercaseHex(count: Int) -> Bool {
        guard self.count == count else { return false }
        return unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdef").contains($0) }
    }
}
