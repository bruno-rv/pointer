import Foundation
import CryptoKit
import Darwin

private struct PerformanceDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

private enum PerformanceStrictJSON {
    static func requireExactKeys(_ decoder: Decoder, _ keys: Set<String>, _ message: String) throws {
        let container = try decoder.container(keyedBy: PerformanceDynamicCodingKey.self)
        try PerformanceTrialValidation.require(
            Set(container.allKeys.map(\.stringValue)) == keys,
            message
        )
    }
}

/// Immutable variant identity used by the performance wire protocol.
public enum PerformanceVariant: String, Codable, Sendable, Equatable {
    case baseline
    case candidate
}

/// The exact input for one paired quality trial. It deliberately carries only
/// pair identity: provenance and eligibility are read from their separately
/// hashed canonical files by the CLI and retained on the result.
public struct PerformanceTrialRequest: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let variant: PerformanceVariant
    public let fixtureProfile: PerformanceFixtureProfile
    public let pairIndex: Int
    public let order: PairOrder
    public let sampleIndex: Int

    public init(
        schemaVersion: Int = PerformanceTrialRequest.currentSchemaVersion,
        variant: PerformanceVariant,
        fixtureProfile: PerformanceFixtureProfile,
        pairIndex: Int,
        order: PairOrder,
        sampleIndex: Int
    ) {
        self.schemaVersion = schemaVersion
        self.variant = variant
        self.fixtureProfile = fixtureProfile
        self.pairIndex = pairIndex
        self.order = order
        self.sampleIndex = sampleIndex
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case variant
        case fixtureProfile
        case pairIndex
        case order
        case sampleIndex
    }

    public init(from decoder: Decoder) throws {
        try PerformanceStrictJSON.requireExactKeys(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue)),
            "trial request fields are not exact"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        variant = try container.decode(PerformanceVariant.self, forKey: .variant)
        fixtureProfile = try container.decode(PerformanceFixtureProfile.self, forKey: .fixtureProfile)
        pairIndex = try container.decode(Int.self, forKey: .pairIndex)
        order = try container.decode(PairOrder.self, forKey: .order)
        sampleIndex = try container.decode(Int.self, forKey: .sampleIndex)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(variant, forKey: .variant)
        try container.encode(fixtureProfile, forKey: .fixtureProfile)
        try container.encode(pairIndex, forKey: .pairIndex)
        try container.encode(order, forKey: .order)
        try container.encode(sampleIndex, forKey: .sampleIndex)
    }

    public func validate() throws {
        try PerformanceTrialValidation.require(
            schemaVersion == Self.currentSchemaVersion,
            "unsupported trial request schemaVersion"
        )
        try PerformanceTrialValidation.require(
            pairIndex >= 0 && pairIndex < 30,
            "trial pair index is outside the canonical range"
        )
        let expectedOrder: PairOrder = pairIndex < 15 ? .baselineFirst : .candidateFirst
        try PerformanceTrialValidation.require(
            order == expectedOrder,
            "trial pair index does not match pair order"
        )
        try PerformanceTrialValidation.require(
            sampleIndex == pairIndex,
            "trial sample index must equal pair index"
        )
    }
}

public struct PerformanceTrialMetricSample: Codable, Sendable, Equatable {
    public let metricID: PerformanceMetricID
    public let unit: PerformanceMetricUnit
    public let status: MeasurementStatus
    public let value: Double?
    public let diagnostic: String?

    public init(
        metricID: PerformanceMetricID,
        unit: PerformanceMetricUnit,
        status: MeasurementStatus,
        value: Double?,
        diagnostic: String?
    ) {
        self.metricID = metricID
        self.unit = unit
        self.status = status
        self.value = value
        self.diagnostic = diagnostic
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case metricID
        case unit
        case status
        case value
        case diagnostic
    }

    public init(from decoder: Decoder) throws {
        try PerformanceStrictJSON.requireExactKeys(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue)),
            "metric sample fields are not exact"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metricID = try container.decode(PerformanceMetricID.self, forKey: .metricID)
        unit = try container.decode(PerformanceMetricUnit.self, forKey: .unit)
        status = try container.decode(MeasurementStatus.self, forKey: .status)
        value = try container.decodeIfPresent(Double.self, forKey: .value)
        diagnostic = try container.decodeIfPresent(String.self, forKey: .diagnostic)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metricID, forKey: .metricID)
        try container.encode(unit, forKey: .unit)
        try container.encode(status, forKey: .status)
        if let value {
            try container.encode(value, forKey: .value)
        } else {
            try container.encodeNil(forKey: .value)
        }
        if let diagnostic {
            try container.encode(diagnostic, forKey: .diagnostic)
        } else {
            try container.encodeNil(forKey: .diagnostic)
        }
    }
}

public typealias MetricSample = PerformanceTrialMetricSample

public struct PerformanceModelTrialEvidence: Codable, Sendable, Equatable {
    public let publicationCount: Int
    public let modelChecksum: String
    public let finalStateValid: Bool

    public init(publicationCount: Int, modelChecksum: String, finalStateValid: Bool) {
        self.publicationCount = publicationCount
        self.modelChecksum = modelChecksum
        self.finalStateValid = finalStateValid
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case publicationCount
        case modelChecksum
        case finalStateValid
    }

    public init(from decoder: Decoder) throws {
        try PerformanceStrictJSON.requireExactKeys(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue)),
            "model evidence fields are not exact"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        publicationCount = try container.decode(Int.self, forKey: .publicationCount)
        modelChecksum = try container.decode(String.self, forKey: .modelChecksum)
        finalStateValid = try container.decode(Bool.self, forKey: .finalStateValid)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(publicationCount, forKey: .publicationCount)
        try container.encode(modelChecksum, forKey: .modelChecksum)
        try container.encode(finalStateValid, forKey: .finalStateValid)
    }
}

public struct PerformanceRendererTrialEvidence: Codable, Sendable, Equatable {
    public let frameCount: Int
    public let missedFrameCount: Int
    public let instrumentationStatus: String
    public let semanticPass: Bool

    public init(
        frameCount: Int,
        missedFrameCount: Int,
        instrumentationStatus: String,
        semanticPass: Bool
    ) {
        self.frameCount = frameCount
        self.missedFrameCount = missedFrameCount
        self.instrumentationStatus = instrumentationStatus
        self.semanticPass = semanticPass
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case frameCount
        case missedFrameCount
        case instrumentationStatus
        case semanticPass
    }

    public init(from decoder: Decoder) throws {
        try PerformanceStrictJSON.requireExactKeys(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue)),
            "renderer evidence fields are not exact"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        frameCount = try container.decode(Int.self, forKey: .frameCount)
        missedFrameCount = try container.decode(Int.self, forKey: .missedFrameCount)
        instrumentationStatus = try container.decode(String.self, forKey: .instrumentationStatus)
        semanticPass = try container.decode(Bool.self, forKey: .semanticPass)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(frameCount, forKey: .frameCount)
        try container.encode(missedFrameCount, forKey: .missedFrameCount)
        try container.encode(instrumentationStatus, forKey: .instrumentationStatus)
        try container.encode(semanticPass, forKey: .semanticPass)
    }
}

internal struct PerformanceTrialSample: Codable, Sendable, Equatable {
    let samples: [PerformanceTrialMetricSample]
    let modelEvidence: PerformanceModelTrialEvidence
    let rendererEvidence: PerformanceRendererTrialEvidence

    init(
        samples: [PerformanceTrialMetricSample],
        modelEvidence: PerformanceModelTrialEvidence,
        rendererEvidence: PerformanceRendererTrialEvidence
    ) {
        self.samples = samples
        self.modelEvidence = modelEvidence
        self.rendererEvidence = rendererEvidence
    }

    func validate() throws {
        try PerformanceTrialValidation.require(
            Set(samples.map(\.metricID)).count == samples.count,
            "trial metric IDs must be unique"
        )
        try PerformanceTrialValidation.require(
            samples.map(\.metricID) == PerformanceMetricID.allCases,
            "trial metric samples are not in canonical order"
        )
        for sample in samples {
            try PerformanceTrialValidation.require(
                sample.unit == sample.metricID.canonicalUnit,
                "trial metric unit does not match its canonical metric"
            )
            switch sample.status {
            case .measured:
                try PerformanceTrialValidation.require(
                    sample.value.map { $0.isFinite && $0 > 0 } == true,
                    "measured trial metric values must be finite and strictly positive"
                )
                try PerformanceTrialValidation.require(
                    sample.diagnostic == nil,
                    "measured trial metrics cannot carry a diagnostic"
                )
            case .failed, .unmeasured:
                try PerformanceTrialValidation.require(
                    sample.value == nil,
                    "unmeasured trial metrics cannot carry a value"
                )
                try PerformanceTrialValidation.require(
                    sample.diagnostic?.isEmpty == false,
                    "unmeasured trial metrics require a diagnostic"
                )
            }
        }
        try PerformanceTrialValidation.require(
            modelEvidence.publicationCount >= 0,
            "trial publication count must be nonnegative"
        )
        try PerformanceTrialValidation.require(
            !modelEvidence.modelChecksum.isEmpty,
            "trial model checksum is required"
        )
        try PerformanceTrialValidation.require(
            rendererEvidence.frameCount >= 0 && rendererEvidence.missedFrameCount >= 0,
            "trial renderer counts must be nonnegative"
        )
        try PerformanceTrialValidation.require(
            rendererEvidence.missedFrameCount <= rendererEvidence.frameCount,
            "trial renderer missed-frame count is incoherent"
        )
        try PerformanceTrialValidation.require(
            !rendererEvidence.instrumentationStatus.isEmpty,
            "trial renderer instrumentation status is required"
        )
    }
}

