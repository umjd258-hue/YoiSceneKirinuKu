import XCTest
@testable import YoiSceneKirinuKu

final class JobManagementTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("YoiSceneKirinuKu-JobManagementTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testFingerprintUsesWholeFileAndIgnoresModificationDateOnly() throws {
        let source = temporaryDirectory.appendingPathComponent("日本語 source.mp4")
        let data = Data((0..<32_768).map { UInt8($0 % 251) })
        try data.write(to: source, options: .withoutOverwriting)

        let first = try AnalysisJobService.fingerprint(source)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 60)],
            ofItemAtPath: source.path
        )
        let touched = try AnalysisJobService.fingerprint(source)
        XCTAssertEqual(first, touched)

        var changed = data
        changed[16_384] ^= 0xff
        try changed.write(to: source)
        let modified = try AnalysisJobService.fingerprint(source)
        XCTAssertEqual(first.byteCount, modified.byteCount)
        XCTAssertNotEqual(first.digest, modified.digest)
    }

    func testServiceCreatesStrictJobAndRejectsSecondRequest() async throws {
        let source = temporaryDirectory.appendingPathComponent("source.mp4")
        try Data("stage-nine".utf8).write(to: source, options: .withoutOverwriting)
        let workspace = temporaryDirectory.appendingPathComponent("workspace", isDirectory: true)
        let service = AnalysisJobService(configuration: configuration(workspace: workspace))
        let characterID = UUID()

        let first = await service.createJob(sourceURL: source, characterIDs: [characterID], requestID: UUID())
        guard case .success(let jobID, .startRequested) = first else {
            return XCTFail("最初のjob作成が成功しませんでした: \(first)")
        }
        let stored = try AnalysisJobService.loadJob(from: workspace)
        XCTAssertEqual(stored.jobID, jobID)
        XCTAssertEqual(stored.selectedCharacterIDs, ["char_\(characterID.uuidString.lowercased())"])

        let second = await service.createJob(sourceURL: source, characterIDs: [characterID], requestID: UUID())
        XCTAssertEqual(second, .failure(.jobAlreadyExists))
        XCTAssertEqual(try AnalysisJobService.loadJob(from: workspace), stored)
    }

    func testRecoverySeparatesFolderFromRunningAndDetectsSourceChange() async throws {
        let source = temporaryDirectory.appendingPathComponent("source.mp4")
        try Data("original".utf8).write(to: source, options: .withoutOverwriting)
        let firstWorkspace = temporaryDirectory.appendingPathComponent("recovery-workspace", isDirectory: true)
        let firstService = AnalysisJobService(configuration: configuration(workspace: firstWorkspace))
        guard case .success = await firstService.createJob(
            sourceURL: source,
            characterIDs: [UUID()],
            requestID: UUID()
        ) else { return XCTFail("job作成に失敗しました") }

        let recovered = await firstService.recoverJob(requestID: UUID())
        guard case .success(_, .recoveryRequired) = recovered else {
            return XCTFail("active状態が復旧確認中へ移りませんでした: \(recovered)")
        }

        let changedSource = temporaryDirectory.appendingPathComponent("changed-source.mp4")
        try Data("before".utf8).write(to: changedSource, options: .withoutOverwriting)
        let secondWorkspace = temporaryDirectory.appendingPathComponent("changed-workspace", isDirectory: true)
        let secondService = AnalysisJobService(configuration: configuration(workspace: secondWorkspace))
        guard case .success = await secondService.createJob(
            sourceURL: changedSource,
            characterIDs: [UUID()],
            requestID: UUID()
        ) else { return XCTFail("変更検出用job作成に失敗しました") }
        try Data("after!".utf8).write(to: changedSource)
        let changedJobID = try AnalysisJobService.loadJob(from: secondWorkspace).jobID
        let changedOutcome = await secondService.recoverJob(requestID: UUID())
        XCTAssertEqual(changedOutcome, .success(jobID: changedJobID, state: .failed))
        XCTAssertEqual(try AnalysisJobService.loadJob(from: secondWorkspace).failureCode, "source_changed")
    }

    func testInvalidCharacterSelectionIsRejectedBeforeProcessStart() async throws {
        let source = temporaryDirectory.appendingPathComponent("source.mp4")
        try Data("source".utf8).write(to: source, options: .withoutOverwriting)
        let service = AnalysisJobService(configuration: configuration(
            workspace: temporaryDirectory.appendingPathComponent("invalid-workspace")
        ))

        let outcome = await service.createJob(sourceURL: source, characterIDs: [], requestID: UUID())
        XCTAssertEqual(outcome, .failure(.jobInvalid))
    }

    func testProtocolViolationsAreRejected() {
        let requestID = UUID()
        let unknownEvent = """
        {"protocol_version":1,"type":"unknown","request_id":"\(requestID.uuidString.lowercased())","sequence":1,"payload":{}}

        """
        XCTAssertEqual(
            AnalysisJobProtocolParser.parse(
                JobProcessResult(
                    stdout: Data(unknownEvent.utf8),
                    terminationStatus: 0,
                    terminationReason: .exit
                ),
                requestID: requestID
            ),
            .failure(.protocolError)
        )
        XCTAssertEqual(
            AnalysisJobProtocolParser.parse(
                JobProcessResult(
                    stdout: Data("not-json\n".utf8),
                    terminationStatus: 0,
                    terminationReason: .exit
                ),
                requestID: requestID
            ),
            .failure(.protocolError)
        )
        XCTAssertEqual(
            AnalysisJobProtocolParser.parse(
                JobProcessResult(stdout: Data(), terminationStatus: 1, terminationReason: .exit),
                requestID: requestID
            ),
            .failure(.protocolError)
        )
    }

    func testPipelineStopsAtVADReadyAndPreservesServiceOwnership() async {
        let characterID = UUID()
        let jobID = UUID()
        let jobs = PipelineJobService(jobID: jobID)
        let audioResult = AnalysisAudioResult(
            reused: true, frameCount: 16_000, durationMilliseconds: 1_000, selectedStreamIndex: 0
        )
        let pipeline = AnalysisPipelineOrchestrator(
            preflightService: PipelinePreflightService(),
            characterService: PipelineCharacterService(characterID: characterID),
            jobService: jobs,
            audioService: PipelineAudioService(outcome: .success(audioResult))
        )

        let outcome = await pipeline.start(
            sourceURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            characterIDs: [characterID],
            requestID: UUID()
        )

        XCTAssertEqual(outcome, .ready(jobID: jobID, state: .preparing, audio: audioResult))
        XCTAssertEqual(jobs.operations, ["create", "prepare"])
    }

    func testPipelineFailsJobWhenAudioPreparationFails() async {
        let characterID = UUID()
        let jobs = PipelineJobService(jobID: UUID())
        let pipeline = AnalysisPipelineOrchestrator(
            preflightService: PipelinePreflightService(),
            characterService: PipelineCharacterService(characterID: characterID),
            jobService: jobs,
            audioService: PipelineAudioService(outcome: .failure(.ffmpegFailed))
        )

        let outcome = await pipeline.start(
            sourceURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            characterIDs: [characterID],
            requestID: UUID()
        )

        XCTAssertEqual(outcome, .failure(.audio(.ffmpegFailed)))
        XCTAssertEqual(jobs.operations, ["create", "prepare", "fail:analysis_audio_ffmpeg_failed"])
    }

    func testPipelineResumeUsesExistingJobWithoutCreatingAnother() async {
        let jobs = PipelineJobService(jobID: UUID())
        let pipeline = AnalysisPipelineOrchestrator(
            preflightService: PipelinePreflightService(),
            characterService: PipelineCharacterService(characterID: UUID()),
            jobService: jobs,
            audioService: PipelineAudioService(outcome: .success(
                AnalysisAudioResult(reused: false, frameCount: 32_000, durationMilliseconds: 2_000, selectedStreamIndex: 1)
            ))
        )

        guard case .ready = await pipeline.resumeStopped(requestID: UUID()) else {
            return XCTFail("stopped jobを再開できませんでした")
        }
        XCTAssertEqual(jobs.operations, ["resume"])
    }

    private func configuration(workspace: URL) -> AnalysisJobConfiguration {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return AnalysisJobConfiguration(
            pythonExecutableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            scriptURL: repository.appendingPathComponent("YoiSceneKirinuKu/analysis_job_runner.py"),
            workspaceRootURL: workspace
        )
    }
}

