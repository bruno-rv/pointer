import Foundation
import Darwin
import XCTest
@testable import PointerAppKit

@MainActor
final class BenchmarkQualityScriptTests: XCTestCase {
    func testFakeRunnerReceivesExactInterleavedDiagnosticProtocolAndForwardsReruns() throws {
        let fixture = try TestFixture()
        defer { fixture.remove() }

        let firstRun = try fixture.run()
        XCTAssertEqual(firstRun.status, 0, firstRun.output)

        let firstInvocations = try fixture.invocations()
        XCTAssertEqual(firstInvocations.filter(\.isTrial).count, 60)
        XCTAssertEqual(firstInvocations.filter(\.isFinalize).count, 1)
        XCTAssertEqual(firstInvocations.filter(\.isCompare).count, 0)
        XCTAssertEqual(firstInvocations.count, 61)
        let recordedFinalizeOutputForParse = try XCTUnwrap(firstInvocations.first(where: \.isFinalize)?.outputDirectoryURL)
        try FileManager.default.createDirectory(at: recordedFinalizeOutputForParse, withIntermediateDirectories: true)

        let trials = firstInvocations.filter(\.isTrial)
        let expectedPairIndices = (0..<15).flatMap { [$0, $0] } + (15..<30).flatMap { [$0, $0] }
        XCTAssertEqual(trials.map { $0.pairIndex ?? -1 }, expectedPairIndices)
        XCTAssertEqual(trials.map(\.pairOrder), Array(repeating: "baselineFirst", count: 30) + Array(repeating: "candidateFirst", count: 30))
        XCTAssertTrue(trials.allSatisfy { $0.fixtureProfile == "standard12" })
        XCTAssertTrue(trials.allSatisfy { $0.operation == "trial" })
        XCTAssertEqual(
            trials.map(\.pairLabel),
            (0..<15).flatMap { ["\($0):baseline", "\($0):candidate"] }
                + (15..<30).flatMap { ["\($0):candidate", "\($0):baseline"] }
        )
        XCTAssertTrue(trials.allSatisfy { $0.partialName == $0.expectedPartialName })
        XCTAssertTrue(trials.allSatisfy { !$0.arguments.contains("--trial-request") && !$0.arguments.contains("--output-dir") })
        XCTAssertTrue(trials.allSatisfy { invocation in
            let expectedExecutable = invocation.variant == "baseline" ? fixture.baselineExecutable.path : fixture.candidateExecutable.path
            return invocation.executable == expectedExecutable
        })

        for trial in trials {
            XCTAssertEqual(trial.cliArguments, fixture.expectedTrialArguments(for: trial))
        }
        for invocation in firstInvocations {
            let parserOutput = invocation.isFinalize ? invocation.outputDirectoryURL : fixture.profileEvidence
            XCTAssertNoThrow(try invocation.parse(outputDirectory: parserOutput), "recorded argv: \(invocation.arguments)")
        }
        try FileManager.default.removeItem(at: recordedFinalizeOutputForParse.deletingLastPathComponent())

        let finalize = try XCTUnwrap(firstInvocations.first(where: \.isFinalize))
        XCTAssertEqual(finalize.fixtureProfile, "standard12")
        XCTAssertNil(finalize.pairIndex)
        XCTAssertEqual(finalize.executable, fixture.candidateExecutable.path)
        XCTAssertEqual(finalize.cliArguments, fixture.expectedFinalizeArguments(for: finalize))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileEvidence.appendingPathComponent("measurements/baseline.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileEvidence.appendingPathComponent("measurements/candidate.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileEvidence.appendingPathComponent("pair-execution/pair-execution.json").path))
        XCTAssertEqual(try Data(contentsOf: fixture.profileEvidence.appendingPathComponent("provenance/baseline.json")), try Data(contentsOf: fixture.baselineProvenance))
        XCTAssertEqual(try Data(contentsOf: fixture.profileEvidence.appendingPathComponent("provenance/candidate.json")), try Data(contentsOf: fixture.candidateProvenance))
        XCTAssertEqual(try Data(contentsOf: fixture.profileEvidence.appendingPathComponent("comparisons/pair-eligibility.json")), try Data(contentsOf: fixture.pairEligibility))