public struct PerformanceTrialResult: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let request: PerformanceTrialRequest
    public let sourceIdentity: SourceIdentity
    public let runProvenanceSHA256: String
    public let pairEligibilitySHA256: String
    public let startedAtUTC: String
    public let endedAtUTC: String
    public let warmupCountExecuted: Int
    public let samples: [PerformanceTrialMetricSample]
    public let modelEvidence: PerformanceModelTrialEvidence
    public let rendererEvidence: PerformanceRendererTrialEvidence

    internal var sampleIndex: Int { request.sampleIndex }
    internal var metricSamples: [PerformanceTrialMetricSample] { samples }

    public init(
        schemaVersion: Int = PerformanceTrialResult.currentSchemaVersion,
        request: PerformanceTrialRequest,
        sourceIdentity: SourceIdentity,
        runProvenanceSHA256: String,
        pairEligibilitySHA256: String,
        startedAtUTC: String,
        endedAtUTC: String,
        warmupCountExecuted: Int,
        samples: [PerformanceTrialMetricSample],
        modelEvidence: PerformanceModelTrialEvidence,
        rendererEvidence: PerformanceRendererTrialEvidence
    ) {
        self.schemaVersion = schemaVersion
        self.request = request
        self.sourceIdentity = sourceIdentity
        self.runProvenanceSHA256 = runProvenanceSHA256
        self.pairEligibilitySHA256 = pairEligibilitySHA256
        self.startedAtUTC = startedAtUTC
        self.endedAtUTC = endedAtUTC
        self.warmupCountExecuted = warmupCountExecuted
        self.samples = samples
        self.modelEvidence = modelEvidence
        self.rendererEvidence = rendererEvidence
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case request
        case sourceIdentity
        case runProvenanceSHA256
        case pairEligibilitySHA256
        case startedAtUTC
        case endedAtUTC
        case warmupCountExecuted
        case samples
        case modelEvidence
        case rendererEvidence
    }

    public init(from decoder: Decoder) throws {
        try PerformanceStrictJSON.requireExactKeys(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue)),
            "trial result fields are not exact"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        request = try container.decode(PerformanceTrialRequest.self, forKey: .request)
        try PerformanceStrictJSON.requireExactKeys(
            try container.superDecoder(forKey: .sourceIdentity),
            ["kind", "value"],
            "trial source identity fields are not exact"
        )
        sourceIdentity = try container.decode(SourceIdentity.self, forKey: .sourceIdentity)
        runProvenanceSHA256 = try container.decode(String.self, forKey: .runProvenanceSHA256)
        pairEligibilitySHA256 = try container.decode(String.self, forKey: .pairEligibilitySHA256)
        startedAtUTC = try container.decode(String.self, forKey: .startedAtUTC)
        endedAtUTC = try container.decode(String.self, forKey: .endedAtUTC)
        warmupCountExecuted = try container.decode(Int.self, forKey: .warmupCountExecuted)
        samples = try container.decode([PerformanceTrialMetricSample].self, forKey: .samples)
        modelEvidence = try container.decode(PerformanceModelTrialEvidence.self, forKey: .modelEvidence)
        rendererEvidence = try container.decode(PerformanceRendererTrialEvidence.self, forKey: .rendererEvidence)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(request, forKey: .request)
        try container.encode(sourceIdentity, forKey: .sourceIdentity)
        try container.encode(runProvenanceSHA256, forKey: .runProvenanceSHA256)
        try container.encode(pairEligibilitySHA256, forKey: .pairEligibilitySHA256)
        try container.encode(startedAtUTC, forKey: .startedAtUTC)
        try container.encode(endedAtUTC, forKey: .endedAtUTC)
        try container.encode(warmupCountExecuted, forKey: .warmupCountExecuted)
        try container.encode(samples, forKey: .samples)
        try container.encode(modelEvidence, forKey: .modelEvidence)
        try container.encode(rendererEvidence, forKey: .rendererEvidence)
    }

    internal init(
        request: PerformanceTrialRequest,
        sourceIdentity: SourceIdentity,
        runProvenanceSHA256: String,
        pairEligibilitySHA256: String,
        startedAtUTC: String,
        endedAtUTC: String,
        sample: PerformanceTrialSample
    ) {
        self.init(
            request: request,
            sourceIdentity: sourceIdentity,
            runProvenanceSHA256: runProvenanceSHA256,
            pairEligibilitySHA256: pairEligibilitySHA256,
            startedAtUTC: startedAtUTC,
            endedAtUTC: endedAtUTC,
            warmupCountExecuted: 5,
            samples: sample.samples,
            modelEvidence: sample.modelEvidence,
            rendererEvidence: sample.rendererEvidence
        )
    }

    func validate() throws {
        try PerformanceTrialValidation.require(schemaVersion == Self.currentSchemaVersion, "unsupported trial result schemaVersion")
        try request.validate()
        try PerformanceTrialValidation.require(sourceIdentity.kind == .sourceCommitSHA ? sourceIdentity.value.isLowercaseHex(count: 40) : sourceIdentity.value.isLowercaseHex(count: 64), "trial source identity is invalid")
        try PerformanceTrialValidation.require(runProvenanceSHA256.isLowercaseHex(count: 64), "trial provenance hash is invalid")
        try PerformanceTrialValidation.require(pairEligibilitySHA256.isLowercaseHex(count: 64), "trial eligibility hash is invalid")
        try PerformanceTrialValidation.require(warmupCountExecuted == 5, "trial warmup count is not canonical")
        try PerformanceTimestamp.validate(startedAtUTC)
        try PerformanceTimestamp.validate(endedAtUTC)
        guard let start = PerformanceTimestamp.date(from: startedAtUTC),
              let end = PerformanceTimestamp.date(from: endedAtUTC)
        else {
            throw PerformanceValidationError.invalid("trial timestamps are not valid UTC timestamps")
        }
        try PerformanceTrialValidation.require(start <= end, "trial timestamps are out of order")
        try PerformanceTrialSample(
            samples: samples,
            modelEvidence: modelEvidence,
            rendererEvidence: rendererEvidence
        ).validate()
    }

    internal func replacing(
        startedAtUTC: String? = nil,
        endedAtUTC: String? = nil,
        samples: [PerformanceTrialMetricSample]? = nil
    ) -> PerformanceTrialResult {
        PerformanceTrialResult(
            schemaVersion: schemaVersion,
            request: request,
            sourceIdentity: sourceIdentity,
            runProvenanceSHA256: runProvenanceSHA256,
            pairEligibilitySHA256: pairEligibilitySHA256,
            startedAtUTC: startedAtUTC ?? self.startedAtUTC,
            endedAtUTC: endedAtUTC ?? self.endedAtUTC,
            warmupCountExecuted: warmupCountExecuted,
            samples: samples ?? self.samples,
            modelEvidence: modelEvidence,
            rendererEvidence: rendererEvidence
        )
    }
}

public struct PerformanceExternalTrialBinding: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let request: PerformanceTrialRequest
    public let sourceIdentity: SourceIdentity
    public let runProvenanceSHA256: String
    public let pairEligibilitySHA256: String
    public let startedAtUTC: String
    public let endedAtUTC: String

    public init(
        schemaVersion: Int = PerformanceExternalTrialBinding.currentSchemaVersion,
        request: PerformanceTrialRequest,
        sourceIdentity: SourceIdentity,
        runProvenanceSHA256: String,
        pairEligibilitySHA256: String,
        startedAtUTC: String,
        endedAtUTC: String
    ) {
        self.schemaVersion = schemaVersion
        self.request = request
        self.sourceIdentity = sourceIdentity
        self.runProvenanceSHA256 = runProvenanceSHA256
        self.pairEligibilitySHA256 = pairEligibilitySHA256
        self.startedAtUTC = startedAtUTC
        self.endedAtUTC = endedAtUTC
    }

    public func validate() throws {
        try PerformanceTrialValidation.require(schemaVersion == Self.currentSchemaVersion, "unsupported external trial binding schemaVersion")
        try request.validate()
        try PerformanceTrialValidation.require(sourceIdentity.value.isLowercaseHex(count: sourceIdentity.kind == .sourceCommitSHA ? 40 : 64), "external trial source identity is invalid")
        try PerformanceTrialValidation.require(runProvenanceSHA256.isLowercaseHex(count: 64), "external trial provenance hash is invalid")
        try PerformanceTrialValidation.require(pairEligibilitySHA256.isLowercaseHex(count: 64), "external trial eligibility hash is invalid")
        try PerformanceTimestamp.validate(startedAtUTC)
        try PerformanceTimestamp.validate(endedAtUTC)
        guard let start = PerformanceTimestamp.date(from: startedAtUTC), let end = PerformanceTimestamp.date(from: endedAtUTC) else {
            throw PerformanceValidationError.invalid("external trial timestamps are invalid")
        }
        try PerformanceTrialValidation.require(start <= end, "external trial timestamps are out of order")
    }
}

public struct PerformanceExternalTrialScalarMeasurement: Codable, Sendable, Equatable {
    public let metricID: PerformanceMetricID
    public let unit: PerformanceMetricUnit
    public let status: MeasurementStatus
    public let value: Double?
    public let diagnostic: String?

    public init(
        metricID: PerformanceMetricID,
        unit: PerformanceMetricUnit,
        status: MeasurementStatus,
        value: Double?,
        diagnostic: String?
    ) {
        self.metricID = metricID
        self.unit = unit
        self.status = status
        self.value = value
        self.diagnostic = diagnostic
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case metricID
        case unit
        case status
        case value
        case diagnostic
    }

    public init(from decoder: Decoder) throws {
        try PerformanceStrictJSON.requireExactKeys(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue)),
            "external scalar fields are not exact"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metricID = try container.decode(PerformanceMetricID.self, forKey: .metricID)
        unit = try container.decode(PerformanceMetricUnit.self, forKey: .unit)
        status = try container.decode(MeasurementStatus.self, forKey: .status)
        value = try container.decodeIfPresent(Double.self, forKey: .value)
        diagnostic = try container.decodeIfPresent(String.self, forKey: .diagnostic)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metricID, forKey: .metricID)
        try container.encode(unit, forKey: .unit)
        try container.encode(status, forKey: .status)
        if let value { try container.encode(value, forKey: .value) } else { try container.encodeNil(forKey: .value) }
        if let diagnostic { try container.encode(diagnostic, forKey: .diagnostic) } else { try container.encodeNil(forKey: .diagnostic) }
    }
}

