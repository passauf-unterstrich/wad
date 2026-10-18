// DictationControllerTests.swift
// Prüft die Absicherungen gegen eine weiterlaufende Aufnahme (SPEC 2.2) ohne echtes Mikrofon:
// Eine Attrappe ersetzt das Mikrofon, eine verstellbare Uhr ersetzt das Warten.

import XCTest

final class DictationControllerTests: XCTestCase {
    private var microphone: FakeMicrophone!
    private var keyIsDown = true
    private var clock = Date(timeIntervalSince1970: 0)
    private var controller: DictationController!

    override func setUp() {
        microphone = FakeMicrophone()
        keyIsDown = true
        clock = Date(timeIntervalSince1970: 0)
        controller = DictationController(
            capture: microphone,
            isKeyPhysicallyDown: { [unowned self] in keyIsDown },
            now: { [unowned self] in clock }
        )
    }

    func testPressAndReleaseStartsAndStopsMicrophone() {
        controller.keyPressed()
        XCTAssertEqual(controller.state, .recording)
        XCTAssertTrue(microphone.isRunning)

        controller.keyReleased()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(microphone.isRunning)
    }

    func testLostReleaseEventIsCaughtBySafetyCheck() {
        controller.keyPressed()
        keyIsDown = false            // Taste ist oben, das Loslassen-Ereignis kam aber nie an.
        controller.checkSafeguards()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(microphone.isRunning)
    }

    func testTimeLimitEndsRecording() {
        controller.keyPressed()
        clock += DictationController.maxDuration - 1
        controller.checkSafeguards()
        XCTAssertEqual(controller.state, .recording, "Kurz vor dem Limit läuft die Aufnahme noch")

        clock += 1
        controller.checkSafeguards()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(microphone.isRunning)
    }

    func testCancelStopsMicrophone() {
        controller.keyPressed()
        controller.cancel(reason: "Test")
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(microphone.isRunning)
    }

    func testSecondPressNeverStartsSecondMicrophone() {
        controller.keyPressed()
        controller.keyPressed()
        XCTAssertEqual(microphone.startCount, 1)
    }

    func testFailedMicrophoneStartStaysIdle() {
        microphone.failsToStart = true
        controller.keyPressed()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(microphone.isRunning)
    }

    func testEveryStateChangeIsReported() {
        var states: [DictationController.State] = []
        controller.onStateChange = { states.append($0) }
        controller.keyPressed()
        controller.keyReleased()
        XCTAssertEqual(states, [.recording, .processing, .idle])
    }

    func testAudioBufferNeverExceedsCapacity() {
        let buffer = AudioBuffer(maxDuration: 1)
        let samples = [Float](repeating: 0.5, count: Int(AudioBuffer.sampleRate) + 500)
        samples.withUnsafeBufferPointer { buffer.append($0) }
        XCTAssertEqual(buffer.count, buffer.capacity)

        buffer.wipe()
        XCTAssertEqual(buffer.count, 0)
    }
}

private final class FakeMicrophone: AudioCapture {
    struct StartFailure: Error {}

    var failsToStart = false
    private(set) var isRunning = false
    private(set) var startCount = 0

    func start() throws {
        if failsToStart { throw StartFailure() }
        startCount += 1
        isRunning = true
    }

    func stop() -> AudioBuffer {
        isRunning = false
        return AudioBuffer(maxDuration: 1)
    }
}