        let secondRun = try fixture.run()
        XCTAssertEqual(secondRun.status, 0, secondRun.output)
        let allInvocations = try fixture.invocations()
        let secondTrials = Array(allInvocations.filter(\.isTrial).dropFirst(60))
        XCTAssertEqual(secondTrials.count, 60)
        XCTAssertEqual(
            secondTrials.map(\.cliArguments),
            trials.map(\.cliArguments),
            "reruns must forward the same pair indices, orders, profiles, and partial-store paths"
        )
        XCTAssertEqual(allInvocations.filter(\.isFinalize).count, 2)
        XCTAssertEqual(allInvocations.filter(\.isCompare).count, 0)
        XCTAssertTrue(
            fixture.partialPaths().allSatisfy { FileManager.default.fileExists(atPath: $0.path) },
            "the CLI-owned partial store must survive a restart"
        )
    }

    func testRunnerFailureStopsBeforeFinalizeAndLeavesExistingEvidenceByteIdentical() throws {
        let fixture = try TestFixture(failAtInvocation: 17, existingEvidence: true)
        defer { fixture.remove() }

        let before = try fixture.evidenceBytes()

        let result = try fixture.run()
        XCTAssertNotEqual(result.status, 0, result.output)

        let invocations = try fixture.invocations()
        XCTAssertEqual(invocations.count, 17)
        XCTAssertNil(invocations.first(where: \.isFinalize))
        XCTAssertNil(invocations.first(where: \.isCompare))
        XCTAssertEqual(try fixture.evidenceBytes(), before)
    }

    func testAuthoritativeOrCompareModeIsRejectedBeforeAnyRunnerCall() throws {
        let fixture = try TestFixture(existingEvidence: true)
        defer { fixture.remove() }

        let before = try fixture.evidenceBytes()
        let result = try fixture.run(extraArguments: ["--authoritative"])
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(try fixture.invocations().isEmpty)
        XCTAssertEqual(try fixture.evidenceBytes(), before)
    }

    func testMissingRunProvenanceAndRemovedPreFFlagsRejectBeforeRunner() throws {
        let missing = try TestFixture()
        defer { missing.remove() }
        let missingResult = try missing.run(omitRunProvenance: "baseline")
        XCTAssertNotEqual(missingResult.status, 0, missingResult.output)
        XCTAssertTrue(try missing.invocations().isEmpty)

        for removedFlag in ["--foundation-provenance", "--manual-evidence-dir"] {
            let fixture = try TestFixture()
            defer { fixture.remove() }
            let result = try fixture.run(extraArguments: [removedFlag, "not-accepted"])
            XCTAssertNotEqual(result.status, 0, "removed flag unexpectedly accepted: \(removedFlag)")
            XCTAssertTrue(try fixture.invocations().isEmpty)
        }
    }

    func testInterruptedPublishRestoresExistingEvidence() throws {
        let fixture = try TestFixture()
        defer { fixture.remove() }

        let before = try fixture.profileFileBytes()
        let result = try fixture.run(extraArguments: ["--publish-hook", fixture.publishHook.path])
        XCTAssertEqual(result.status, 143, result.output)
        XCTAssertEqual(try String(contentsOf: fixture.publishMarker, encoding: .utf8), "reached\n")
        XCTAssertEqual(try fixture.profileFileBytes(), before)
        XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.appendingPathExtension("tmp").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
        XCTAssertEqual(try fixture.invocations().filter(\.isTrial).count, 60)
        XCTAssertEqual(try fixture.invocations().filter(\.isFinalize).count, 1)
        XCTAssertEqual(try fixture.invocations().filter(\.isCompare).count, 0)
    }

    func testInterruptedPostRenamePublishRemovesNewEvidenceAndRestoresExistingEvidence() throws {
        let fixture = try TestFixture()
        defer { fixture.remove() }

        let before = try fixture.profileFileBytes()
        let result = try fixture.run(extraArguments: ["--post-rename-publish-hook", fixture.postRenamePublishHook.path])
        XCTAssertEqual(result.status, 143, result.output)
        XCTAssertEqual(try String(contentsOf: fixture.postRenamePublishMarker, encoding: .utf8), "reached\n", result.output)
        XCTAssertEqual(try fixture.profileFileBytes(), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.postRenameOutputMarker.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileEvidence.appendingPathComponent("measurements").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileEvidence.appendingPathComponent("pair-execution").path))
        XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.appendingPathExtension("tmp").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testSymlinkedDefaultBuildInputsAreRejectedBeforeAnyRunnerCall() throws {
        let physicalDefaultFixture = try TestFixture()
        defer { physicalDefaultFixture.remove() }
        let physicalDefaultResult = try physicalDefaultFixture.run(useDefaultBuildInputs: true)
        XCTAssertEqual(physicalDefaultResult.status, 0, physicalDefaultResult.output)
        let defaultInvocations = try physicalDefaultFixture.invocations()
        XCTAssertEqual(defaultInvocations.count, 61)
        XCTAssertTrue(defaultInvocations.filter(\.isTrial).allSatisfy { invocation in
            let expectedExecutable = invocation.variant == "baseline"
                ? physicalDefaultFixture.baselineExecutable.path
                : physicalDefaultFixture.candidateExecutable.path
            return invocation.executable == expectedExecutable
        })
        XCTAssertEqual(
            defaultInvocations.first(where: \.isFinalize)?.executable,
            physicalDefaultFixture.candidateExecutable.path
        )

        let executableFixture = try TestFixture()
        defer { executableFixture.remove() }
        try executableFixture.replaceBaselineExecutableWithSymlink()
        let executableResult = try executableFixture.run(useDefaultBuildInputs: true)
        XCTAssertNotEqual(executableResult.status, 0, executableResult.output)
        XCTAssertTrue(executableResult.output.contains("baseline executable must not be a symlink"), executableResult.output)
        XCTAssertTrue(try executableFixture.invocations().isEmpty)

        let provenanceFixture = try TestFixture()
        defer { provenanceFixture.remove() }
        try provenanceFixture.replaceBaselineProvenanceWithSymlink()
        let provenanceResult = try provenanceFixture.run(useDefaultBuildInputs: true)
        XCTAssertNotEqual(provenanceResult.status, 0, provenanceResult.output)
        XCTAssertTrue(provenanceResult.output.contains("baseline run provenance must not be a symlink"), provenanceResult.output)
        XCTAssertTrue(try provenanceFixture.invocations().isEmpty)
    }

    func testRecordedFinalizeArgvReplaysThroughRealCLIWithCanonicalPartialsAndAtomicPreseed() throws {
        let fixture = try TestFixture()
        defer { fixture.remove() }

        let scriptResult = try fixture.run()
        XCTAssertEqual(scriptResult.status, 0, scriptResult.output)
        let finalize = try XCTUnwrap(try fixture.invocations().first(where: \.isFinalize))
        let recordedFinalizeOutput = finalize.outputDirectoryURL
        XCTAssertTrue(recordedFinalizeOutput.path.contains(".benchmark-quality.pending."))
        let expectedPendingOutput = fixture.profileEvidence.deletingLastPathComponent()
            .appendingPathComponent(".benchmark-quality.pending.standard12/standard12")
        XCTAssertEqual(recordedFinalizeOutput.standardizedFileURL.path, expectedPendingOutput.standardizedFileURL.path)
        let finalizeOutput = recordedFinalizeOutput
        try FileManager.default.createDirectory(at: finalizeOutput, withIntermediateDirectories: true)
        try fixture.installCanonicalFinalizeInputs()
        try fixture.writeCanonicalPreseed(at: finalizeOutput)

        try PerformanceCLI.run(arguments: finalize.cliArguments, outputDirectory: finalizeOutput)
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalizeOutput.appendingPathComponent("measurements/baseline.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalizeOutput.appendingPathComponent("measurements/candidate.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: finalizeOutput.appendingPathComponent("pair-execution/pair-execution.json").path))
        XCTAssertEqual(try fixture.canonicalOutputFileNames(at: finalizeOutput), [
            "comparisons/pair-eligibility.json",
            "measurements/baseline.json",
            "measurements/candidate.json",
            "pair-execution/pair-execution.json",
            "provenance/baseline.json",
            "provenance/candidate.json"
        ])
        XCTAssertEqual(
            try Data(contentsOf: finalizeOutput.appendingPathComponent("comparisons/pair-eligibility.json")),
            try Data(contentsOf: fixture.pairEligibility)
        )
        XCTAssertEqual(
            try Data(contentsOf: finalizeOutput.appendingPathComponent("provenance/baseline.json")),
            try Data(contentsOf: fixture.baselineProvenance)
        )
        XCTAssertEqual(
            try Data(contentsOf: finalizeOutput.appendingPathComponent("provenance/candidate.json")),
            try Data(contentsOf: fixture.candidateProvenance)
        )
        let baselineReport = try PerformanceCanonicalJSON.decoded(
            PerformanceMeasurementReport.self,
            from: Data(contentsOf: finalizeOutput.appendingPathComponent("measurements/baseline.json"))
        )
        let candidateReport = try PerformanceCanonicalJSON.decoded(
            PerformanceMeasurementReport.self,
            from: Data(contentsOf: finalizeOutput.appendingPathComponent("measurements/candidate.json"))
        )
        XCTAssertEqual(baselineReport.runProvenance.outputRoot, fixture.baselineRoot.path)
        XCTAssertEqual(candidateReport.runProvenance.outputRoot, fixture.candidateRoot.path)
        XCTAssertEqual(baselineReport.runProvenance.configuration, PerformanceConfiguration.standard12)
        XCTAssertEqual(candidateReport.runProvenance.configuration, PerformanceConfiguration.standard12)
        XCTAssertEqual(baselineReport.disposition, .revise)
        XCTAssertEqual(candidateReport.disposition, .revise)
        let artifact = try PerformanceCanonicalJSON.decoded(
            PerformancePairExecutionArtifact.self,
            from: Data(contentsOf: finalizeOutput.appendingPathComponent("pair-execution/pair-execution.json"))
        )
        XCTAssertEqual(artifact.records.count, 30)
        XCTAssertEqual(artifact.records.map(\.pairIndex), Array(0..<30))
        XCTAssertEqual(artifact.records.prefix(15).map(\.order), Array(repeating: .baselineFirst, count: 15))
        XCTAssertEqual(artifact.records.suffix(15).map(\.order), Array(repeating: .candidateFirst, count: 15))
        let replayStagingParent = finalizeOutput.deletingLastPathComponent()
        XCTAssertTrue(
            try fixture.transientPublishDirectories().filter { $0 != replayStagingParent }.isEmpty
        )
        XCTAssertTrue(
            fixture.partialPaths().allSatisfy { FileManager.default.fileExists(atPath: $0.path) },
            "real finalization must preserve all script-derived partial paths"
        )
    }

    func testInvalidDestinationWithSymlinkedPhysicalAncestorMakesNoExternalMutation() throws {
        let fixture = try TestFixture()
        defer { fixture.remove() }

        let external = fixture.rootDirectory.appendingPathComponent("external-evidence")
        let destinationParent = fixture.rootDirectory.appendingPathComponent("redirected")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: destinationParent, withDestinationURL: external)
        let destination = destinationParent.appendingPathComponent("standard12")

        let result = try fixture.run(outputDirectoryOverride: destination)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(try fixture.invocations().isEmpty)
        XCTAssertEqual(try fixture.directorySnapshot(at: external), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testDerivedPartialDirectoryWithSymlinkedAncestorMakesNoExternalMutation() throws {
        let fixture = try TestFixture()
        defer { fixture.remove() }

        let external = fixture.rootDirectory.appendingPathComponent("external-partials")
        let redirectedParent = fixture.partialDirectory.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: redirectedParent, withDestinationURL: external)

        let result = try fixture.run()
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(try fixture.invocations().isEmpty)
        XCTAssertEqual(try fixture.directorySnapshot(at: external), [])
    }

    func testStagedFinalizerOutputMustMatchExactRegularJSONAllowlist() throws {
        let fixture = try TestFixture(finalizerOutputMode: .extraFile)
        defer { fixture.remove() }

        let result = try fixture.run()
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(try fixture.invocations().last?.isFinalize == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileEvidence.appendingPathComponent("measurements").path))
    }

    func testStagedFinalizerOutputRejectsSymlinkedJSON() throws {
        let fixture = try TestFixture(finalizerOutputMode: .symlinkFile)
        defer { fixture.remove() }

        let result = try fixture.run()
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileEvidence.appendingPathComponent("measurements").path))
    }

    func testSIGKILLAfterBackupRestoresOldEvidenceBeforeNextInvocation() throws {
        let fixture = try TestFixture(failAtInvocation: 62, existingEvidence: true)
        defer { fixture.remove() }

        let before = try fixture.profileFileBytes()
        let killed = try fixture.run(extraArguments: ["--publish-hook", fixture.killAfterBackupHook.path])
        XCTAssertEqual(killed.status, 9, killed.output)
        XCTAssertFalse(try fixture.transientPublishDirectories().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileLock.path))

        let recovery = try fixture.run()
        XCTAssertNotEqual(recovery.status, 0, recovery.output)
        XCTAssertEqual(try fixture.profileFileBytes(), before)
        XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.appendingPathExtension("tmp").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))

        let completed = try fixture.run(failAtInvocationOverride: 0)
        XCTAssertEqual(completed.status, 0, completed.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileEvidence.appendingPathComponent("measurements/baseline.json").path))
        XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
    }

    func testSIGKILLAfterInstallRestoresOldEvidenceBeforeNextInvocation() throws {
        let fixture = try TestFixture(failAtInvocation: 62, existingEvidence: true)
        defer { fixture.remove() }

        let before = try fixture.profileFileBytes()
        let killed = try fixture.run(extraArguments: ["--post-rename-publish-hook", fixture.killAfterInstallHook.path])
        XCTAssertEqual(killed.status, 9, killed.output)
        XCTAssertFalse(try fixture.transientPublishDirectories().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileLock.path))

        let recovery = try fixture.run()
        XCTAssertNotEqual(recovery.status, 0, recovery.output)
        XCTAssertEqual(try fixture.profileFileBytes(), before)
        XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.appendingPathExtension("tmp").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))

        let completed = try fixture.run(failAtInvocationOverride: 0)
        XCTAssertEqual(completed.status, 0, completed.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileEvidence.appendingPathComponent("pair-execution/pair-execution.json").path))
        XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
    }

    func testLiveProfileLockRejectsConcurrentInvocationWithoutRecoveringFirstRun() throws {
        let fixture = try TestFixture()
        defer { fixture.remove() }

        let first = try fixture.start(holdParent: true)
        try fixture.waitForReady()
        XCTAssertTrue(first.process.isRunning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileLock.path))
        let lockContents = try String(contentsOf: fixture.profileLock, encoding: .utf8)
        XCTAssertTrue(lockContents.contains("pid="))
        XCTAssertTrue(lockContents.contains("transaction="))
        XCTAssertTrue(lockContents.contains("child="))
        XCTAssertFalse(lockContents.contains("child=none"))

        let before = try fixture.profileFileBytes()
        let second = try fixture.run()
        XCTAssertNotEqual(second.status, 0, second.output)
        XCTAssertTrue(second.output.contains("profile lock"), second.output)
        XCTAssertEqual(try fixture.profileFileBytes(), before)
        XCTAssertEqual(try fixture.invocations().count, 1)

        XCTAssertEqual(kill(first.process.processIdentifier, SIGCONT), 0)
        first.process.waitUntilExit()
        XCTAssertEqual(first.process.terminationStatus, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testDeadOwnerWithLiveChildCannotBeRecoveredUntilChildExits() throws {
        let fixture = try TestFixture(failAtInvocation: 2, existingEvidence: true)
        defer { fixture.remove() }

        let before = try fixture.profileFileBytes()
        let first = try fixture.start(killParentWithChild: true)
        try fixture.waitForReady()
        first.process.waitUntilExit()
        XCTAssertEqual(first.process.terminationStatus, 9)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileLock.path))

        let blocked = try fixture.run()
        XCTAssertNotEqual(blocked.status, 0, blocked.output)
        XCTAssertTrue(blocked.output.contains("live child process"), blocked.output)
        XCTAssertEqual(try fixture.profileFileBytes(), before)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))

        try Data("go\n".utf8).write(to: fixture.childRelease)
        let done = first.output.fileHandleForReading.readData(ofLength: 5)
        XCTAssertEqual(String(decoding: done, as: UTF8.self), "DONE\n")

        let recovered = try fixture.run()
        XCTAssertNotEqual(recovered.status, 0, recovered.output)
        XCTAssertEqual(try fixture.profileFileBytes(), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testTERMForwardsToActiveChildBeforeReleasingProfileLock() throws {
        let fixture = try TestFixture()
        defer { fixture.remove() }

        let running = try fixture.start(holdChild: true)
        try fixture.waitForReady()
        let lockContents = try String(contentsOf: fixture.profileLock, encoding: .utf8)
        XCTAssertTrue(lockContents.contains("child="))
        XCTAssertFalse(lockContents.contains("child=none"))

        XCTAssertEqual(kill(running.process.processIdentifier, SIGTERM), 0)
        running.process.waitUntilExit()
        XCTAssertEqual(running.process.terminationStatus, 143)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testProfileLockTupleMatrixFailsClosedBeforeMutation() throws {
        let malformedTuples = [
            ("idle", "token", "none", "none"),
            ("idle", "none", "123", "none"),
            ("idle", "none", "none", "123"),
            ("starting", "none", "none", "none"),
            ("starting", "token", "123", "none"),
            ("starting", "token", "none", "123"),
            ("running", "token", "none", "123"),
            ("running", "token", "123", "none"),
            ("running", "none", "123", "123"),
            ("running", "token", "0", "1"),
            ("running", "token", "123", "456")
        ]
        for (state, token, child, pgid) in malformedTuples {
            let fixture = try TestFixture(existingEvidence: true)
            defer { fixture.remove() }
            let before = try fixture.profileNodeSnapshot()
            let lockContents = "version=1\npid=999999999\ntransaction=stale\nchild=\(child)\nchild-state=\(state)\nchild-token=\(token)\nchild-pgid=\(pgid)\n"
            try fixture.writeProfileLock(contents: lockContents)

            let result = try fixture.run()
            XCTAssertNotEqual(result.status, 0, "malformed lock tuple was accepted: \(state), \(token), \(child), \(pgid)")
            XCTAssertTrue(result.output.contains("invalid child tuple"), result.output)
            XCTAssertTrue(try fixture.invocations().isEmpty)
            XCTAssertEqual(try fixture.profileNodeSnapshot(), before)
            XCTAssertEqual(try String(contentsOf: fixture.profileLock, encoding: .utf8), lockContents)
        }
    }

    func testStaleStartingIntentAfterDurableWriteRecoversBeforeFork() throws {
        let fixture = try TestFixture(existingEvidence: true)
        defer { fixture.remove() }

        let before = try fixture.profileFileBytes()
        let first = try fixture.start(crashAfterStarting: true)
        first.process.waitUntilExit()
        XCTAssertEqual(first.process.terminationStatus, 9)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileLock.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))

        let recovered = try fixture.run()
        XCTAssertEqual(recovered.status, 0, recovered.output)
        XCTAssertNotEqual(try fixture.profileFileBytes(), before)
        XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testStaleStartingIntentAfterForkBeforeOwnerRecordRecoversGatedGroup() throws {
        let fixture = try TestFixture(existingEvidence: true)
        defer { fixture.remove() }

        let first = try fixture.start(crashBeforeOwner: true, beforeOwnerDelay: 1.25)
        first.process.waitUntilExit()
        XCTAssertEqual(first.process.terminationStatus, 9)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileLock.path))

        let recovered = try fixture.run()
        XCTAssertEqual(recovered.status, 0, recovered.output)
        try fixture.waitForBeforeOwnerDone()
        XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testStaleStartingIntentAfterOwnerReadyRecoversBeforeGateRelease() throws {
        let fixture = try TestFixture(existingEvidence: true)
        defer { fixture.remove() }

        let first = try fixture.start(crashAfterReady: true)
        first.process.waitUntilExit()
        XCTAssertEqual(first.process.terminationStatus, 9)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileLock.path))

        let recovered = try fixture.run()
        XCTAssertEqual(recovered.status, 0, recovered.output)
        XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testStartingRecoveryResumesAfterDurableRevocationMarkerCrash() throws {
        let fixture = try TestFixture(existingEvidence: true)
        defer { fixture.remove() }

        let first = try fixture.start(crashAfterStarting: true)
        first.process.waitUntilExit()
        XCTAssertEqual(first.process.terminationStatus, 9)

        let interrupted = try fixture.run(crashAfterChildRevoke: true)
        XCTAssertEqual(interrupted.status, 9, interrupted.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileLock.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertEqual(try fixture.invocations().count, 0)
        XCTAssertEqual(try fixture.childControlEntries().count, 1)

        let recovered = try fixture.run()
        XCTAssertEqual(recovered.status, 0, recovered.output)
        XCTAssertEqual(try fixture.invocations().count, 61)
        XCTAssertTrue(try fixture.childControlEntries().isEmpty)
        XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testStartingRecoveryResumesAfterQuarantineRenameCrash() throws {
        let fixture = try TestFixture(existingEvidence: true)
        defer { fixture.remove() }

        let first = try fixture.start(crashAfterStarting: true)
        first.process.waitUntilExit()
        XCTAssertEqual(first.process.terminationStatus, 9)

        let interrupted = try fixture.run(crashAfterChildQuarantine: true)
        XCTAssertEqual(interrupted.status, 9, interrupted.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileLock.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertEqual(try fixture.invocations().count, 0)
        XCTAssertEqual(try fixture.childControlEntries().count, 1)
        XCTAssertTrue(try fixture.childControlEntries()[0].lastPathComponent.contains(".revoked."))

        let recovered = try fixture.run()
        XCTAssertEqual(recovered.status, 0, recovered.output)
        XCTAssertEqual(try fixture.invocations().count, 61)
        XCTAssertTrue(try fixture.childControlEntries().isEmpty)
        XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testStartingRecoveryResumesAfterCleanupTombstoneRenameCrash() throws {
        let fixture = try TestFixture(existingEvidence: true)
        defer { fixture.remove() }

        let first = try fixture.start(crashAfterStarting: true)
        first.process.waitUntilExit()
        XCTAssertEqual(first.process.terminationStatus, 9)

        let interrupted = try fixture.run(crashAfterChildCleanupRename: true)
        XCTAssertEqual(interrupted.status, 9, interrupted.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileLock.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertEqual(try fixture.invocations().count, 0)
        XCTAssertEqual(try fixture.childControlEntries().count, 1)
        XCTAssertTrue(try fixture.childControlEntries()[0].lastPathComponent.contains(".cleanup."))

        let recovered = try fixture.run()
        XCTAssertEqual(recovered.status, 0, recovered.output)
        XCTAssertEqual(try fixture.invocations().count, 61)
        XCTAssertTrue(try fixture.childControlEntries().isEmpty)
        XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testStartingRecoveryResumesAfterCleanupFileRemovalCrash() throws {
        let fixture = try TestFixture(existingEvidence: true)
        defer { fixture.remove() }

        let first = try fixture.start(crashAfterStarting: true)
        first.process.waitUntilExit()
        XCTAssertEqual(first.process.terminationStatus, 9)

        let interrupted = try fixture.run(crashAfterChildFileRemoval: true)
        XCTAssertEqual(interrupted.status, 9, interrupted.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileLock.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertEqual(try fixture.invocations().count, 0)
        XCTAssertEqual(try fixture.childControlEntries().count, 1)
        XCTAssertTrue(try fixture.childControlEntries()[0].lastPathComponent.contains(".cleanup."))

        let recovered = try fixture.run()
        XCTAssertEqual(recovered.status, 0, recovered.output)
        XCTAssertEqual(try fixture.invocations().count, 61)
        XCTAssertTrue(try fixture.childControlEntries().isEmpty)
        XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testStartingRecoveryResumesAfterRevocationMarkerRemovalCrash() throws {
        let fixture = try TestFixture(existingEvidence: true)
        defer { fixture.remove() }

        let first = try fixture.start(crashAfterStarting: true)
        first.process.waitUntilExit()
        XCTAssertEqual(first.process.terminationStatus, 9)

        let interrupted = try fixture.run(crashAfterChildRevocationRemoval: true)
        XCTAssertEqual(interrupted.status, 9, interrupted.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileLock.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertEqual(try fixture.invocations().count, 0)
        let cleanup = try XCTUnwrap(try fixture.childControlEntries().first)
        XCTAssertTrue(cleanup.lastPathComponent.contains(".cleanup."))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(at: cleanup, includingPropertiesForKeys: nil).contains { $0.lastPathComponent.hasSuffix(".capability.revoked") })

        let recovered = try fixture.run()
        XCTAssertEqual(recovered.status, 0, recovered.output)
        XCTAssertEqual(try fixture.invocations().count, 61)
        XCTAssertTrue(try fixture.childControlEntries().isEmpty)
        XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testStaleRecoveryGuardAllowsExactlyOneConcurrentContender() throws {
        let fixture = try TestFixture(existingEvidence: true)
        defer { fixture.remove() }

        let first = try fixture.start(crashAfterStarting: true)
        first.process.waitUntilExit()
        XCTAssertEqual(first.process.terminationStatus, 9)

        let contenderA = try fixture.start()
        let contenderB = try fixture.start()
        contenderA.process.waitUntilExit()
        contenderB.process.waitUntilExit()
        let results = [
            (contenderA.process.terminationStatus, String(data: contenderA.output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""),
            (contenderB.process.terminationStatus, String(data: contenderB.output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
        ]
        XCTAssertEqual(results.filter { $0.0 == 0 }.count, 1, "exactly one stale contender should publish: \(results)")
        XCTAssertEqual(try fixture.invocations().count, 61)
        XCTAssertTrue(results.contains { $0.0 != 0 && ($0.1.contains("recovery guard") || $0.1.contains("profile lock")) })
        XCTAssertTrue(try fixture.recoveryGuardQuarantines().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testStaleRecoveryGuardCrashIsReclaimedBeforeRecovery() throws {
        let fixture = try TestFixture(existingEvidence: true)
        defer { fixture.remove() }

        let first = try fixture.start(crashAfterStarting: true)
        first.process.waitUntilExit()
        XCTAssertEqual(first.process.terminationStatus, 9)

        let interrupted = try fixture.run(crashAfterRecoveryGuard: true)
        XCTAssertEqual(interrupted.status, 9, interrupted.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileLock.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.recoveryGuard.path))
        XCTAssertEqual(try fixture.invocations().count, 0)

        let recovered = try fixture.run()
        XCTAssertEqual(recovered.status, 0, recovered.output)
        XCTAssertEqual(try fixture.invocations().count, 61)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.recoveryGuard.path))
        XCTAssertTrue(try fixture.recoveryGuardQuarantines().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
    }

    func testRecoveryGuardBarrierSerializesConcurrentStaleRecovery() throws {
        let fixture = try TestFixture(existingEvidence: true)
        defer { fixture.remove() }

        let first = try fixture.start(crashAfterStarting: true)
        first.process.waitUntilExit()
        XCTAssertEqual(first.process.terminationStatus, 9)

        let contenderA = try fixture.start(recoveryGuardBarrier: true)
        try fixture.waitForRecoveryGuardReady()
        let contenderB = try fixture.start()
        contenderB.process.waitUntilExit()
        let contenderBOutput = String(data: contenderB.output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertNotEqual(contenderB.process.terminationStatus, 0, contenderBOutput)
        XCTAssertTrue(contenderBOutput.contains("recovery guard is held by a live process"), contenderBOutput)
        XCTAssertEqual(try fixture.invocations().count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.recoveryGuard.path))

        try fixture.releaseRecoveryGuardBarrier()
        contenderA.process.waitUntilExit()
        XCTAssertEqual(contenderA.process.terminationStatus, 0)
        XCTAssertEqual(try fixture.invocations().count, 61)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.recoveryGuard.path))
        XCTAssertTrue(try fixture.recoveryGuardQuarantines().isEmpty)
    }

    func testRecoveryGuardReclaimBarrierLeavesUniqueQuarantineUntilRelease() throws {
        let fixture = try TestFixture(existingEvidence: true)
        defer { fixture.remove() }

        let first = try fixture.start(crashAfterStarting: true)
        first.process.waitUntilExit()
        XCTAssertEqual(first.process.terminationStatus, 9)
        let guardCrash = try fixture.run(crashAfterRecoveryGuard: true)
        XCTAssertEqual(guardCrash.status, 9, guardCrash.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.recoveryGuard.path))

        let reclaim = try fixture.start(recoveryGuardReclaimBarrier: true)
        try fixture.waitForRecoveryGuardReclaimReady()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.recoveryGuard.path))
        XCTAssertEqual(try fixture.recoveryGuardQuarantines().count, 1)
        XCTAssertTrue(try fixture.syncEvents().contains("recovery-guard-quarantine"))
        XCTAssertEqual(try fixture.invocations().count, 0)

        try fixture.releaseRecoveryGuardReclaimBarrier()
        reclaim.process.waitUntilExit()
        XCTAssertEqual(reclaim.process.terminationStatus, 0)
        XCTAssertEqual(try fixture.invocations().count, 61)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.recoveryGuard.path))
        XCTAssertTrue(try fixture.recoveryGuardQuarantines().isEmpty)
    }

    func testInvalidRevokedCapabilityMarkerFailsClosed() throws {
        let fixture = try TestFixture(existingEvidence: true)
        defer { fixture.remove() }

        let first = try fixture.start(crashAfterStarting: true)
        first.process.waitUntilExit()
        XCTAssertEqual(first.process.terminationStatus, 9)
        let control = try XCTUnwrap(try fixture.childControlEntries().first)
        let capability = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: control, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasSuffix(".capability") }
        )
        let marker = capability.appendingPathExtension("revoked")
        try fixture.writeFileForTest(at: marker, contents: "not-revoked\n")

        let result = try fixture.run()
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("capability revocation is invalid"), result.output)
        XCTAssertTrue(try fixture.invocations().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testChildLockStateRenameIsFollowedByDurableSync() throws {
        let fixture = try TestFixture()
        defer { fixture.remove() }

        let running = try fixture.start(holdChild: true)
        try fixture.waitForReady()
        XCTAssertTrue(try fixture.scriptContains("mv -f -- \"$temporary\" \"$profile_lock\" || return 1\n    durable_sync lock-update"))
        XCTAssertTrue(try fixture.syncEvents().contains("lock-update"))
        XCTAssertTrue(try String(contentsOf: fixture.profileLock, encoding: .utf8).contains("child-state=running"))

        try Data("go\n".utf8).write(to: fixture.childRelease)
        running.process.waitUntilExit()
        XCTAssertEqual(running.process.terminationStatus, 0)
        XCTAssertTrue(try fixture.syncEvents().contains("lock-update"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testNonemptyOrphanPendingTreeWithoutJournalIsRejectedWithoutMutation() throws {
        let fixture = try TestFixture()
        defer { fixture.remove() }

        let orphan = fixture.pendingDirectory
        let sentinel = orphan.appendingPathComponent("unowned.json")
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try Data("unowned\n".utf8).write(to: sentinel)

        let result = try fixture.run()
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(try fixture.invocations().isEmpty)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("unowned\n".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testPreparedCrashLeavesJournalAndRecoveryRemovesPendingWithoutChangingOldEvidence() throws {
        let fixture = try TestFixture(
            failAtInvocation: 62,
            existingEvidence: true,
            finalizerOutputMode: .killBeforeOutput
        )
        defer { fixture.remove() }

        let before = try fixture.profileFileBytes()
        let killed = try fixture.run(finalizerCrash: true)
        XCTAssertEqual(killed.status, 9, killed.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileLock.path))
        XCTAssertFalse(try fixture.transientPublishDirectories().isEmpty)

        let recovery = try fixture.run()
        XCTAssertNotEqual(recovery.status, 0, recovery.output)
        XCTAssertEqual(try fixture.profileFileBytes(), before)
        XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testLogicalDestinationOverlapRejectsBeforeCreatingAnyParent() throws {
        let fixture = try TestFixture()
        defer { fixture.remove() }

        let before = try fixture.directorySnapshot(at: fixture.baselineRoot)
        let invalidDestination = fixture.baselineRoot.appendingPathComponent("extra/standard12")
        let result = try fixture.run(outputDirectoryOverride: invalidDestination)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(try fixture.invocations().isEmpty)
        XCTAssertEqual(try fixture.directorySnapshot(at: fixture.baselineRoot), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalidDestination.deletingLastPathComponent().path))
    }

    func testLegacyEvidenceDestinationIsRejectedWithoutMutation() throws {
        let fixture = try TestFixture()
        defer { fixture.remove() }

        let legacyDestination = fixture.rootDirectory.appendingPathComponent("evidence/standard12")
        let result = try fixture.run(outputDirectoryOverride: legacyDestination)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(try fixture.invocations().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.rootDirectory.appendingPathComponent("evidence").path))
    }

    func testPublishHooksAreRevalidatedForExtraSymlinkAndInvalidJSONMutations() throws {
        for placement in [MutationPlacement.prePublish, .postRename] {
            for mutation in [OutputMutation.extra, .symlink, .invalidJSON] {
                let fixture = try TestFixture(existingEvidence: true)
                defer { fixture.remove() }
                let before = try fixture.profileFileBytes()
                let hook = try fixture.makeMutationHook(mutation: mutation, placement: placement)
                let hookFlag = placement == .prePublish ? "--publish-hook" : "--post-rename-publish-hook"

                let result = try fixture.run(extraArguments: [hookFlag, hook.path])
                XCTAssertNotEqual(result.status, 0, "mutation unexpectedly published: (placement) (mutation)\n(result.output)")
                XCTAssertEqual(try fixture.profileFileBytes(), before)
                XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
                XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
                XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
            }
        }
    }

    func testForeignRepositoryShapedRootsAreRejectedBeforeMutation() throws {
        let fixture = try TestFixture()
        defer { fixture.remove() }

        let foreignRoot = fixture.rootDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("pointer foreign benchmark", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fixture.createRepositoryLayout(at: foreignRoot)
        defer { try? FileManager.default.removeItem(at: foreignRoot) }
        let foreignOutput = foreignRoot.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance/standard12")
        let before = try fixture.directorySnapshot(at: foreignRoot)

        let result = try fixture.run(repositoryRootOverride: foreignRoot)
        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("repository root"), result.output)
        XCTAssertTrue(try fixture.invocations().isEmpty)
        XCTAssertEqual(try fixture.directorySnapshot(at: foreignRoot), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: foreignOutput.appendingPathComponent("measurements").path))
    }

    func testTERMForwardsToTrackedPublishHookBeforeReleasingLock() throws {
        let fixture = try TestFixture(existingEvidence: true)
        defer { fixture.remove() }

        let hook = try fixture.makeBlockingHook(killParent: false, mutateAfterRelease: false)
        let before = try fixture.profileFileBytes()
        let running = try fixture.start(extraArguments: ["--publish-hook", hook.path])
        try fixture.waitForReady()
        let lockContents = try String(contentsOf: fixture.profileLock, encoding: .utf8)
        XCTAssertFalse(lockContents.contains("child=none"))

        XCTAssertEqual(kill(running.process.processIdentifier, SIGTERM), 0)
        running.process.waitUntilExit()
        XCTAssertEqual(running.process.terminationStatus, 143)
        XCTAssertEqual(try fixture.profileFileBytes(), before)
        XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.appendingPathExtension("tmp").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testSIGKILLedPublishHookKeepsLiveChildOwnershipUntilLateMutationExits() throws {
        let fixture = try TestFixture(failAtInvocation: 62, existingEvidence: true)
        defer { fixture.remove() }

        let hook = try fixture.makeBlockingHook(killParent: true, mutateAfterRelease: true)
        let before = try fixture.profileFileBytes()
        let first = try fixture.start(extraArguments: ["--publish-hook", hook.path])
        try fixture.waitForReady()
        first.process.waitUntilExit()
        XCTAssertEqual(first.process.terminationStatus, 9)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.profileLock.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(try fixture.transientPublishDirectories().isEmpty)

        let blocked = try fixture.run(failAtInvocationOverride: 62)
        XCTAssertNotEqual(blocked.status, 0, blocked.output)
        XCTAssertTrue(blocked.output.contains("live child process"), blocked.output)
        XCTAssertEqual(try fixture.invocations().count, 61)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(try fixture.transientPublishDirectories().isEmpty)

        try Data("go\n".utf8).write(to: fixture.childRelease)
        try fixture.waitForDone()

        let recovered = try fixture.run(failAtInvocationOverride: 62)
        XCTAssertNotEqual(recovered.status, 0, recovered.output)
        XCTAssertEqual(try fixture.profileFileBytes(), before)
        XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }

    func testPreexistingOutputNodeTypeMutationsAreRejectedBeforeOverwrite() throws {
        for mutation in ExistingOutputNodeMutation.allCases {
            let fixture = try TestFixture(existingEvidence: true)
            defer { fixture.remove() }
            try fixture.applyExistingOutputNodeMutation(mutation)
            let before = try fixture.profileNodeSnapshot()

            let result = try fixture.run()
            XCTAssertNotEqual(result.status, 0, "wrong existing node type was accepted: \(mutation)\n\(result.output)")
            XCTAssertEqual(try fixture.profileNodeSnapshot(), before)
            XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
        }
    }

    func testForkedHookDescendantKeepsGroupTrackedUntilRevalidation() throws {
        let fixture = try TestFixture(existingEvidence: true)
        defer { fixture.remove() }

        let hook = try fixture.makeForkingDelayedHook()
        let before = try fixture.profileFileBytes()
        let result = try fixture.run(extraArguments: ["--publish-hook", hook.path])

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertEqual(try fixture.profileFileBytes(), before)
        XCTAssertTrue(try fixture.transientPublishDirectories().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.transactionJournal.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.profileLock.path))
    }
}

private enum MutationPlacement {
    case prePublish
    case postRename
}

private enum OutputMutation {
    case extra
    case symlink
    case invalidJSON
}

private enum ExistingOutputNodeMutation: CaseIterable {
    case comparisonsFile
    case provenanceSymlink
    case provenanceDanglingSymlink
    case measurementsFile
    case pairExecutionSymlink
}

private struct RecordedInvocation {
    let arguments: [String]

    var isTrial: Bool { value(after: "--operation") == "trial" }
    var isFinalize: Bool { value(after: "--operation") == "finalize" }
    var isCompare: Bool { arguments.contains("--quality-compare") }
    var cliArguments: [String] { Array(arguments.dropFirst()) }
    var executable: String { arguments.first ?? "" }

    var fixtureProfile: String? { value(after: "--fixture-profile") }
    var variant: String? { value(after: "--variant") }
    var operation: String? { value(after: "--operation") }
    var pairOrder: String? { value(after: "--pair-order") }
    var pairIndex: Int? { value(after: "--pair-index").flatMap(Int.init) }
    var pairLabel: String { "\(pairIndex ?? -1):\(variant ?? "")" }
    var partialName: String? {
        value(after: "--partial-pair-directory").map { URL(fileURLWithPath: $0).appendingPathComponent("\(pairIndex ?? -1).json").lastPathComponent }
    }
    var expectedPartialName: String { "\(pairIndex ?? -1).json" }
    var outputDirectoryURL: URL {
        URL(fileURLWithPath: value(after: "--output-dir") ?? "")
    }

    @MainActor
    func parse(outputDirectory: URL) throws -> PerformanceCLI.Invocation {
        try PerformanceCLI.parse(arguments: cliArguments, outputDirectory: outputDirectory)
    }

    func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(arguments.index(after: index)) else {
            return nil
        }
        return arguments[arguments.index(after: index)]
    }
}

private final class RunningScript {
    let process: Process
    let output: Pipe
    let input: Pipe

    init(process: Process, output: Pipe, input: Pipe) {
        self.process = process
        self.output = output
        self.input = input
    }
}

private final class TestFixture {
    enum FinalizerOutputMode {
        case canonical
        case extraFile
        case symlinkFile
        case killBeforeOutput
    }

    private let root: URL
    private let script: URL
    private let runner: URL
    private let log: URL
    private let failAtInvocation: Int?
    private let finalizerOutputMode: FinalizerOutputMode

    let rootDirectory: URL
    let baselineRoot: URL
    let candidateRoot: URL
    let baselineExecutable: URL
    let candidateExecutable: URL
    let baselineProvenance: URL
    let candidateProvenance: URL
    let pairEligibility: URL
    let partialDirectory: URL
    let profileEvidence: URL
    let publishHook: URL
    let publishMarker: URL
    let postRenamePublishHook: URL
    let postRenamePublishMarker: URL
    let postRenameOutputMarker: URL
    let killAfterBackupHook: URL
    let killAfterInstallHook: URL
    let transactionJournal: URL
    let profileLock: URL
    let recoveryGuard: URL
    let recoveryGuardReady: URL
    let recoveryGuardRelease: URL
    let recoveryGuardReclaimReady: URL
    let recoveryGuardReclaimRelease: URL
    let pendingDirectory: URL
    let childRelease: URL
    let readySignal: URL
    let doneSignal: URL
    let beforeOwnerDone: URL
    let syncRecorder: URL
    let baselineCommit = String(repeating: "a", count: 40)
    let candidateCommit = String(repeating: "b", count: 40)

    init(
        failAtInvocation: Int? = nil,
        existingEvidence: Bool = false,
        finalizerOutputMode: FinalizerOutputMode = .canonical
    ) throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let repositoryScript = repositoryRoot.appendingPathComponent("scripts/benchmark-quality.sh")
        let temporaryDirectory = FileManager.default.temporaryDirectory.path
        let canonicalTemporaryDirectory = temporaryDirectory.hasPrefix("/var/")
            ? "/private\(temporaryDirectory)"
            : temporaryDirectory
        root = URL(fileURLWithPath: canonicalTemporaryDirectory)
            .appendingPathComponent("pointer benchmark script \(UUID().uuidString)", isDirectory: true)
        rootDirectory = root
        script = root.appendingPathComponent("scripts/benchmark-quality.sh")
        runner = root.appendingPathComponent("fake-runner.sh")
        log = root.appendingPathComponent("invocations.log")
        self.failAtInvocation = failAtInvocation
        self.finalizerOutputMode = finalizerOutputMode
        baselineRoot = root.appendingPathComponent("build/standard12/baseline")
        candidateRoot = root.appendingPathComponent("build/standard12/candidate")
        baselineExecutable = baselineRoot.appendingPathComponent("Pointer.app/Contents/MacOS/Pointer")
        candidateExecutable = candidateRoot.appendingPathComponent("Pointer.app/Contents/MacOS/Pointer")
        baselineProvenance = baselineRoot.appendingPathComponent("provenance.json")
        candidateProvenance = candidateRoot.appendingPathComponent("provenance.json")
        let performanceEvidenceRoot = root.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance", isDirectory: true)
        pairEligibility = performanceEvidenceRoot.appendingPathComponent("standard12/comparisons/pair-eligibility.json")
        partialDirectory = root.appendingPathComponent("build/standard12/pair-execution/partial")
        profileEvidence = performanceEvidenceRoot.appendingPathComponent("standard12")
        publishHook = root.appendingPathComponent("publish-hook.sh")
        publishMarker = root.appendingPathComponent("publish-hook-reached.txt")
        postRenamePublishHook = root.appendingPathComponent("post-rename-publish-hook.sh")
        postRenamePublishMarker = root.appendingPathComponent("post-rename-publish-hook-reached.txt")
        postRenameOutputMarker = profileEvidence.appendingPathComponent("measurements/post-rename-output-marker.txt")
        killAfterBackupHook = root.appendingPathComponent("kill-after-backup-hook.sh")
        killAfterInstallHook = root.appendingPathComponent("kill-after-install-hook.sh")
        transactionJournal = performanceEvidenceRoot.appendingPathComponent(".benchmark-quality.transaction.standard12")
        profileLock = performanceEvidenceRoot.appendingPathComponent(".benchmark-quality.lock.standard12")
        recoveryGuard = performanceEvidenceRoot.appendingPathComponent(".benchmark-quality.recovery.standard12")
        recoveryGuardReady = root.appendingPathComponent("recovery-guard.ready")
        recoveryGuardRelease = root.appendingPathComponent("recovery-guard.release")
        recoveryGuardReclaimReady = root.appendingPathComponent("recovery-guard-reclaim.ready")
        recoveryGuardReclaimRelease = root.appendingPathComponent("recovery-guard-reclaim.release")
        pendingDirectory = performanceEvidenceRoot.appendingPathComponent(".benchmark-quality.pending.standard12")
        childRelease = root.appendingPathComponent("release-child.txt")
        readySignal = root.appendingPathComponent("ready.signal")
        doneSignal = root.appendingPathComponent("done.signal")
        beforeOwnerDone = root.appendingPathComponent("before-owner.done")
        syncRecorder = root.appendingPathComponent("sync.log")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try writeExecutable(at: script, contents: String(contentsOf: repositoryScript, encoding: .utf8))
        try writeExecutable(at: runner, contents: Self.runnerScript)
        try writeExecutable(at: publishHook, contents: "#!/bin/sh\nprintf '%s\\n' reached > \"$POINTER_PUBLISH_MARKER\"\nkill -TERM \"$PPID\"\n")
        try writeExecutable(at: postRenamePublishHook, contents: "#!/bin/sh\nprintf '%s\\n' reached > \"$POINTER_POST_RENAME_PUBLISH_MARKER\"\nprintf '%s\\n' new > \"$POINTER_POST_RENAME_OUTPUT_MARKER\"\nkill -TERM \"$PPID\"\n")
        try writeExecutable(at: killAfterBackupHook, contents: "#!/bin/sh\nkill -KILL \"$PPID\"\n")
        try writeExecutable(at: killAfterInstallHook, contents: "#!/bin/sh\nkill -KILL \"$PPID\"\n")
        guard mkfifo(childRelease.path, mode_t(0o600)) == 0 else {
            throw NSError(domain: "PointerBenchmarkTests", code: 1)
        }
        guard mkfifo(readySignal.path, mode_t(0o600)) == 0 else {
            throw NSError(domain: "PointerBenchmarkTests", code: 1)
        }
        guard mkfifo(doneSignal.path, mode_t(0o600)) == 0 else {
            throw NSError(domain: "PointerBenchmarkTests", code: 1)
        }
        guard mkfifo(beforeOwnerDone.path, mode_t(0o600)) == 0 else {
            throw NSError(domain: "PointerBenchmarkTests", code: 1)
        }
        guard mkfifo(recoveryGuardReady.path, mode_t(0o600)) == 0 else {
            throw NSError(domain: "PointerBenchmarkTests", code: 1)
        }
        guard mkfifo(recoveryGuardRelease.path, mode_t(0o600)) == 0 else {
            throw NSError(domain: "PointerBenchmarkTests", code: 1)
        }
        guard mkfifo(recoveryGuardReclaimReady.path, mode_t(0o600)) == 0 else {
            throw NSError(domain: "PointerBenchmarkTests", code: 1)
        }
        guard mkfifo(recoveryGuardReclaimRelease.path, mode_t(0o600)) == 0 else {
            throw NSError(domain: "PointerBenchmarkTests", code: 1)
        }
        try writeFile(at: log, contents: "")
        try writeFile(at: syncRecorder, contents: "")

        for executable in [baselineExecutable, candidateExecutable] {
            try writeExecutable(at: executable, contents: "#!/bin/sh\nexit 0\n")
        }
        try writeFile(at: baselineProvenance, contents: "{\"variant\":\"baseline\"}\n")
        try writeFile(at: candidateProvenance, contents: "{\"variant\":\"candidate\"}\n")
        try writeFile(at: pairEligibility, contents: "{\"eligible\":true}\n")
        if existingEvidence {
            try writeFile(at: profileEvidence.appendingPathComponent("comparisons/pair-eligibility.json"), contents: "{\"eligible\":true}\n")
            try writeFile(at: profileEvidence.appendingPathComponent("provenance/baseline.json"), contents: "{\"variant\":\"baseline\"}\n")
            try writeFile(at: profileEvidence.appendingPathComponent("provenance/candidate.json"), contents: "{\"variant\":\"candidate\"}\n")
        }
        try writeFile(at: root.appendingPathComponent("baseline-report-template.json"), contents: "{\"reportKind\":\"measurement\",\"schemaVersion\":1,\"fixtureProfile\":\"standard12\",\"variant\":\"baseline\"}\n")
        try writeFile(at: root.appendingPathComponent("candidate-report-template.json"), contents: "{\"reportKind\":\"measurement\",\"schemaVersion\":1,\"fixtureProfile\":\"standard12\",\"variant\":\"candidate\"}\n")
        try writeFile(at: root.appendingPathComponent("pair-artifact-template.json"), contents: "{\"schemaVersion\":1,\"fixtureProfile\":\"standard12\",\"records\":[] }\n")
    }

    func run(
        useDefaultBuildInputs: Bool = false,
        omitRunProvenance: String? = nil,
        extraArguments: [String] = [],
        outputDirectoryOverride: URL? = nil,
        repositoryRootOverride: URL? = nil,
        failAtInvocationOverride: Int? = nil,
        finalizerCrash: Bool = false,
        crashAfterChildRevoke: Bool = false,
        crashAfterChildQuarantine: Bool = false,
        crashAfterChildCleanupRename: Bool = false,
        crashAfterChildFileRemoval: Bool = false,
        crashAfterChildRevocationRemoval: Bool = false,
        crashAfterRecoveryGuard: Bool = false,
        recoveryGuardBarrier: Bool = false,
        recoveryGuardReclaimBarrier: Bool = false
    ) throws -> (status: Int32, output: String) {
        let running = try start(
            useDefaultBuildInputs: useDefaultBuildInputs,
            omitRunProvenance: omitRunProvenance,
            extraArguments: extraArguments,
            outputDirectoryOverride: outputDirectoryOverride,
            repositoryRootOverride: repositoryRootOverride,
            failAtInvocationOverride: failAtInvocationOverride,
            holdParent: false,
            finalizerCrash: finalizerCrash,
            killParentWithChild: false,
            holdChild: false,
            crashAfterChildRevoke: crashAfterChildRevoke,
            crashAfterChildQuarantine: crashAfterChildQuarantine,
            crashAfterChildCleanupRename: crashAfterChildCleanupRename,
            crashAfterChildFileRemoval: crashAfterChildFileRemoval,
            crashAfterChildRevocationRemoval: crashAfterChildRevocationRemoval,
            crashAfterRecoveryGuard: crashAfterRecoveryGuard,
            recoveryGuardBarrier: recoveryGuardBarrier,
            recoveryGuardReclaimBarrier: recoveryGuardReclaimBarrier
        )
        running.process.waitUntilExit()
        let output = String(data: running.output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (running.process.terminationStatus, output)
    }

    func start(
        useDefaultBuildInputs: Bool = false,
        omitRunProvenance: String? = nil,
        extraArguments: [String] = [],
        outputDirectoryOverride: URL? = nil,
        repositoryRootOverride: URL? = nil,
        failAtInvocationOverride: Int? = nil,
        holdParent: Bool = false,
        finalizerCrash: Bool = false,
        killParentWithChild: Bool = false,
        holdChild: Bool = false,
        crashAfterStarting: Bool = false,
        crashBeforeOwner: Bool = false,
        crashAfterReady: Bool = false,
        beforeOwnerDelay: TimeInterval = 0,
        crashAfterChildRevoke: Bool = false,
        crashAfterChildQuarantine: Bool = false,
        crashAfterChildCleanupRename: Bool = false,
        crashAfterChildFileRemoval: Bool = false,
        crashAfterChildRevocationRemoval: Bool = false,
        crashAfterRecoveryGuard: Bool = false,
        recoveryGuardBarrier: Bool = false,
        recoveryGuardReclaimBarrier: Bool = false
    ) throws -> RunningScript {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments(
            useDefaultBuildInputs: useDefaultBuildInputs,
            omitRunProvenance: omitRunProvenance,
            outputDirectoryOverride: outputDirectoryOverride,
            repositoryRootOverride: repositoryRootOverride
        ) + extraArguments
        var environment = ProcessInfo.processInfo.environment
        environment["POINTER_FAKE_LOG"] = log.path
        environment["POINTER_FAKE_FAIL_AT"] = (failAtInvocationOverride ?? failAtInvocation).map(String.init) ?? "0"
        environment["POINTER_FAKE_PARTIAL_DIRECTORY"] = partialDirectory.path
        environment["POINTER_FAKE_BASELINE_REPORT"] = root.appendingPathComponent("baseline-report-template.json").path
        environment["POINTER_FAKE_CANDIDATE_REPORT"] = root.appendingPathComponent("candidate-report-template.json").path
        environment["POINTER_FAKE_PAIR_ARTIFACT"] = root.appendingPathComponent("pair-artifact-template.json").path
        environment["POINTER_PUBLISH_MARKER"] = publishMarker.path
        environment["POINTER_POST_RENAME_PUBLISH_MARKER"] = postRenamePublishMarker.path
        environment["POINTER_POST_RENAME_OUTPUT_MARKER"] = postRenameOutputMarker.path
        environment["POINTER_FAKE_FINALIZER_EXTRA_FILE"] = finalizerOutputMode == .extraFile ? "1" : "0"
        environment["POINTER_FAKE_FINALIZER_SYMLINK_FILE"] = finalizerOutputMode == .symlinkFile ? "1" : "0"
        environment["POINTER_FAKE_FINALIZER_KILL"] = finalizerCrash ? "1" : "0"
        environment["POINTER_FAKE_HOLD_PARENT"] = holdParent ? "1" : "0"
        environment["POINTER_FAKE_KILL_PARENT_WITH_CHILD"] = killParentWithChild ? "1" : "0"
        environment["POINTER_FAKE_HOLD_CHILD"] = holdChild ? "1" : "0"
        environment["POINTER_FAKE_CHILD_RELEASE"] = childRelease.path
        environment["POINTER_FAKE_READY"] = readySignal.path
        environment["POINTER_FAKE_DONE"] = doneSignal.path
        environment["POINTER_BENCHMARK_SYNC_RECORDER"] = syncRecorder.path
        environment["POINTER_BENCHMARK_CRASH_AFTER_STARTING"] = crashAfterStarting ? "1" : "0"
        environment["POINTER_BENCHMARK_CRASH_BEFORE_OWNER"] = crashBeforeOwner ? "1" : "0"
        environment["POINTER_BENCHMARK_CRASH_AFTER_READY"] = crashAfterReady ? "1" : "0"
        environment["POINTER_BENCHMARK_CRASH_BEFORE_OWNER_DELAY"] = String(beforeOwnerDelay)
        environment["POINTER_BENCHMARK_CRASH_BEFORE_OWNER_DONE"] = beforeOwnerDone.path
        environment["POINTER_BENCHMARK_CRASH_AFTER_CHILD_REVOKE"] = crashAfterChildRevoke ? "1" : "0"
        environment["POINTER_BENCHMARK_CRASH_AFTER_CHILD_QUARANTINE"] = crashAfterChildQuarantine ? "1" : "0"
        environment["POINTER_BENCHMARK_CRASH_AFTER_CHILD_CLEANUP_RENAME"] = crashAfterChildCleanupRename ? "1" : "0"
        environment["POINTER_BENCHMARK_CRASH_AFTER_CHILD_FILE_REMOVAL"] = crashAfterChildFileRemoval ? "1" : "0"
        environment["POINTER_BENCHMARK_CRASH_AFTER_CHILD_REVOCATION_REMOVAL"] = crashAfterChildRevocationRemoval ? "1" : "0"
        environment["POINTER_BENCHMARK_CRASH_AFTER_RECOVERY_GUARD"] = crashAfterRecoveryGuard ? "1" : "0"
        environment["POINTER_BENCHMARK_RECOVERY_GUARD_READY"] = recoveryGuardBarrier ? recoveryGuardReady.path : ""
        environment["POINTER_BENCHMARK_RECOVERY_GUARD_RELEASE"] = recoveryGuardRelease.path
        environment["POINTER_BENCHMARK_RECOVERY_GUARD_RECLAIM_READY"] = recoveryGuardReclaimBarrier ? recoveryGuardReclaimReady.path : ""
        environment["POINTER_BENCHMARK_RECOVERY_GUARD_RECLAIM_RELEASE"] = recoveryGuardReclaimRelease.path
        environment["POINTER_FAKE_TRANSACTION_JOURNAL"] = transactionJournal.path
        process.environment = environment
        let pipe = Pipe()
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        return RunningScript(process: process, output: pipe, input: input)
    }

    func waitForReady() throws {
        let handle = try FileHandle(forReadingFrom: readySignal)
        let data = handle.readData(ofLength: 6)
        try? handle.close()
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "READY\n")
    }

    func waitForDone() throws {
        let handle = try FileHandle(forReadingFrom: doneSignal)
        let data = handle.readData(ofLength: 5)
        try? handle.close()
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "DONE\n")
    }

    func waitForBeforeOwnerDone() throws {
        let handle = try FileHandle(forReadingFrom: beforeOwnerDone)
        let data = handle.readData(ofLength: 5)
        try? handle.close()
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "DONE\n")
    }

    func waitForRecoveryGuardReady() throws {
        let handle = try FileHandle(forReadingFrom: recoveryGuardReady)
        let data = handle.readData(ofLength: 6)
        try? handle.close()
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "READY\n")
    }

    func releaseRecoveryGuardBarrier() throws {
        try Data("RELEASE\n".utf8).write(to: recoveryGuardRelease)
    }

    func waitForRecoveryGuardReclaimReady() throws {
        let handle = try FileHandle(forReadingFrom: recoveryGuardReclaimReady)
        let data = handle.readData(ofLength: 6)
        try? handle.close()
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "READY\n")
    }

    func releaseRecoveryGuardReclaimBarrier() throws {
        try Data("RELEASE\n".utf8).write(to: recoveryGuardReclaimRelease)
    }

    func syncEvents() throws -> [String] {
        String(decoding: try Data(contentsOf: syncRecorder), as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
    }

    func writeProfileLock(contents: String) throws {
        try writeFile(at: profileLock, contents: contents)
    }

    func childControlEntries() throws -> [URL] {
        let parent = profileEvidence.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parent.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".benchmark-quality.children.") }
            .sorted { $0.path < $1.path }
    }

    func recoveryGuardQuarantines() throws -> [URL] {
        let parent = recoveryGuard.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parent.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".benchmark-quality.recovery.standard12.reclaimed.") }
            .sorted { $0.path < $1.path }
    }

    func writeFileForTest(at url: URL, contents: String) throws {
        try writeFile(at: url, contents: contents)
    }

    func scriptContains(_ text: String) throws -> Bool {
        try String(contentsOf: script, encoding: .utf8).contains(text)
    }

    func invocations() throws -> [RecordedInvocation] {
        let data = try Data(contentsOf: log)
        return String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                RecordedInvocation(arguments: line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init))
            }
    }

    func partialPaths() -> [URL] {
        (0..<30).map { index in
            root.appendingPathComponent("build/standard12/pair-execution/partial/\(index).json")
        }
    }

    func createRepositoryLayout(at repository: URL) throws {
        let buildRoot = repository.appendingPathComponent("build/standard12")
        let foreignBaselineRoot = buildRoot.appendingPathComponent("baseline")
        let foreignCandidateRoot = buildRoot.appendingPathComponent("candidate")
        let foreignBaselineExecutable = foreignBaselineRoot.appendingPathComponent("Pointer.app/Contents/MacOS/Pointer")
        let foreignCandidateExecutable = foreignCandidateRoot.appendingPathComponent("Pointer.app/Contents/MacOS/Pointer")
        try writeExecutable(at: foreignBaselineExecutable, contents: "#!/bin/sh\nexit 0\n")
        try writeExecutable(at: foreignCandidateExecutable, contents: "#!/bin/sh\nexit 0\n")
        try writeFile(at: foreignBaselineRoot.appendingPathComponent("provenance.json"), contents: "{\"variant\":\"baseline\"}\n")
        try writeFile(at: foreignCandidateRoot.appendingPathComponent("provenance.json"), contents: "{\"variant\":\"candidate\"}\n")
        try writeFile(
            at: repository.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance/standard12/comparisons/pair-eligibility.json"),
            contents: "{\"eligible\":true}\n"
        )
    }

    func installCanonicalFinalizeInputs() throws {
        let configuration = PerformanceConfiguration.standard12
        let baselineRun = PerformanceRunProvenance(
            variant: "baseline",
            outputRoot: baselineRoot.path,
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
            outputRoot: candidateRoot.path,
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
            baselineRoot: baselineRoot.path,
            candidateRoot: candidateRoot.path,
            baselineCommitSHA: PerformanceFixtures.baselineCommit,
            candidateCommitSHA: PerformanceFixtures.commit,
            foundationProvenance: PerformanceFixtures.foundationProvenance
        )
        try PerformanceCanonicalJSON.data(for: baselineRun).write(to: baselineProvenance, options: .atomic)
        try PerformanceCanonicalJSON.data(for: candidateRun).write(to: candidateProvenance, options: .atomic)
        try PerformanceCanonicalJSON.data(for: eligibility).write(to: pairEligibility, options: .atomic)
        if FileManager.default.fileExists(atPath: partialDirectory.path) {
            try FileManager.default.removeItem(at: partialDirectory)
        }
        try FileManager.default.createDirectory(at: partialDirectory, withIntermediateDirectories: true)
        let baselineData = try PerformanceCanonicalJSON.data(for: baselineRun)
        let candidateData = try PerformanceCanonicalJSON.data(for: candidateRun)
        let eligibilityData = try PerformanceCanonicalJSON.data(for: eligibility)
        let baselineHash = PerformanceFixtures.sha256(baselineData)
        let candidateHash = PerformanceFixtures.sha256(candidateData)
        let eligibilityHash = PerformanceFixtures.sha256(eligibilityData)
        for index in 0..<configuration.totalPairs {
            let order: PairOrder = index < configuration.pairsPerOrder ? .baselineFirst : .candidateFirst
            let baselineStart = index * 4 + (order == .baselineFirst ? 0 : 2)
            let candidateStart = index * 4 + (order == .baselineFirst ? 2 : 0)
            let baseline = makeCanonicalResult(
                variant: .baseline,
                pairIndex: index,
                order: order,
                sourceIdentity: PerformanceFixtures.baselineBuild.sourceIdentity,
                runProvenanceSHA256: baselineHash,
                pairEligibilitySHA256: eligibilityHash,
                startSecond: baselineStart
            )
            let candidate = makeCanonicalResult(
                variant: .candidate,
                pairIndex: index,
                order: order,
                sourceIdentity: PerformanceFixtures.build.sourceIdentity,
                runProvenanceSHA256: candidateHash,
                pairEligibilitySHA256: eligibilityHash,
                startSecond: candidateStart
            )
            let partial = PerformancePartialPair(
                fixtureProfile: .standard12,
                pairIndex: index,
                order: order,
                baseline: baseline,
                candidate: candidate
            )
            let partialURL = partialDirectory.appendingPathComponent("\(index).json")
            try PerformanceCanonicalJSON.data(for: partial).write(to: partialURL, options: .atomic)
        }
    }

    func writeCanonicalPreseed(at output: URL) throws {
        let comparisons = output.appendingPathComponent("comparisons", isDirectory: true)
        try FileManager.default.createDirectory(at: comparisons, withIntermediateDirectories: true)
        let eligibilityDestination = comparisons.appendingPathComponent("pair-eligibility.json")
        if !FileManager.default.fileExists(atPath: eligibilityDestination.path) {
            try FileManager.default.copyItem(at: pairEligibility, to: eligibilityDestination)
        }
    }

    func canonicalOutputFileNames(at output: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(at: output, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return try enumerator.compactMap { item -> String? in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory != true else { return nil }
            return String(url.path.dropFirst(output.path.count + 1))
        }.sorted()
    }

    func replaceBaselineExecutableWithSymlink() throws {
        let executable = baselineRoot.appendingPathComponent("Pointer.app/Contents/MacOS/Pointer")
        let target = executable.deletingLastPathComponent().appendingPathComponent("real-pointer")
        try FileManager.default.moveItem(at: executable, to: target)
        try FileManager.default.createSymbolicLink(at: executable, withDestinationURL: target)
    }

    func replaceBaselineProvenanceWithSymlink() throws {
        let target = baselineProvenance.deletingLastPathComponent().appendingPathComponent("real-provenance.json")
        try FileManager.default.moveItem(at: baselineProvenance, to: target)
        try FileManager.default.createSymbolicLink(at: baselineProvenance, withDestinationURL: target)
    }

    func makeMutationHook(mutation: OutputMutation, placement: MutationPlacement) throws -> URL {
        let hook = root.appendingPathComponent("mutation-hook.sh")
        let target = placement == .prePublish ? "$POINTER_BENCHMARK_STAGING" : "$POINTER_BENCHMARK_OUTPUT"
        let contents: String
        switch mutation {
        case .extra:
            contents = "#!/bin/sh\nprintf '%s\\n' extra > \"\(target)/measurements/unexpected.json\"\n"
        case .symlink:
            contents = "#!/bin/sh\nrm -f \"\(target)/measurements/baseline.json\"\nln -s \"$POINTER_FAKE_BASELINE_REPORT\" \"\(target)/measurements/baseline.json\"\n"
        case .invalidJSON:
            contents = "#!/bin/sh\nprintf '%s\\n' '{invalid' > \"\(target)/measurements/baseline.json\"\n"
        }
        try writeExecutable(at: hook, contents: contents)
        return hook
    }

    func makeBlockingHook(killParent: Bool, mutateAfterRelease: Bool) throws -> URL {
        let hook = root.appendingPathComponent("blocking-hook.sh")
        var contents = "#!/bin/sh\nprintf 'READY\\n' > \"${POINTER_FAKE_READY:?}\"\n"
        if killParent {
            contents += "trap '' HUP TERM\nkill -KILL \"$PPID\"\n"
        }
        contents += "IFS= read -r _ < \"${POINTER_FAKE_CHILD_RELEASE:?}\"\n"
        if mutateAfterRelease {
            contents += "printf '%s\\n' late > \"$POINTER_BENCHMARK_STAGING/measurements/late-hook.json\"\n"
        }
        contents += "printf 'DONE\\n' > \"${POINTER_FAKE_DONE:?}\"\n"
        try writeExecutable(at: hook, contents: contents)
        return hook
    }

    func makeForkingDelayedHook() throws -> URL {
        let hook = root.appendingPathComponent("forking-delayed-hook.sh")
        let contents = "#!/bin/sh\n( /bin/sleep 0.1; printf '%s\\n' late > \"$POINTER_BENCHMARK_STAGING/measurements/late-descendant.json\" ) &\nexit 0\n"
        try writeExecutable(at: hook, contents: contents)
        return hook
    }

    func applyExistingOutputNodeMutation(_ mutation: ExistingOutputNodeMutation) throws {
        let fileManager = FileManager.default
        switch mutation {
        case .comparisonsFile:
            try fileManager.removeItem(at: profileEvidence.appendingPathComponent("comparisons"))
            try writeFile(at: profileEvidence.appendingPathComponent("comparisons"), contents: "not-a-directory\n")
        case .provenanceSymlink:
            let provenance = profileEvidence.appendingPathComponent("provenance")
            let target = root.appendingPathComponent("external-provenance", isDirectory: true)
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            try fileManager.moveItem(at: provenance, to: profileEvidence.appendingPathComponent("provenance-real"))
            try fileManager.createSymbolicLink(at: provenance, withDestinationURL: target)
        case .provenanceDanglingSymlink:
            let provenance = profileEvidence.appendingPathComponent("provenance")
            let target = root.appendingPathComponent("missing-provenance")
            try fileManager.moveItem(at: provenance, to: profileEvidence.appendingPathComponent("provenance-real"))
            try fileManager.createSymbolicLink(at: provenance, withDestinationURL: target)
        case .measurementsFile:
            try writeFile(at: profileEvidence.appendingPathComponent("measurements"), contents: "not-a-directory\n")
        case .pairExecutionSymlink:
            let pairExecution = profileEvidence.appendingPathComponent("pair-execution")
            let target = root.appendingPathComponent("external-pair-execution", isDirectory: true)
            try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
            try fileManager.createSymbolicLink(at: pairExecution, withDestinationURL: target)
        }
    }

    func evidenceBytes() throws -> Data {
        try Data(contentsOf: profileEvidence.appendingPathComponent("comparisons/pair-eligibility.json"))
    }

    func profileFileBytes() throws -> [String: Data] {
        guard let enumerator = FileManager.default.enumerator(
            at: profileEvidence,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [:] }
        var files: [String: Data] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory != true else { continue }
            let relativePath = String(url.path.dropFirst(profileEvidence.path.count + 1))
            files[relativePath] = try Data(contentsOf: url)
        }
        return files
    }

    func profileNodeSnapshot() throws -> [String: String] {
        let fileManager = FileManager.default
        var snapshot: [String: String] = [:]

        func visit(_ url: URL, relativePath: String) throws {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let fileType = attributes[.type] as? FileAttributeType
            if fileType == .typeSymbolicLink {
                snapshot[relativePath] = "symlink:\(try fileManager.destinationOfSymbolicLink(atPath: url.path))"
                return
            }
            if fileType == .typeDirectory {
                snapshot[relativePath] = "directory"
                for child in try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: []) {
                    let childRelativePath = relativePath.isEmpty
                        ? child.lastPathComponent
                        : "\(relativePath)/\(child.lastPathComponent)"
                    try visit(child, relativePath: childRelativePath)
                }
                return
            }
            snapshot[relativePath] = "file:\(try Data(contentsOf: url).base64EncodedString())"
        }

        try visit(profileEvidence, relativePath: "")
        return snapshot
    }

    func directorySnapshot(at directory: URL) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else { return [] }
        return try enumerator.compactMap { item -> String? in
            guard let url = item as? URL else { return nil }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory != true else { return nil }
            return String(url.path.dropFirst(directory.path.count + 1))
        }.sorted()
    }

    func transientPublishDirectories() throws -> [URL] {
        let parent = profileEvidence.deletingLastPathComponent()
        return try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
            .filter { url in
                let name = url.lastPathComponent
                return name.hasPrefix(".benchmark-quality.pending.") || name.hasPrefix(".benchmark-quality.backup.")
            }
    }

    func expectedTrialArguments(for invocation: RecordedInvocation) -> [String] {
        let variant = invocation.variant ?? ""
        let commit = variant == "baseline" ? baselineCommit : candidateCommit
        let provenance = variant == "baseline" ? baselineProvenance.path : candidateProvenance.path
        return [
            "--quality-performance", "--format", "json", "--operation", "trial",
            "--fixture-profile", "standard12", "--variant", variant,
            "--pair-order", invocation.pairOrder ?? "",
            "--pair-index", String(invocation.pairIndex ?? -1),
            "--source-commit-sha", commit,
            "--run-provenance-file", provenance,
            "--pair-eligibility-file", pairEligibility.path,
            "--partial-pair-directory", partialDirectory.path
        ]
    }

    func expectedFinalizeArguments(for invocation: RecordedInvocation) -> [String] {
        [
            "--quality-performance", "--format", "json", "--operation", "finalize",
            "--fixture-profile", "standard12",
            "--partial-pair-directory", partialDirectory.path,
            "--baseline-run-provenance-file", baselineProvenance.path,
            "--candidate-run-provenance-file", candidateProvenance.path,
            "--pair-eligibility-file", pairEligibility.path,
            "--output-dir", invocation.outputDirectoryURL.path
        ]
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    private func arguments(
        useDefaultBuildInputs: Bool = false,
        omitRunProvenance: String? = nil,
        outputDirectoryOverride: URL? = nil,
        repositoryRootOverride: URL? = nil
    ) -> [String] {
        let argumentRoot = repositoryRootOverride ?? root
        let baselineRoot = argumentRoot.appendingPathComponent("build/standard12/baseline")
        let candidateRoot = argumentRoot.appendingPathComponent("build/standard12/candidate")
        let baselineProvenance = baselineRoot.appendingPathComponent("provenance.json")
        let candidateProvenance = candidateRoot.appendingPathComponent("provenance.json")
        let pairEligibility = argumentRoot.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance/standard12/comparisons/pair-eligibility.json")
        let defaultOutput = argumentRoot.appendingPathComponent(".codex/sdd/reports/quality-campaign/performance/standard12")
        var values = [
            "--fixture-profile", "standard12",
            "--baseline-commit-sha", baselineCommit,
            "--candidate-commit-sha", candidateCommit,
            "--baseline-root", baselineRoot.path,
            "--candidate-root", candidateRoot.path,
            "--pair-eligibility-file", pairEligibility.path,
            "--output-dir", (outputDirectoryOverride ?? defaultOutput).path,
            "--runner", runner.path
        ]
        if !useDefaultBuildInputs {
            let buildInputs = [
                "--baseline-executable", baselineRoot.appendingPathComponent("Pointer.app/Contents/MacOS/Pointer").path,
                "--candidate-executable", candidateRoot.appendingPathComponent("Pointer.app/Contents/MacOS/Pointer").path
            ]
            values.insert(contentsOf: buildInputs, at: 10)
        }
        var provenanceInputs: [String] = []
        if omitRunProvenance != "baseline" {
            provenanceInputs += ["--baseline-run-provenance", baselineProvenance.path]
        }
        if omitRunProvenance != "candidate" {
            provenanceInputs += ["--candidate-run-provenance", candidateProvenance.path]
        }
        values.insert(contentsOf: provenanceInputs, at: useDefaultBuildInputs ? 10 : 14)
        return values
    }

    private func makeCanonicalResult(
        variant: PerformanceVariant,
        pairIndex: Int,
        order: PairOrder,
        sourceIdentity: SourceIdentity,
        runProvenanceSHA256: String,
        pairEligibilitySHA256: String,
        startSecond: Int
    ) -> PerformanceTrialResult {
        let request = PerformanceTrialRequest(
            variant: variant,
            fixtureProfile: .standard12,
            pairIndex: pairIndex,
            order: order,
            sampleIndex: pairIndex
        )
        let samples = PerformanceMetricID.allCases.enumerated().map { offset, metricID in
            PerformanceTrialMetricSample(
                metricID: metricID,
                unit: metricID.canonicalUnit,
                status: .measured,
                value: metricID == .allocations
                    ? Double(offset + 1)
                    : Double(offset + 1) + Double(pairIndex) / 100,
                diagnostic: nil
            )
        }
        let start = String(format: "2026-08-31T12:%02d:%02d.000Z", startSecond / 60, startSecond % 60)
        let end = String(format: "2026-08-31T12:%02d:%02d.500Z", startSecond / 60, startSecond % 60)
        return PerformanceTrialResult(
            request: request,
            sourceIdentity: sourceIdentity,
            runProvenanceSHA256: runProvenanceSHA256,
            pairEligibilitySHA256: pairEligibilitySHA256,
            startedAtUTC: start,
            endedAtUTC: end,
            warmupCountExecuted: 5,
            samples: samples,
            modelEvidence: PerformanceModelTrialEvidence(
                publicationCount: 2,
                modelChecksum: variant == .baseline ? "baseline-model-checksum" : "candidate-model-checksum",
                finalStateValid: true
            ),
            rendererEvidence: PerformanceRendererTrialEvidence(
                frameCount: 1,
                missedFrameCount: 0,
                instrumentationStatus: "fixture",
                semanticPass: true
            )
        )
    }

    private static let runnerScript = #"""
#!/bin/bash
set -euo pipefail

log_path="${POINTER_FAKE_LOG:?}"
failure_at="${POINTER_FAKE_FAIL_AT:-0}"
invocation_count=0
if [[ -f "$log_path" ]]; then
    invocation_count="$(wc -l < "$log_path" | tr -d ' ')"
fi
invocation_count=$((invocation_count + 1))
first_argument=true
for argument in "$@"; do
    if [[ "$first_argument" == true ]]; then
        first_argument=false
    else
        printf '\t' >> "$log_path"
    fi
    printf '%s' "$argument" >> "$log_path"
done
printf '\n' >> "$log_path"
if [[ "$failure_at" != 0 && "$invocation_count" == "$failure_at" ]]; then
    exit 37
fi
if [[ "${POINTER_FAKE_HOLD_PARENT:-0}" == "1" && "$invocation_count" == "1" ]]; then
    printf 'READY\n' > "${POINTER_FAKE_READY:?}"
    kill -STOP "$PPID"
fi

partial=""
profile=""
partial_directory=""
pair_order=""
pair_index=""
variant=""
operation=""
output_dir=""
for ((index = 1; index <= $#; index++)); do
    argument="${!index}"
    next_index=$((index + 1))
    next="${!next_index-}"
    case "$argument" in
        --operation) operation="$next" ;;
        --fixture-profile) profile="$next" ;;
        --variant) variant="$next" ;;
        --pair-order) pair_order="$next" ;;
        --pair-index) pair_index="$next" ;;
        --partial-pair-directory) partial_directory="$next" ;;
        --output-dir) output_dir="$next" ;;
    esac