public struct PerformanceExternalTrialSidecar: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1
    public static let requiredMetricIDs: [PerformanceMetricID] = [
        .compositor, .combinedFrame, .launchCold, .launchWarm,
        .allocations, .redrawLayout, .responsiveness, .inputToVisible
    ]

    public let schemaVersion: Int
    public let binding: PerformanceExternalTrialBinding
    public let measurements: [PerformanceExternalTrialScalarMeasurement]

    public init(
        schemaVersion: Int = PerformanceExternalTrialSidecar.currentSchemaVersion,
        binding: PerformanceExternalTrialBinding,
        measurements: [PerformanceExternalTrialScalarMeasurement]
    ) {
        self.schemaVersion = schemaVersion
        self.binding = binding
        self.measurements = measurements
    }

    public func validate() throws {
        try PerformanceTrialValidation.require(schemaVersion == Self.currentSchemaVersion, "unsupported external trial sidecar schemaVersion")
        try binding.validate()
        try PerformanceTrialValidation.require(measurements.map(\.metricID) == Self.requiredMetricIDs, "external trial sidecar metrics are incomplete or out of order")
        for measurement in measurements {
            try PerformanceTrialValidation.require(measurement.unit == measurement.metricID.canonicalUnit, "external sidecar metric unit is invalid")
            switch measurement.status {
            case .measured:
                try PerformanceTrialValidation.require(measurement.value.map { $0.isFinite && $0 > 0 } == true, "measured external sidecar scalar is invalid")
                try PerformanceTrialValidation.require(measurement.diagnostic == nil, "measured external sidecar scalar cannot carry a diagnostic")
            case .failed, .unmeasured:
                try PerformanceTrialValidation.require(measurement.value == nil, "unmeasured external sidecar scalar cannot carry a value")
                try PerformanceTrialValidation.require(measurement.diagnostic?.isEmpty == false, "unmeasured external sidecar scalar requires a diagnostic")
            }
        }
    }
}

public struct PerformanceExternalAggregateBinding: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let variant: PerformanceVariant
    public let fixtureProfile: PerformanceFixtureProfile
    public let sourceIdentity: SourceIdentity
    public let runProvenanceSHA256: String
    public let pairEligibilitySHA256: String

    public init(
        schemaVersion: Int = PerformanceExternalAggregateBinding.currentSchemaVersion,
        variant: PerformanceVariant,
        fixtureProfile: PerformanceFixtureProfile,
        sourceIdentity: SourceIdentity,
        runProvenanceSHA256: String,
        pairEligibilitySHA256: String
    ) {
        self.schemaVersion = schemaVersion
        self.variant = variant
        self.fixtureProfile = fixtureProfile
        self.sourceIdentity = sourceIdentity
        self.runProvenanceSHA256 = runProvenanceSHA256
        self.pairEligibilitySHA256 = pairEligibilitySHA256
    }

    public func validate() throws {
        try PerformanceTrialValidation.require(schemaVersion == Self.currentSchemaVersion, "unsupported external aggregate binding schemaVersion")
        try PerformanceTrialValidation.require(sourceIdentity.value.isLowercaseHex(count: sourceIdentity.kind == .sourceCommitSHA ? 40 : 64), "external aggregate source identity is invalid")
        try PerformanceTrialValidation.require(runProvenanceSHA256.isLowercaseHex(count: 64), "external aggregate provenance hash is invalid")
        try PerformanceTrialValidation.require(pairEligibilitySHA256.isLowercaseHex(count: 64), "external aggregate eligibility hash is invalid")
    }
}

public struct PerformanceExternalAggregateSidecar: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let binding: PerformanceExternalAggregateBinding
    public let resultSHA256s: [String]
    public let memory: MemoryMeasurement
    public let resilience: ResilienceMeasurement

    public init(
        schemaVersion: Int = PerformanceExternalAggregateSidecar.currentSchemaVersion,
        binding: PerformanceExternalAggregateBinding,
        resultSHA256s: [String],
        memory: MemoryMeasurement,
        resilience: ResilienceMeasurement
    ) {
        self.schemaVersion = schemaVersion
        self.binding = binding
        self.resultSHA256s = resultSHA256s
        self.memory = memory
        self.resilience = resilience
    }

    public func validate() throws {
        try PerformanceTrialValidation.require(schemaVersion == Self.currentSchemaVersion, "unsupported external aggregate sidecar schemaVersion")
        try binding.validate()
        try PerformanceTrialValidation.require(resultSHA256s.count == 30, "external aggregate result hash count is invalid")
        try PerformanceTrialValidation.require(resultSHA256s.allSatisfy { $0.isLowercaseHex(count: 64) }, "external aggregate result hash is invalid")
        try PerformanceTrialValidation.require(memory.windowSeconds == PerformanceConfiguration.standard.memoryWindowSeconds, "external aggregate memory window is invalid")
        try PerformanceTrialValidation.require(memory.sampleIntervalSeconds == PerformanceConfiguration.standard.memorySampleIntervalSeconds, "external aggregate memory sample interval is invalid")
        try PerformanceTrialValidation.require(!memory.postWarmupSlopeBytesPerSecond.isNaN, "external aggregate memory slope is invalid")
        try PerformanceTrialValidation.require(resilience.disposition != .blocked, "external aggregate resilience is blocked")
    }
}

@MainActor
internal protocol PerformanceTrialExecuting {
    func warmup(request: PerformanceTrialRequest) throws
    func sample(request: PerformanceTrialRequest) throws -> PerformanceTrialSample
}

@MainActor
internal enum PerformanceTrialRunner {
    static let warmupCount = 5

    static func run(request: PerformanceTrialRequest) throws -> PerformanceTrialResult {
        try run(
            request: request,
            sourceIdentity: SourceIdentity(
                kind: .sourceCommitSHA,
                value: String(repeating: "0", count: 40)
            ),
            runProvenanceSHA256: String(repeating: "0", count: 64),
            pairEligibilitySHA256: String(repeating: "0", count: 64),
            executor: ProductionPerformanceTrialExecutor()
        )
    }

    static func run(
        request: PerformanceTrialRequest,
        executor: any PerformanceTrialExecuting
    ) throws -> PerformanceTrialResult {
        try run(
            request: request,
            sourceIdentity: SourceIdentity(
                kind: .sourceCommitSHA,
                value: String(repeating: "0", count: 40)
            ),
            runProvenanceSHA256: String(repeating: "0", count: 64),
            pairEligibilitySHA256: String(repeating: "0", count: 64),
            executor: executor
        )
    }

    static func run(
        request: PerformanceTrialRequest,
        sourceIdentity: SourceIdentity,
        runProvenanceSHA256: String,
        pairEligibilitySHA256: String,
        executor: any PerformanceTrialExecuting
    ) throws -> PerformanceTrialResult {
        try request.validate()
        for _ in 0..<warmupCount {
            try executor.warmup(request: request)
        }
        let startedAtUTC = PerformanceTimestamp.now()
        let sample = try executor.sample(request: request)
        let endedAtUTC = PerformanceTimestamp.now()
        try sample.validate()
        let result = PerformanceTrialResult(
            request: request,
            sourceIdentity: sourceIdentity,
            runProvenanceSHA256: runProvenanceSHA256,
            pairEligibilitySHA256: pairEligibilitySHA256,
            startedAtUTC: startedAtUTC,
            endedAtUTC: endedAtUTC,
            sample: sample
        )
        try result.validate()
        return result
    }
}

/// The production trial adapter emits one scalar slot for every canonical
/// metric. Metrics without an in-process probe remain explicitly unmeasured;
/// they are never silently dropped or synthesized.
@MainActor
internal final class ProductionPerformanceTrialExecutor: PerformanceTrialExecuting {
    func warmup(request _: PerformanceTrialRequest) throws {
        // GestureBenchmark and the offscreen renderer each perform their own
        // five local warmups immediately before their scalar sample.
    }

    func sample(request: PerformanceTrialRequest) throws -> PerformanceTrialSample {
        let configuration: PerformanceConfiguration = request.fixtureProfile == .standard12
            ? .standard12
            : .dense1000
        let model = GestureBenchmarkInstrumentationAdapter().measureSingleTrial(
            configuration: configuration
        )
        let renderer = OffscreenCanvasRendererAdapter().measureSingleTrial(
            configuration: configuration
        )
        let compositor = PerformanceHarness.measureCompositor(configuration: configuration)
        let combinedFrame = PerformanceHarness.measureCombinedFrame(configuration: configuration)
        let launch = PerformanceHarness.measureLaunch(configuration: configuration)
        let allocations = PerformanceHarness.measureAllocations(configuration: configuration)
        let redraw = PerformanceHarness.measureRedrawLayout(configuration: configuration)
        let responsiveness = PerformanceHarness.measureResponsiveness(configuration: configuration)
        let inputToVisible = PerformanceHarness.measureInputToVisible(configuration: configuration)
        let memory = PerformanceHarness.measureMemory(configuration: configuration)
        let samples = [
            Self.scalar(metricID: .model, unit: .nanoseconds, status: model.status, value: model.trialNanoseconds.first, diagnostic: "model-instrumentation-unavailable"),
            Self.scalar(metricID: .renderer, unit: .milliseconds, status: renderer.status, value: renderer.frameMilliseconds.first, diagnostic: renderer.instrumentationStatus),
            Self.scalar(metricID: .compositor, unit: .milliseconds, status: compositor.status, value: compositor.frameMilliseconds.first, diagnostic: compositor.instrumentationStatus),
            Self.scalar(metricID: .combinedFrame, unit: .milliseconds, status: combinedFrame.status, value: combinedFrame.frameMilliseconds.first, diagnostic: combinedFrame.instrumentationStatus),
            Self.scalar(metricID: .launchCold, unit: .milliseconds, status: launch.status, value: launch.coldMilliseconds.first, diagnostic: "launch-instrumentation-unavailable"),
            Self.scalar(metricID: .launchWarm, unit: .milliseconds, status: launch.status, value: launch.warmMilliseconds.first, diagnostic: "launch-instrumentation-unavailable"),
            Self.scalar(metricID: .allocations, unit: .bytes, status: allocations.status, value: allocations.bytesPerGesture.first.map(Double.init), diagnostic: "allocation-instrumentation-unavailable"),
            Self.scalar(metricID: .redrawLayout, unit: .milliseconds, status: redraw.status, value: redraw.sampleMilliseconds.first, diagnostic: "redraw-instrumentation-unavailable"),
            Self.scalar(metricID: .responsiveness, unit: .milliseconds, status: responsiveness.status, value: responsiveness.responseMilliseconds.first, diagnostic: "responsiveness-instrumentation-unavailable"),
            Self.scalar(metricID: .inputToVisible, unit: .milliseconds, status: inputToVisible.status, value: inputToVisible.sampleMilliseconds.first, diagnostic: "input-to-visible-instrumentation-unavailable"),
            Self.scalar(metricID: .memoryRSS, unit: .bytes, status: memory.status, value: memory.samples.first.map { Double($0.rssBytes) }, diagnostic: "memory-instrumentation-unavailable")
        ]
        return PerformanceTrialSample(
            samples: samples,
            modelEvidence: PerformanceModelTrialEvidence(
                publicationCount: model.publicationCount,
                modelChecksum: model.modelChecksum,
                finalStateValid: model.finalStateValid
            ),
            rendererEvidence: PerformanceRendererTrialEvidence(
                frameCount: renderer.frameCount,
                missedFrameCount: renderer.missedFrameCount,
                instrumentationStatus: renderer.instrumentationStatus,
                semanticPass: renderer.status == .measured
            )
        )
    }