private final class PipelinePreflightService: PreflightServicing, @unchecked Sendable {
    func run(sourceURL: URL, requestID: UUID) async -> PreflightOutcome {
        .success(PreflightResult(
            fileName: sourceURL.lastPathComponent,
            durationMilliseconds: 1_000,
            containerFormat: "mov,mp4",
            videoStreamCount: 1,
            audioStreamCount: 1
        ))
    }
}

private final class PipelineCharacterService: CharacterRegistrationServicing, @unchecked Sendable {
    let characterID: UUID
    init(characterID: UUID) { self.characterID = characterID }
    func register(_ request: CharacterRegistrationRequest, requestID: UUID) async -> CharacterRegistrationOutcome {
        .failure(.invalidRequest)
    }
    func addSample(_ request: CharacterSampleAdditionRequest, requestID: UUID) async -> CharacterRegistrationOutcome {
        .failure(.invalidRequest)
    }
    func regenerateEmbeddings(for characterID: UUID, requestID: UUID) async -> CharacterRegistrationOutcome {
        .success(RegisteredCharacter(characterID: characterID, displayName: "Test", samples: []))
    }
    func deleteCharacter(_ characterID: UUID, requestID: UUID) async -> CharacterDeletionOutcome {
        .failure(.invalidRequest)
    }
    func loadCharacters(requestID: UUID) async -> CharacterLoadOutcome {
        .success([RegisteredCharacter(characterID: characterID, displayName: "Test", samples: [])])
    }
}