done
if [[ "$operation" == "trial" && "${POINTER_FAKE_KILL_PARENT_WITH_CHILD:-0}" == "1" && "$invocation_count" == "1" ]]; then
    printf 'READY\n' > "${POINTER_FAKE_READY:?}"
    trap '' HUP TERM
    kill -KILL "$PPID"
    IFS= read -r _ < "${POINTER_FAKE_CHILD_RELEASE:?}"
    printf 'DONE\n'
fi
if [[ "$operation" == "trial" && "${POINTER_FAKE_HOLD_CHILD:-0}" == "1" && "$invocation_count" == "1" ]]; then
    printf 'READY\n' > "${POINTER_FAKE_READY:?}"
    IFS= read -r _ < "${POINTER_FAKE_CHILD_RELEASE:?}"
fi
if [[ "$operation" == "finalize" && "${POINTER_FAKE_FINALIZER_KILL:-0}" == "1" ]]; then
    [[ -f "${POINTER_FAKE_TRANSACTION_JOURNAL:?}" ]] || exit 38
    kill -KILL "$PPID"
fi
if [[ "$operation" == "trial" && -n "$partial_directory" ]]; then
    partial="$partial_directory/$pair_index.json"
    mkdir -p "$(dirname -- "$partial")"
    sample_json='{"metricID":"model","unit":"nanoseconds","value":1}'
    sample_json="$sample_json,{\"metricID\":\"renderer\",\"unit\":\"milliseconds\",\"value\":1}"
    sample_json="$sample_json,{\"metricID\":\"compositor\",\"unit\":\"milliseconds\",\"value\":1}"
    sample_json="$sample_json,{\"metricID\":\"combinedFrame\",\"unit\":\"milliseconds\",\"value\":1}"
    sample_json="$sample_json,{\"metricID\":\"launchCold\",\"unit\":\"milliseconds\",\"value\":1}"
    sample_json="$sample_json,{\"metricID\":\"launchWarm\",\"unit\":\"milliseconds\",\"value\":1}"
    sample_json="$sample_json,{\"metricID\":\"allocations\",\"unit\":\"bytes\",\"value\":1}"
    sample_json="$sample_json,{\"metricID\":\"redrawLayout\",\"unit\":\"milliseconds\",\"value\":1}"
    sample_json="$sample_json,{\"metricID\":\"responsiveness\",\"unit\":\"milliseconds\",\"value\":1}"
    sample_json="$sample_json,{\"metricID\":\"inputToVisible\",\"unit\":\"milliseconds\",\"value\":1}"
    sample_json="$sample_json,{\"metricID\":\"memoryRSS\",\"unit\":\"bytes\",\"value\":1}"
    result_json() {
        local result_variant="$1"
        local result_commit="$2"
        printf '{"schemaVersion":1,"request":{"schemaVersion":1,"variant":"%s","fixtureProfile":"%s","pairIndex":%s,"order":"%s","sampleIndex":%s},"sourceIdentity":{"kind":"sourceCommitSHA","value":"%s"},"runProvenanceSHA256":"%064d","pairEligibilitySHA256":"%064d","startedAtUTC":"2026-08-31T12:00:00Z","endedAtUTC":"2026-08-31T12:00:01Z","warmupCountExecuted":5,"samples":[%s],"modelEvidence":{"publicationCount":2,"modelChecksum":"checksum","finalStateValid":true},"rendererEvidence":{"frameCount":1,"missedFrameCount":0,"instrumentationStatus":"fixture","semanticPass":true}}' "$result_variant" "$profile" "$pair_index" "$pair_order" "$pair_index" "$result_commit" 1 2 "$sample_json"
    }
    baseline_result="$(result_json baseline 1111111111111111111111111111111111111111)"
    candidate_result="$(result_json candidate 2222222222222222222222222222222222222222)"
    printf '{"schemaVersion":1,"fixtureProfile":"%s","pairIndex":%s,"sampleIndex":%s,"order":"%s","baseline":%s,"candidate":%s}\n' "$profile" "$pair_index" "$pair_index" "$pair_order" "$baseline_result" "$candidate_result" > "$partial"
fi
if [[ "$operation" == "finalize" && -n "$output_dir" ]]; then
    mkdir -p "$output_dir/measurements" "$output_dir/pair-execution"
    cp "$POINTER_FAKE_BASELINE_REPORT" "$output_dir/measurements/baseline.json"
    cp "$POINTER_FAKE_CANDIDATE_REPORT" "$output_dir/measurements/candidate.json"
    cp "$POINTER_FAKE_PAIR_ARTIFACT" "$output_dir/pair-execution/pair-execution.json"
    if [[ "${POINTER_FAKE_FINALIZER_SYMLINK_FILE:-0}" == "1" ]]; then
        rm -f "$output_dir/measurements/baseline.json"
        ln -s "$POINTER_FAKE_BASELINE_REPORT" "$output_dir/measurements/baseline.json"
    fi
    if [[ "${POINTER_FAKE_FINALIZER_EXTRA_FILE:-0}" == "1" ]]; then
        printf '%s\n' extra > "$output_dir/measurements/unexpected.json"
    fi
fi
"""#

    private func writeExecutable(at url: URL, contents: String) throws {
        try writeFile(at: url, contents: contents)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func writeFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

}