    internal static func scalar(
        metricID: PerformanceMetricID,
        unit: PerformanceMetricUnit,
        status: MeasurementStatus,
        value: Double?,
        diagnostic: String
    ) -> PerformanceTrialMetricSample {
        if status == .measured {
            guard let value, value.isFinite, value > 0 else {
                return PerformanceTrialMetricSample(
                    metricID: metricID,
                    unit: unit,
                    status: .failed,
                    value: nil,
                    diagnostic: "trial-\(metricID.rawValue)-invalid-measured-scalar"
                )
            }
            return PerformanceTrialMetricSample(
                metricID: metricID,
                unit: unit,
                status: .measured,
                value: value,
                diagnostic: nil
            )
        }
        let stableDiagnostic = diagnostic.isEmpty
            ? "trial-\(metricID.rawValue)-\(status.rawValue)"
            : diagnostic
        return PerformanceTrialMetricSample(
            metricID: metricID,
            unit: unit,
            status: status,
            value: nil,
            diagnostic: stableDiagnostic
        )
    }
}

public struct PerformancePartialPair: Codable, Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let fixtureProfile: PerformanceFixtureProfile
    public let pairIndex: Int
    public let order: PairOrder
    public let baseline: PerformanceTrialResult?
    public let candidate: PerformanceTrialResult?

    internal var sampleIndex: Int {
        baseline?.request.sampleIndex ?? candidate?.request.sampleIndex ?? pairIndex
    }

    public init(
        schemaVersion: Int = PerformancePartialPair.currentSchemaVersion,
        fixtureProfile: PerformanceFixtureProfile,
        pairIndex: Int,
        order: PairOrder,
        baseline: PerformanceTrialResult? = nil,
        candidate: PerformanceTrialResult? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.fixtureProfile = fixtureProfile
        self.pairIndex = pairIndex
        self.order = order
        self.baseline = baseline
        self.candidate = candidate
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case fixtureProfile
        case pairIndex
        case order
        case baseline
        case candidate
    }

    public init(from decoder: Decoder) throws {
        try PerformanceStrictJSON.requireExactKeys(
            decoder,
            Set(CodingKeys.allCases.map(\.stringValue)),
            "partial pair fields are not exact"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        fixtureProfile = try container.decode(PerformanceFixtureProfile.self, forKey: .fixtureProfile)
        pairIndex = try container.decode(Int.self, forKey: .pairIndex)
        order = try container.decode(PairOrder.self, forKey: .order)
        baseline = try container.decodeIfPresent(PerformanceTrialResult.self, forKey: .baseline)
        candidate = try container.decodeIfPresent(PerformanceTrialResult.self, forKey: .candidate)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(fixtureProfile, forKey: .fixtureProfile)
        try container.encode(pairIndex, forKey: .pairIndex)
        try container.encode(order, forKey: .order)
        if let baseline {
            try container.encode(baseline, forKey: .baseline)
        } else {
            try container.encodeNil(forKey: .baseline)
        }
        if let candidate {
            try container.encode(candidate, forKey: .candidate)
        } else {
            try container.encodeNil(forKey: .candidate)
        }
    }

    func validate() throws {
        try PerformanceTrialValidation.require(
            schemaVersion == Self.currentSchemaVersion,
            "unsupported partial pair schemaVersion"
        )
        try PerformanceTrialValidation.require(
            pairIndex >= 0 && pairIndex < 30,
            "partial pair index is outside the canonical range"
        )
        let expectedOrder: PairOrder = pairIndex < 15 ? .baselineFirst : .candidateFirst
        try PerformanceTrialValidation.require(
            order == expectedOrder,
            "partial pair order does not match its global index"
        )
        try PerformanceTrialValidation.require(
            baseline != nil || candidate != nil,
            "partial pair must contain at least one variant result"
        )
        if let baseline {
            try baseline.validate()
            try PerformanceTrialValidation.require(baseline.request.variant == .baseline, "baseline partial has the wrong variant")
            try PerformanceTrialValidation.require(baseline.request.fixtureProfile == fixtureProfile, "baseline partial fixture profile mismatch")
            try PerformanceTrialValidation.require(baseline.request.pairIndex == pairIndex && baseline.request.sampleIndex == pairIndex && baseline.request.order == order, "baseline partial pair identity mismatch")
        }
        if let candidate {
            try candidate.validate()
            try PerformanceTrialValidation.require(candidate.request.variant == .candidate, "candidate partial has the wrong variant")
            try PerformanceTrialValidation.require(candidate.request.fixtureProfile == fixtureProfile, "candidate partial fixture profile mismatch")
            try PerformanceTrialValidation.require(candidate.request.pairIndex == pairIndex && candidate.request.sampleIndex == pairIndex && candidate.request.order == order, "candidate partial pair identity mismatch")
        }
        if let baseline, let candidate {
            try PerformanceTrialValidation.require(baseline.request.fixtureProfile == candidate.request.fixtureProfile, "partial pair fixture profile mismatch")
        }
    }
}

internal enum PerformanceCanonicalJSON {
    static func data<T: Encodable>(for value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func decoded<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        let value = try decoder.decode(type, from: data)
        let canonical = try dataForValidated(value)
        try PerformanceTrialValidation.require(data == canonical, "JSON bytes are not canonical")
        return value
    }

    private static func dataForValidated<T: Encodable>(_ value: T) throws -> Data {
        try data(for: value)
    }
}

/// A canonical, process-safe store for one pair file. Both variants may write
/// the same derived path; an identical retry is a no-op, while a conflicting
/// result for an already-recorded variant is rejected.
internal struct PerformancePartialDirectoryIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
}

internal struct PerformancePartialPairStore {
    internal final class Reservation {
        let existing: PerformancePartialPair?
        private let store: PerformancePartialPairStore
        private let url: URL
        private let lockURL: URL
        private var descriptor: Int32?
        private let directoryIdentity: PerformancePartialDirectoryIdentity

        init(
            store: PerformancePartialPairStore,
            url: URL,
            lockURL: URL,
            descriptor: Int32,
            directoryIdentity: PerformancePartialDirectoryIdentity,
            existing: PerformancePartialPair?
        ) {
            self.store = store
            self.url = url
            self.lockURL = lockURL
            self.descriptor = descriptor
            self.directoryIdentity = directoryIdentity
            self.existing = existing
        }

        func commit(_ incoming: PerformancePartialPair) throws -> URL {
            guard descriptor != nil else {
                throw PerformanceValidationError.invalid("partial pair reservation is no longer active")
            }
            try store.validateDirectoryIdentity(directoryIdentity)
            return try store.storeReserved(incoming, existing: existing, url: url, expectedDirectoryIdentity: directoryIdentity)
        }

        func release() {
            guard let descriptor else { return }
            close(descriptor)
            try? FileManager.default.removeItem(at: lockURL)
            self.descriptor = nil
        }