private final class PipelineJobService: AnalysisJobServicing, @unchecked Sendable {
    let jobID: UUID
    private let lock = NSLock()
    private var storedOperations: [String] = []
    var operations: [String] { lock.withLock { storedOperations } }
    init(jobID: UUID) { self.jobID = jobID }
    func createJob(sourceURL: URL, characterIDs: [UUID], requestID: UUID) async -> AnalysisJobOutcome {
        record("create")
        return .success(jobID: jobID, state: .startRequested)
    }
    func recoverJob(requestID: UUID) async -> AnalysisJobOutcome {
        record("recover")
        return .success(jobID: jobID, state: .recoveryRequired)
    }
    func resumeJob(requestID: UUID) async -> AnalysisJobOutcome {
        record("resume")
        return .success(jobID: jobID, state: .preparing)
    }
    func resumeRecoveryJob(requestID: UUID) async -> AnalysisJobOutcome {
        record("resumeRecovery")
        return .success(jobID: jobID, state: .preparing)
    }
    func prepareJob(jobID: UUID, requestID: UUID) async -> AnalysisJobOutcome {
        record("prepare")
        return .success(jobID: jobID, state: .preparing)
    }
    func failJob(jobID: UUID, failureCode: String, requestID: UUID) async -> AnalysisJobOutcome {
        record("fail:\(failureCode)")
        return .success(jobID: jobID, state: .failed)
    }
    private func record(_ operation: String) { lock.withLock { storedOperations.append(operation) } }
}

private final class PipelineAudioService: AnalysisAudioServicing, @unchecked Sendable {
    let outcome: AnalysisAudioOutcome
    init(outcome: AnalysisAudioOutcome) { self.outcome = outcome }
    func prepare(jobID: UUID, requestID: UUID) async -> AnalysisAudioOutcome { outcome }
}