        deinit {
            release()
        }
    }

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    func captureDirectoryIdentity(createIfMissing: Bool = false) throws -> PerformancePartialDirectoryIdentity {
        if !nodeExists(at: directory.path) {
            try PerformanceTrialValidation.require(createIfMissing, "partial pair directory is missing")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        var info = stat()
        try PerformanceTrialValidation.require(lstat(directory.path, &info) == 0, "partial pair directory cannot be inspected")
        try PerformanceTrialValidation.require((info.st_mode & S_IFMT) == S_IFDIR, "partial pair directory must be a physical directory")
        return PerformancePartialDirectoryIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }

    func validateDirectoryIdentity(_ expected: PerformancePartialDirectoryIdentity) throws {
        let actual = try captureDirectoryIdentity()
        try PerformanceTrialValidation.require(actual == expected, "partial pair directory changed during measurement")
    }

    static func url(
        directory: URL,
        pairOrder: PairOrder,
        pairIndex: Int
    ) -> URL {
        directory.appendingPathComponent("\(pairIndex).json")
    }

    static func url(directory: URL, pairIndex: Int) -> URL {
        directory.appendingPathComponent("\(pairIndex).json")
    }

    static func derivedURL(
        directory: URL,
        pairOrder: PairOrder,
        pairIndex: Int
    ) -> URL {
        url(directory: directory, pairOrder: pairOrder, pairIndex: pairIndex)
    }

    func store(_ incoming: PerformancePartialPair) throws -> URL {
        try incoming.validate()
        let directoryIdentity = try captureDirectoryIdentity(createIfMissing: true)
        let url = Self.url(directory: directory, pairOrder: incoming.order, pairIndex: incoming.pairIndex)
        let lockURL = url.appendingPathExtension("lock")
        let lockDescriptor = try acquireLock(at: lockURL)
        defer {
            close(lockDescriptor)
            try? FileManager.default.removeItem(at: lockURL)
        }
        try validateDirectoryIdentity(directoryIdentity)

        let existing: PerformancePartialPair?
        if FileManager.default.fileExists(atPath: url.path) {
            existing = try load(url: url)
        } else {
            existing = nil
        }
        if existing == nil {
            let firstVariant: PerformanceVariant = incoming.order == .baselineFirst ? .baseline : .candidate
            let incomingVariants = Set([
                incoming.baseline.map { _ in PerformanceVariant.baseline },
                incoming.candidate.map { _ in PerformanceVariant.candidate }
            ].compactMap { $0 })
            if incomingVariants.count == 1 {
                try PerformanceTrialValidation.require(
                    incomingVariants.contains(firstVariant),
                    "partial pair must record its first variant before the second"
                )
            }
        }
        let merged = try merge(existing: existing, incoming: incoming)
        let bytes = try canonicalData(for: merged)
        if existing != nil {
            let existingBytes = try Data(contentsOf: url)
            if existingBytes == bytes {
                return url
            }
        }
        try validateDirectoryIdentity(directoryIdentity)
        try bytes.write(to: url, options: .atomic)
        try validateDirectoryIdentity(directoryIdentity)
        return url
    }

    func write(_ incoming: PerformancePartialPair) throws -> URL {
        try store(incoming)
    }

    func auditBeforeMeasurement(
        configuration: PerformanceConfiguration,
        profile: PerformanceFixtureProfile,
        selectedVariant: PerformanceVariant,
        selectedSourceIdentity: SourceIdentity,
        selectedRunProvenanceSHA256: String,
        pairEligibilitySHA256: String,
        eligibility: PerformancePairEligibility
    ) throws {
        try PerformanceTrialValidation.require(configuration.isCanonical && configuration.fixtureProfile == profile, "premeasure configuration/profile mismatch")
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try validateDirectoryEntries()
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for file in files {
            let artifact = try load(url: file)
            try PerformanceTrialValidation.require(artifact.fixtureProfile == profile, "premeasure partial fixture profile mismatch")
            try PerformanceTrialValidation.require(artifact.pairIndex >= 0 && artifact.pairIndex < configuration.totalPairs, "premeasure partial pair index is invalid")
            let expectedOrder: PairOrder = artifact.pairIndex < configuration.pairsPerOrder ? .baselineFirst : .candidateFirst
            try PerformanceTrialValidation.require(artifact.order == expectedOrder, "premeasure partial pair order is invalid")
            for result in [artifact.baseline, artifact.candidate].compactMap({ $0 }) {
                try PerformanceTrialValidation.require(result.request.fixtureProfile == profile, "premeasure trial fixture profile mismatch")
                try PerformanceTrialValidation.require(result.pairEligibilitySHA256 == pairEligibilitySHA256, "premeasure trial eligibility mismatch")
                let expectedCommit = result.request.variant == .baseline
                    ? eligibility.baselineCommitSHA
                    : eligibility.candidateCommitSHA
                if result.sourceIdentity.kind == .sourceCommitSHA {
                    try PerformanceTrialValidation.require(result.sourceIdentity.value == expectedCommit, "premeasure trial source commit mismatch")
                } else {
                    try PerformanceTrialValidation.require(result.sourceIdentity.value.isLowercaseHex(count: 64), "premeasure trial content identity is invalid")
                }
                if result.request.variant == selectedVariant {
                    try PerformanceTrialValidation.require(result.sourceIdentity == selectedSourceIdentity, "premeasure selected source identity mismatch")
                    try PerformanceTrialValidation.require(result.runProvenanceSHA256 == selectedRunProvenanceSHA256, "premeasure selected provenance mismatch")
                }
            }
        }
    }

    func reserve(
        request: PerformanceTrialRequest,
        sourceIdentity: SourceIdentity,
        runProvenanceSHA256: String,
        pairEligibilitySHA256: String,
        expectedDirectoryIdentity: PerformancePartialDirectoryIdentity? = nil
    ) throws -> Reservation {
        try request.validate()
        let directoryIdentity = try captureDirectoryIdentity(createIfMissing: true)
        if let expectedDirectoryIdentity {
            try validateDirectoryIdentity(expectedDirectoryIdentity)
            try PerformanceTrialValidation.require(directoryIdentity == expectedDirectoryIdentity, "partial pair directory changed before reservation")
        }
        try validateDirectoryEntries()
        let url = Self.url(directory: directory, pairOrder: request.order, pairIndex: request.pairIndex)
        let lockURL = url.appendingPathExtension("lock")
        let descriptor = try acquireLock(at: lockURL)
        do {
            if let expectedDirectoryIdentity {
                try validateDirectoryIdentity(expectedDirectoryIdentity)
            } else {
                try validateDirectoryIdentity(directoryIdentity)
            }
            try validateDirectoryEntries(allowing: lockURL)
            let existing = FileManager.default.fileExists(atPath: url.path)
                ? try load(url: url)
                : nil
            try validateReservation(
                existing: existing,
                request: request,
                sourceIdentity: sourceIdentity,
                runProvenanceSHA256: runProvenanceSHA256,
                pairEligibilitySHA256: pairEligibilitySHA256
            )
            return Reservation(store: self, url: url, lockURL: lockURL, descriptor: descriptor, directoryIdentity: expectedDirectoryIdentity ?? directoryIdentity, existing: existing)
        } catch {
            close(descriptor)
            try? FileManager.default.removeItem(at: lockURL)
            throw error
        }
    }

    func load(pairOrder: PairOrder, pairIndex: Int) throws -> PerformancePartialPair {
        let url = Self.url(directory: directory, pairOrder: pairOrder, pairIndex: pairIndex)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw PerformanceValidationError.invalid("missing partial pair artifact \(url.lastPathComponent)")
        }
        return try load(url: url)
    }

    func loadIfPresent(pairOrder: PairOrder, pairIndex: Int) throws -> PerformancePartialPair? {
        let url = Self.url(directory: directory, pairOrder: pairOrder, pairIndex: pairIndex)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try load(url: url)
    }

    func loadAll(configuration: PerformanceConfiguration) throws -> [PerformancePartialPair] {
        try validateDirectoryEntries()
        let expected = Set((0..<configuration.totalPairs).map { index in
            Self.url(
                directory: directory,
                pairOrder: index < configuration.pairsPerOrder ? .baselineFirst : .candidateFirst,
                pairIndex: index
            ).lastPathComponent
        })
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        try PerformanceTrialValidation.require(
            !files.contains { $0.pathExtension == "lock" },
            "partial pair directory has an active lock"
        )
        let actual = Set(files.map(\.lastPathComponent))
        try PerformanceTrialValidation.require(actual == expected, "partial pair directory contains missing, extra, or duplicate artifacts")
        return try (0..<configuration.totalPairs).map { index in
            let order: PairOrder = index < configuration.pairsPerOrder ? .baselineFirst : .candidateFirst
            return try load(pairOrder: order, pairIndex: index)
        }
    }

    private func load(url: URL) throws -> PerformancePartialPair {
        let data = try Data(contentsOf: url)
        try Self.validateShape(data)
        let artifact = try PerformanceCanonicalJSON.decoded(PerformancePartialPair.self, from: data)
        try artifact.validate()
        return artifact
    }

    private func merge(
        existing: PerformancePartialPair?,
        incoming: PerformancePartialPair
    ) throws -> PerformancePartialPair {
        guard let existing else { return incoming }
        try PerformanceTrialValidation.require(
            existing.schemaVersion == incoming.schemaVersion
                && existing.fixtureProfile == incoming.fixtureProfile
                && existing.pairIndex == incoming.pairIndex
                && existing.order == incoming.order,
            "partial pair identity conflict"
        )
        let baseline = try mergeVariant(existing: existing.baseline, incoming: incoming.baseline, variant: .baseline)
        let candidate = try mergeVariant(existing: existing.candidate, incoming: incoming.candidate, variant: .candidate)
        return PerformancePartialPair(
            schemaVersion: existing.schemaVersion,
            fixtureProfile: existing.fixtureProfile,
            pairIndex: existing.pairIndex,
            order: existing.order,
            baseline: baseline,
            candidate: candidate
        )
    }

    private func mergeVariant(
        existing: PerformanceTrialResult?,
        incoming: PerformanceTrialResult?,
        variant: PerformanceVariant
    ) throws -> PerformanceTrialResult? {
        guard let existing, let incoming else { return existing ?? incoming }
        try PerformanceTrialValidation.require(
            existing.request.variant == variant && incoming.request.variant == variant,
            "partial pair variant conflict"
        )
        try PerformanceTrialValidation.require(existing == incoming, "conflicting retry for \(variant.rawValue) partial")
        return existing
    }

    private func storeReserved(
        _ incoming: PerformancePartialPair,
        existing: PerformancePartialPair?,
        url: URL,
        expectedDirectoryIdentity: PerformancePartialDirectoryIdentity
    ) throws -> URL {
        try incoming.validate()
        let merged = try merge(existing: existing, incoming: incoming)
        let bytes = try canonicalData(for: merged)
        if existing != nil, try Data(contentsOf: url) == bytes {
            return url
        }
        try validateDirectoryIdentity(expectedDirectoryIdentity)
        try bytes.write(to: url, options: .atomic)
        try validateDirectoryIdentity(expectedDirectoryIdentity)
        return url
    }

    private func validateReservation(
        existing: PerformancePartialPair?,
        request: PerformanceTrialRequest,
        sourceIdentity: SourceIdentity,
        runProvenanceSHA256: String,
        pairEligibilitySHA256: String
    ) throws {
        guard let existing else {
            let firstVariant: PerformanceVariant = request.order == .baselineFirst ? .baseline : .candidate
            try PerformanceTrialValidation.require(request.variant == firstVariant, "partial pair must record its first variant before the second")
            return
        }
        let current = request.variant == .baseline ? existing.baseline : existing.candidate
        if let current {
            try PerformanceTrialValidation.require(current.request == request, "retry request conflicts with existing partial result")
            try PerformanceTrialValidation.require(current.sourceIdentity == sourceIdentity, "retry source identity conflicts with existing partial result")
            try PerformanceTrialValidation.require(current.runProvenanceSHA256 == runProvenanceSHA256, "retry provenance conflicts with existing partial result")
            try PerformanceTrialValidation.require(current.pairEligibilitySHA256 == pairEligibilitySHA256, "retry eligibility conflicts with existing partial result")
            return
        }
        let firstVariant: PerformanceVariant = request.order == .baselineFirst ? .baseline : .candidate
        let other = request.variant == .baseline ? existing.candidate : existing.baseline
        try PerformanceTrialValidation.require(other?.request.variant == firstVariant, "partial pair first variant is missing or out of order")
    }

    private func validateDirectoryEntries(allowing allowedLockURL: URL? = nil) throws {
        _ = try captureDirectoryIdentity()
        let expected = Set((0..<30).map { "\($0).json" })
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        for file in files {
            if let allowedLockURL,
               file.standardizedFileURL.path == allowedLockURL.standardizedFileURL.path {
                continue
            }
            if file.pathExtension == "lock" {
                throw PerformanceValidationError.invalid("partial pair artifact is locked")
            }
            try PerformanceTrialValidation.require(expected.contains(file.lastPathComponent), "partial pair directory contains an extra entry")
            try validateRegularFile(file)
        }
    }

    private func validateRegularFile(_ url: URL) throws {
        var fileInfo = stat()
        try PerformanceTrialValidation.require(lstat(url.path, &fileInfo) == 0, "partial pair artifact cannot be inspected")
        try PerformanceTrialValidation.require((fileInfo.st_mode & S_IFMT) == S_IFREG, "partial pair artifact must be a regular file")
    }

    private func canonicalData(for artifact: PerformancePartialPair) throws -> Data {
        try PerformanceCanonicalJSON.data(for: artifact)
    }

    private func acquireLock(at url: URL) throws -> Int32 {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw PerformanceValidationError.invalid("partial pair artifact is locked: \(url.deletingPathExtension().lastPathComponent)")
        }
        return descriptor
    }

    private func nodeExists(at path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    private static func validateShape(_ data: Data) throws {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let root = object as? [String: Any]
        else {
            throw PerformanceValidationError.invalid("partial pair JSON is invalid")
        }
        let rootKeys: Set<String> = ["schemaVersion", "fixtureProfile", "pairIndex", "order", "baseline", "candidate"]
        try PerformanceTrialValidation.require(Set(root.keys) == rootKeys, "partial pair JSON fields are not exact")
        for key in ["baseline", "candidate"] where root[key] != nil && !(root[key] is NSNull) {
            guard let result = root[key] as? [String: Any] else {
                throw PerformanceValidationError.invalid("partial pair trial result is invalid")
            }
            let resultKeys: Set<String> = ["schemaVersion", "request", "sourceIdentity", "runProvenanceSHA256", "pairEligibilitySHA256", "startedAtUTC", "endedAtUTC", "warmupCountExecuted", "samples", "modelEvidence", "rendererEvidence"]
            try PerformanceTrialValidation.require(Set(result.keys) == resultKeys, "partial pair trial result fields are invalid")
            guard let request = result["request"] as? [String: Any] else {
                throw PerformanceValidationError.invalid("partial pair trial request is invalid")
            }
            let requestKeys: Set<String> = ["schemaVersion", "variant", "fixtureProfile", "pairIndex", "order", "sampleIndex"]
            try PerformanceTrialValidation.require(Set(request.keys) == requestKeys, "partial pair trial request fields are invalid")
            guard let samples = result["samples"] as? [[String: Any]] else {
                throw PerformanceValidationError.invalid("partial pair trial samples are invalid")
            }
            let sampleKeys: Set<String> = ["metricID", "unit", "status", "value", "diagnostic"]
            for sample in samples {
                try PerformanceTrialValidation.require(Set(sample.keys) == sampleKeys, "partial pair metric sample fields are invalid")
            }
            guard let modelEvidence = result["modelEvidence"] as? [String: Any],
                  let rendererEvidence = result["rendererEvidence"] as? [String: Any]
            else {
                throw PerformanceValidationError.invalid("partial pair trial evidence is invalid")
            }
            try PerformanceTrialValidation.require(
                Set(modelEvidence.keys) == ["publicationCount", "modelChecksum", "finalStateValid"],
                "partial pair model evidence fields are invalid"
            )
            try PerformanceTrialValidation.require(
                Set(rendererEvidence.keys) == ["frameCount", "missedFrameCount", "instrumentationStatus", "semanticPass"],
                "partial pair renderer evidence fields are invalid"
            )
        }
    }
}

internal struct PerformanceFinalizedTrialReports: Sendable {
    let baselineReport: PerformanceMeasurementReport
    let candidateReport: PerformanceMeasurementReport
    let artifact: PerformancePairExecutionArtifact
    let baselineReportURL: URL
    let candidateReportURL: URL
    let artifactURL: URL
    let baselineReportSHA256: String
    let candidateReportSHA256: String
    let artifactSHA256: String
}

internal enum PerformancePairExecutionFinalizer {
    private struct ScalarAggregation {
        let status: MeasurementStatus
        let values: [Double]
        let diagnostic: String
    }

    static func finalize(
        partialDirectory: URL,
        baselineReportURL: URL,
        candidateReportURL: URL,
        outputDirectory: URL,
        configuration: PerformanceConfiguration,
        baselineRun: PerformanceRunProvenance,
        candidateRun: PerformanceRunProvenance,
        baselineBuild: BuildProvenance,
        candidateBuild: BuildProvenance,
        baselineIdentity: MeasurementIdentity,
        candidateIdentity: MeasurementIdentity,
        baselineRunProvenanceSHA256: String,
        candidateRunProvenanceSHA256: String,
        pairEligibilitySHA256: String,
        baselineExternalAggregate: PerformanceExternalAggregateSidecar? = nil,
        candidateExternalAggregate: PerformanceExternalAggregateSidecar? = nil
    ) throws -> PerformanceFinalizedTrialReports {
        try PerformanceTrialValidation.require(configuration.isCanonical, "finalizer requires a canonical configuration")
        try PerformanceTrialValidation.require(baselineRun.configuration == configuration && candidateRun.configuration == configuration, "finalizer run configuration mismatch")
        try PerformanceTrialValidation.require(baselineRun.build == baselineBuild && candidateRun.build == candidateBuild, "finalizer build provenance mismatch")
        let partials = try PerformancePartialPairStore(directory: partialDirectory).loadAll(configuration: configuration)
        try PerformanceTrialValidation.require(partials.count == configuration.totalPairs, "finalizer requires exactly totalPairs partial artifacts")
        try PerformanceTrialValidation.require(partials.allSatisfy { $0.baseline != nil && $0.candidate != nil }, "finalizer requires complete baseline and candidate partials")

        let baselineResults = partials.compactMap(\.baseline)
        let candidateResults = partials.compactMap(\.candidate)
        for result in baselineResults {
            try validate(result: result, expectedVariant: .baseline, run: baselineRun, build: baselineBuild, configuration: configuration, runProvenanceSHA256: baselineRunProvenanceSHA256, pairEligibilitySHA256: pairEligibilitySHA256)
        }
        for result in candidateResults {
            try validate(result: result, expectedVariant: .candidate, run: candidateRun, build: candidateBuild, configuration: configuration, runProvenanceSHA256: candidateRunProvenanceSHA256, pairEligibilitySHA256: pairEligibilitySHA256)
        }
        try validateModelEvidenceAgreement(baselineResults, variant: .baseline)
        try validateModelEvidenceAgreement(candidateResults, variant: .candidate)
        try validateExternalAggregate(
            baselineExternalAggregate,
            variant: .baseline,
            profile: configuration.fixtureProfile,
            sourceIdentity: baselineBuild.sourceIdentity,
            runProvenanceSHA256: baselineRunProvenanceSHA256,
            pairEligibilitySHA256: pairEligibilitySHA256,
            results: baselineResults
        )
        try validateExternalAggregate(
            candidateExternalAggregate,
            variant: .candidate,
            profile: configuration.fixtureProfile,
            sourceIdentity: candidateBuild.sourceIdentity,
            runProvenanceSHA256: candidateRunProvenanceSHA256,
            pairEligibilitySHA256: pairEligibilitySHA256,
            results: candidateResults
        )
        let records = try makeRecords(partials: partials, configuration: configuration)
        let baselineReport = try aggregateReport(
            results: baselineResults,
            configuration: configuration,
            build: baselineBuild,
            run: baselineRun,
            identity: baselineIdentity,
            externalAggregate: baselineExternalAggregate
        )
        let candidateReport = try aggregateReport(
            results: candidateResults,
            configuration: configuration,
            build: candidateBuild,
            run: candidateRun,
            identity: candidateIdentity,
            externalAggregate: candidateExternalAggregate
        )
        try baselineReport.validateStructure()
        try candidateReport.validateStructure()

        let baselineBytes = try PerformanceCanonicalJSON.data(for: baselineReport)
        let candidateBytes = try PerformanceCanonicalJSON.data(for: candidateReport)
        let baselineHash = sha256(baselineBytes)
        let candidateHash = sha256(candidateBytes)
        let artifact = PerformancePairExecutionArtifact(
            baselineID: baselineRun.sourceRef,
            candidateID: candidateRun.sourceRef,
            baselineMeasurementReportSHA256: baselineHash,
            candidateMeasurementReportSHA256: candidateHash,
            records: records
        )
        let artifactBytes = try PerformancePairExecutionArtifact.canonicalData(for: artifact)
        let artifactHash = sha256(artifactBytes)
        try artifact.validate(
            expectedBaselineID: baselineRun.sourceRef,
            expectedCandidateID: candidateRun.sourceRef,
            expectedBaselineReportHash: baselineHash,
            expectedCandidateReportHash: candidateHash,
            expectedArtifactHash: artifactHash,
            pairCount: configuration.totalPairs
        )

        let artifactURL = outputDirectory
            .appendingPathComponent("pair-execution", isDirectory: true)
            .appendingPathComponent("pair-execution.json")
        try validateNoConflictingOutput(url: baselineReportURL, bytes: baselineBytes)
        try validateNoConflictingOutput(url: candidateReportURL, bytes: candidateBytes)
        try validateNoConflictingOutput(url: artifactURL, bytes: artifactBytes)
        try FileManager.default.createDirectory(at: baselineReportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: candidateReportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDirectory.appendingPathComponent("pair-execution", isDirectory: true), withIntermediateDirectories: true)
        try writeIfNeeded(url: baselineReportURL, bytes: baselineBytes)
        try writeIfNeeded(url: candidateReportURL, bytes: candidateBytes)
        // The pair artifact is intentionally last: a reader cannot observe a
        // complete pair artifact that points at missing report bytes.
        try writeIfNeeded(url: artifactURL, bytes: artifactBytes)
        return PerformanceFinalizedTrialReports(
            baselineReport: baselineReport,
            candidateReport: candidateReport,
            artifact: artifact,
            baselineReportURL: baselineReportURL,
            candidateReportURL: candidateReportURL,
            artifactURL: artifactURL,
            baselineReportSHA256: baselineHash,
            candidateReportSHA256: candidateHash,
            artifactSHA256: artifactHash
        )
    }

    private static func validate(
        result: PerformanceTrialResult,
        expectedVariant: PerformanceVariant,
        run: PerformanceRunProvenance,
        build: BuildProvenance,
        configuration: PerformanceConfiguration,
        runProvenanceSHA256: String,
        pairEligibilitySHA256: String
    ) throws {
        try PerformanceTrialValidation.require(result.request.variant == expectedVariant, "finalizer trial variant mismatch")
        try PerformanceTrialValidation.require(result.sourceIdentity == build.sourceIdentity, "finalizer trial/build identity mismatch")
        try PerformanceTrialValidation.require(result.request.fixtureProfile == configuration.fixtureProfile, "finalizer trial/profile mismatch")
        try PerformanceTrialValidation.require(result.runProvenanceSHA256 == runProvenanceSHA256, "finalizer trial/provenance hash mismatch")
        try PerformanceTrialValidation.require(result.pairEligibilitySHA256 == pairEligibilitySHA256, "finalizer trial/eligibility hash mismatch")
        try PerformanceTrialValidation.require(run.variant == expectedVariant.rawValue, "finalizer run variant mismatch")
        try PerformanceTrialValidation.require(run.build == build, "finalizer run/build provenance mismatch")
        try PerformanceTrialValidation.require(result.request.fixtureProfile == configuration.fixtureProfile, "finalizer trial/profile mismatch")
    }

    private static func validateModelEvidenceAgreement(
        _ results: [PerformanceTrialResult],
        variant: PerformanceVariant
    ) throws {
        guard let first = results.first else {
            throw PerformanceValidationError.invalid("finalizer (variant.rawValue) model evidence is missing")
        }
        try PerformanceTrialValidation.require(
            results.allSatisfy { $0.modelEvidence == first.modelEvidence },
            "finalizer (variant.rawValue) model evidence changed across trials"
        )
    }

    private static func validateExternalAggregate(
        _ sidecar: PerformanceExternalAggregateSidecar?,
        variant: PerformanceVariant,
        profile: PerformanceFixtureProfile,
        sourceIdentity: SourceIdentity,
        runProvenanceSHA256: String,
        pairEligibilitySHA256: String,
        results: [PerformanceTrialResult]
    ) throws {
        guard let sidecar else { return }
        try sidecar.validate()
        try PerformanceTrialValidation.require(sidecar.binding.variant == variant, "external aggregate variant mismatch")
        try PerformanceTrialValidation.require(sidecar.binding.fixtureProfile == profile, "external aggregate profile mismatch")
        try PerformanceTrialValidation.require(sidecar.binding.sourceIdentity == sourceIdentity, "external aggregate source identity mismatch")
        try PerformanceTrialValidation.require(sidecar.binding.runProvenanceSHA256 == runProvenanceSHA256, "external aggregate provenance hash mismatch")
        try PerformanceTrialValidation.require(sidecar.binding.pairEligibilitySHA256 == pairEligibilitySHA256, "external aggregate eligibility hash mismatch")
        let orderedResults = results.sorted { $0.request.sampleIndex < $1.request.sampleIndex }
        let hashes = try orderedResults.map { try sha256(PerformanceCanonicalJSON.data(for: $0)) }
        try PerformanceTrialValidation.require(sidecar.resultSHA256s == hashes, "external aggregate result hashes do not match partial results")
    }

    private static func makeRecords(
        partials: [PerformancePartialPair],
        configuration: PerformanceConfiguration
    ) throws -> [PerformancePairExecutionRecord] {
        let records = try partials.sorted { $0.pairIndex < $1.pairIndex }.map { partial in
            guard let baseline = partial.baseline, let candidate = partial.candidate else {
                throw PerformanceValidationError.invalid("finalizer requires complete pair records")
            }
            return PerformancePairExecutionRecord(
                pairIndex: partial.pairIndex,
                order: partial.order,
                baselineSampleIndex: partial.pairIndex,
                candidateSampleIndex: partial.pairIndex,
                baselineStartedAtUTC: baseline.startedAtUTC,
                candidateStartedAtUTC: candidate.startedAtUTC,
                baselineEndedAtUTC: baseline.endedAtUTC,
                candidateEndedAtUTC: candidate.endedAtUTC
            )
        }
        try PerformanceTrialValidation.require(records.count == configuration.totalPairs, "finalizer record count is invalid")
        return records
    }

    internal static func aggregateReport(
        results: [PerformanceTrialResult],
        configuration: PerformanceConfiguration,
        build: BuildProvenance,
        run: PerformanceRunProvenance,
        identity: MeasurementIdentity,
        externalAggregate: PerformanceExternalAggregateSidecar? = nil
    ) throws -> PerformanceMeasurementReport {
        try PerformanceTrialValidation.require(results.count == configuration.totalPairs, "aggregate requires exactly totalPairs results")
        try PerformanceTrialValidation.require(
            Set(results.map(\.request.pairIndex)) == Set(0..<configuration.totalPairs),
            "aggregate sample indices must be unique and contiguous"
        )
        if let variant = PerformanceVariant(rawValue: run.variant) {
            try validateModelEvidenceAgreement(results, variant: variant)
        }
        let orderedResults = results.sorted { $0.request.sampleIndex < $1.request.sampleIndex }
        let modelAggregation = try scalarAggregation(for: .model, results: orderedResults)
        let rendererAggregation = try scalarAggregation(for: .renderer, results: orderedResults)
        let modelStatus = modelAggregation.status
        if modelStatus == .measured {
            try PerformanceTrialValidation.require(
                orderedResults.dropFirst().allSatisfy { $0.modelEvidence.modelChecksum == orderedResults[0].modelEvidence.modelChecksum },
                "model checksum changed across trials"
            )
            try PerformanceTrialValidation.require(
                orderedResults.allSatisfy { $0.modelEvidence.publicationCount == 2 && $0.modelEvidence.finalStateValid },
                "model evidence is incomplete across trials"
            )
        }
        let rendererStatus = rendererAggregation.status
        if rendererStatus == .measured {
            try PerformanceTrialValidation.require(
                orderedResults.allSatisfy { $0.rendererEvidence.semanticPass },
                "renderer semantic evidence is incomplete across trials"
            )
        }
        let modelSamples = modelAggregation.values
        let rendererSamples = rendererAggregation.values
        let modelChecksum = orderedResults.first?.modelEvidence.modelChecksum ?? "trial-model-unmeasured"
        let model = ModelMeasurement(
            status: modelStatus,
            trialNanoseconds: modelSamples,
            medianNanoseconds: modelSamples.isEmpty ? 0 : median(modelSamples),
            p95Nanoseconds: modelSamples.isEmpty ? 0 : p95(modelSamples),
            madNanoseconds: modelSamples.isEmpty ? 0 : mad(modelSamples),
            publicationCount: orderedResults.first?.modelEvidence.publicationCount ?? 0,
            modelChecksum: modelChecksum,
            finalStateValid: orderedResults.allSatisfy(\.modelEvidence.finalStateValid)
        )
        let renderer = FrameMeasurement(
            status: rendererStatus,
            sampleCount: rendererSamples.count,
            p95Milliseconds: rendererSamples.isEmpty ? 0 : p95(rendererSamples),
            frameMilliseconds: rendererSamples,
            frameCount: rendererSamples.count,
            missedFrameCount: rendererStatus == .measured
                ? rendererSamples.filter { $0 > 16.7 }.count
                : 0,
            instrumentationStatus: rendererStatus == .measured
                ? (orderedResults.first?.rendererEvidence.instrumentationStatus ?? "trial-renderer-sidecar")
                : rendererAggregation.diagnostic
        )
        let compositor = try frameMeasurement(metric: .compositor, aggregation: try scalarAggregation(for: .compositor, results: orderedResults))
        let combinedFrame = try frameMeasurement(metric: .combinedFrame, aggregation: try scalarAggregation(for: .combinedFrame, results: orderedResults))
        let launch = try launchMeasurement(
            cold: try scalarAggregation(for: .launchCold, results: orderedResults),
            warm: try scalarAggregation(for: .launchWarm, results: orderedResults)
        )
        let allocations = try allocationMeasurement(aggregation: try scalarAggregation(for: .allocations, results: orderedResults))
        let redraw = try redrawMeasurement(aggregation: try scalarAggregation(for: .redrawLayout, results: orderedResults))
        let responsiveness = try responsivenessMeasurement(aggregation: try scalarAggregation(for: .responsiveness, results: orderedResults))
        let input = try inputMeasurement(aggregation: try scalarAggregation(for: .inputToVisible, results: orderedResults))
        let zeroResources = ResourceCounts(overlays: 0, timers: 0, handlers: 0, windows: 0, observers: 0)
        let memoryAggregation = try scalarAggregation(for: .memoryRSS, results: orderedResults)
        let memory = externalAggregate?.memory ?? (memoryAggregation.status == .measured
            ? scalarMemory(values: memoryAggregation.values, configuration: configuration, resources: zeroResources)
            : emptyMemory(status: memoryAggregation.status, configuration: configuration, resources: zeroResources))
        let resilience = externalAggregate?.resilience ?? ResilienceMeasurement(status: .unmeasured, cases: [], disposition: .revise)
        let fixture = FixtureIdentity(identifier: configuration.fixtureProfile.identifier, fixtureProfile: configuration.fixtureProfile, fixtureVersion: configuration.fixtureProfile.version, markCount: configuration.fixtureMarkCount, continuationSamples: configuration.samplesPerGesture, warmupCount: configuration.warmupCount, trialCount: configuration.trialCount, seed: 1234)
        let makeReport: (Disposition) -> PerformanceMeasurementReport = { disposition in
            PerformanceMeasurementReport(
                reportKind: .measurement,
                schemaVersion: PerformanceMeasurementReport.currentSchemaVersion,
                harnessVersion: configuration.harnessVersion,
                foundationIdentity: configuration.foundationIdentity,
                buildContractVersion: configuration.buildContractVersion,
                buildProvenance: build,
                runProvenance: run,
                identity: identity,
                host: run.host,
                fixture: fixture,
                model: model,
                renderer: renderer,
                compositor: compositor,
                combinedFrame: combinedFrame,
                launch: launch,
                allocations: allocations,
                redrawLayout: redraw,
                responsiveness: responsiveness,
                inputToVisible: input,
                memory: memory,
                resilience: resilience,
                disposition: disposition
            )
        }
        let report = makeReport(.revise)
        let statuses = [
            model.status,
            renderer.status,
            compositor.status,
            combinedFrame.status,
            launch.status,
            allocations.status,
            redraw.status,
            responsiveness.status,
            input.status,
            memory.status,
            resilience.status
        ]
        guard statuses.allSatisfy({ $0 == .measured }) else { return report }
        let acceptedReport = makeReport(.acceptedNoRegression)
        return (try? acceptedReport.validateCompletion()) == nil ? report : acceptedReport
    }

    private static func scalarAggregation(
        for metric: PerformanceMetricID,
        results: [PerformanceTrialResult]
    ) throws -> ScalarAggregation {
        let samples = try results.map { result -> PerformanceTrialMetricSample in
            guard let sample = result.samples.first(where: { $0.metricID == metric }) else {
                throw PerformanceValidationError.invalid("metric \(metric.rawValue) is missing from a trial")
            }
            return sample
        }
        if samples.contains(where: { $0.status == .failed }) {
            return ScalarAggregation(
                status: .failed,
                values: [],
                diagnostic: "trial-\(metric.rawValue)-failed"
            )
        }
        if samples.contains(where: { $0.status == .unmeasured }) {
            return ScalarAggregation(
                status: .unmeasured,
                values: [],
                diagnostic: "trial-\(metric.rawValue)-unmeasured"
            )
        }
        let values = samples.compactMap(\.value)
        try PerformanceTrialValidation.require(
            values.count == results.count && values.allSatisfy { $0.isFinite && $0 > 0 },
            "measured metric \(metric.rawValue) has an invalid scalar"
        )
        return ScalarAggregation(
            status: .measured,
            values: values,
            diagnostic: "trial-\(metric.rawValue)-measured"
        )
    }

    private static func frameMeasurement(
        metric: PerformanceMetricID,
        aggregation: ScalarAggregation
    ) throws -> FrameMeasurement {
        guard aggregation.status == .measured else {
            return FrameMeasurement(status: aggregation.status, sampleCount: 0, p95Milliseconds: 0, frameCount: 0, missedFrameCount: 0, instrumentationStatus: aggregation.diagnostic)
        }
        try PerformanceTrialValidation.require(metric.canonicalUnit == .milliseconds, "frame metric unit is invalid")
        let values = aggregation.values
        return FrameMeasurement(status: .measured, sampleCount: values.count, p95Milliseconds: p95(values), frameMilliseconds: values, frameCount: values.count, missedFrameCount: values.filter { $0 > 16.7 }.count, instrumentationStatus: aggregation.diagnostic)
    }

    private static func launchMeasurement(cold: ScalarAggregation, warm: ScalarAggregation) throws -> LaunchMeasurement {
        if cold.status == .failed || warm.status == .failed {
            return LaunchMeasurement(status: .failed, coldMilliseconds: [], warmMilliseconds: [])
        }
        if cold.status == .unmeasured || warm.status == .unmeasured {
            return LaunchMeasurement(status: .unmeasured, coldMilliseconds: [], warmMilliseconds: [])
        }
        try PerformanceTrialValidation.require(cold.values.count == warm.values.count, "launch cold/warm samples are incomplete")
        return LaunchMeasurement(status: .measured, coldMilliseconds: cold.values, warmMilliseconds: warm.values)
    }

    private static func allocationMeasurement(aggregation: ScalarAggregation) throws -> AllocationMeasurement {
        guard aggregation.status == .measured else {
            return AllocationMeasurement(status: aggregation.status, bytesPerGesture: [], peakAllocationBytes: 0)
        }
        let bytes = try aggregation.values.map { value -> Int64 in
            try PerformanceTrialValidation.require(value.rounded() == value && value <= Double(Int64.max), "allocation scalar must be an integral byte count")
            return Int64(value)
        }
        return AllocationMeasurement(status: .measured, bytesPerGesture: bytes, peakAllocationBytes: bytes.max() ?? 0)
    }

    private static func redrawMeasurement(aggregation: ScalarAggregation) throws -> RedrawLayoutMeasurement {
        guard aggregation.status == .measured else {
            return RedrawLayoutMeasurement(status: aggregation.status, redrawsPerSample: [], layoutPasses: [], p95Milliseconds: 0)
        }
        return RedrawLayoutMeasurement(status: .measured, redrawsPerSample: Array(repeating: 1, count: aggregation.values.count), layoutPasses: Array(repeating: 1, count: aggregation.values.count), p95Milliseconds: p95(aggregation.values), sampleMilliseconds: aggregation.values)
    }

    private static func responsivenessMeasurement(aggregation: ScalarAggregation) throws -> ResponsivenessMeasurement {
        guard aggregation.status == .measured else {
            return ResponsivenessMeasurement(status: aggregation.status, stallCount: 0, maximumMainThreadStallMilliseconds: 0, p95ResponseMilliseconds: 0)
        }
        return ResponsivenessMeasurement(status: .measured, stallCount: 0, maximumMainThreadStallMilliseconds: aggregation.values.max() ?? 0, p95ResponseMilliseconds: p95(aggregation.values), responseMilliseconds: aggregation.values)
    }

    private static func inputMeasurement(aggregation: ScalarAggregation) throws -> InputToVisibleMeasurement {
        guard aggregation.status == .measured else {
            return InputToVisibleMeasurement(status: aggregation.status, sampleCount: 0, p95Milliseconds: 0, missedSampleCount: 0)
        }
        return InputToVisibleMeasurement(status: .measured, sampleCount: aggregation.values.count, p95Milliseconds: p95(aggregation.values), missedSampleCount: 0, sampleMilliseconds: aggregation.values)
    }

    private static func emptyMemory(
        status: MeasurementStatus,
        configuration: PerformanceConfiguration,
        resources: ResourceCounts
    ) -> MemoryMeasurement {
        MemoryMeasurement(status: status, windowSeconds: configuration.memoryWindowSeconds, sampleIntervalSeconds: configuration.memorySampleIntervalSeconds, samples: [], aggregates: [], peakRSSBytes: 0, finalWindowDeltaBytes: 0, finalWindowDeltaPercent: 0, matchedBaselineSeries: [], matchedBaselineValues: [], peakLiveResourceCounts: resources, endLiveResourceCounts: resources)
    }

    private static func scalarMemory(
        values: [Double],
        configuration: PerformanceConfiguration,
        resources: ResourceCounts
    ) -> MemoryMeasurement {
        let samples = values.enumerated().map { index, value in
            MemorySample(elapsedSeconds: Double(index * configuration.memorySampleIntervalSeconds), rssBytes: Int64(value.rounded()), phase: .running, resources: resources)
        }
        return MemoryMeasurement(status: .measured, windowSeconds: configuration.memoryWindowSeconds, sampleIntervalSeconds: configuration.memorySampleIntervalSeconds, samples: samples, aggregates: [], peakRSSBytes: samples.map(\.rssBytes).max() ?? 0, finalWindowDeltaBytes: 0, finalWindowDeltaPercent: 0, postWarmupSlopeBytesPerSecond: slope(for: samples, warmupCount: configuration.warmupCount), matchedBaselineSeries: [], matchedBaselineValues: [], peakLiveResourceCounts: resources, endLiveResourceCounts: resources)
    }

    private static func slope(for samples: [MemorySample], warmupCount: Int) -> Double {
        let postWarmup = Array(samples.dropFirst(warmupCount))
        guard postWarmup.count >= 2 else { return 0 }
        let meanElapsed = postWarmup.map(\.elapsedSeconds).reduce(0, +) / Double(postWarmup.count)
        let meanRSS = postWarmup.map { Double($0.rssBytes) }.reduce(0, +) / Double(postWarmup.count)
        let numerator = postWarmup.reduce(0.0) { total, sample in
            total + (sample.elapsedSeconds - meanElapsed) * (Double(sample.rssBytes) - meanRSS)
        }
        let denominator = postWarmup.reduce(0.0) { total, sample in
            total + pow(sample.elapsedSeconds - meanElapsed, 2)
        }
        return denominator == 0 ? 0 : numerator / denominator
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    private static func p95(_ values: [Double]) -> Double {
        values.sorted()[max(0, Int(ceil(Double(values.count) * 0.95)) - 1)]
    }

    private static func mad(_ values: [Double]) -> Double {
        let center = median(values)
        return median(values.map { abs($0 - center) })
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func validateNoConflictingOutput(url: URL, bytes: Data) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let existing = try Data(contentsOf: url)
        try PerformanceTrialValidation.require(existing == bytes, "finalizer output conflicts with existing bytes: \(url.lastPathComponent)")
    }

    private static func writeIfNeeded(url: URL, bytes: Data) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            return
        }
        try bytes.write(to: url, options: .atomic)
    }
}

internal enum PerformanceTimestamp {
    private static let lock = NSLock()
    private static var lastDate = Date.distantPast
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    static func now() -> String {
        lock.lock()
        defer { lock.unlock() }
        let current = Date()
        let next = max(current, lastDate.addingTimeInterval(0.001))
        lastDate = next
        return formatter.string(from: next)
    }

    static func date(from value: String) -> Date? {
        formatter.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
    }

    static func validate(_ value: String) throws {
        try PerformanceTrialValidation.require(value.hasSuffix("Z"), "timestamp must be UTC")
        try PerformanceTrialValidation.require(value.contains("."), "trial timestamp must retain fractional seconds")
        try PerformanceTrialValidation.require(date(from: value) != nil, "timestamp must be ISO-8601")
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

private enum PerformanceTrialValidation {
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw PerformanceValidationError.invalid(message)
        }
    }
}
