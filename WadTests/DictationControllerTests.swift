// DictationControllerTests.swift
// Prüft die Absicherungen gegen eine weiterlaufende Aufnahme (SPEC 2.2) und das Live-Chunking
// ohne echtes Mikrofon: Attrappen ersetzen Mikrofon und Modell, eine verstellbare Uhr das Warten.
// Hintergrundarbeit läuft hier sofort, damit jeder Schritt direkt prüfbar ist.

import XCTest

final class DictationControllerTests: XCTestCase {
    private var microphone: FakeMicrophone!
    private var transcriber: FakeTranscriber!
    private var keyIsDown = true
    private var clock = Date(timeIntervalSince1970: 0)
    private var controller: DictationController!
    private var inserted: [String] = []
    private var finished: [String] = []
    private var notices: [String] = []

    override func setUp() {
        microphone = FakeMicrophone()
        transcriber = FakeTranscriber()
        keyIsDown = true
        clock = Date(timeIntervalSince1970: 0)
        inserted = []
        finished = []
        notices = []
        controller = DictationController(
            capture: microphone,
            transcriber: transcriber,
            isKeyPhysicallyDown: { [unowned self] in keyIsDown },
            now: { [unowned self] in clock },
            background: { $0() },
            main: { $0() }
        )
        controller.onText = { [unowned self] in inserted.append($0) }
        controller.onDictationFinished = { [unowned self] in finished.append($0) }
        controller.onNotice = { [unowned self] in notices.append($0) }
    }

    // MARK: Absicherungen

    func testPressAndReleaseStartsAndStopsMicrophone() {
        controller.keyPressed()
        XCTAssertEqual(controller.state, .recording)
        XCTAssertTrue(microphone.isRunning)

        clock += 1
        controller.keyReleased()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(microphone.isRunning)
    }

    func testLostReleaseEventIsCaughtBySafetyCheck() {
        controller.keyPressed()
        clock += 1
        keyIsDown = false            // Taste ist oben, das Loslassen-Ereignis kam aber nie an.
        controller.checkSafeguards()
        XCTAssertEqual(controller.state, .recording, "Ein einzelner Aussetzer beendet noch nichts")
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
        XCTAssertEqual(notices.count, 1, "Der Nutzer erfährt, warum die Aufnahme endete")
    }

    func testBriefGlitchDuringPasteDoesNotEndDictation() {
        controller.keyPressed()
        keyIsDown = false
        controller.checkSafeguards()
        keyIsDown = true
        controller.checkSafeguards()
        keyIsDown = false
        controller.checkSafeguards()
        XCTAssertEqual(controller.state, .recording, "Nur zwei Aussetzer direkt hintereinander zählen")
    }

    func testCancelStopsMicrophoneAndInsertsNothing() {
        controller.keyPressed()
        microphone.deliver(seconds: 3, speech: true)
        controller.cancel(reason: "Test")
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(microphone.isRunning)
        XCTAssertEqual(inserted, [])
        XCTAssertEqual(microphone.buffer?.count, 0, "Abgebrochenes Audio ist gelöscht")
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
        XCTAssertEqual(notices.count, 1, "Statt still zu versagen, gibt es einen Hinweis")
    }

    // MARK: Umwandlung

    func testShortTapIsDiscardedWithoutTranscription() {
        controller.keyPressed()
        microphone.deliver(seconds: 0.1, speech: true)
        clock += DictationController.minDuration / 2
        controller.keyReleased()
        XCTAssertEqual(transcriber.chunkLengths, [])
        XCTAssertEqual(inserted, [])
    }

    func testSilenceNeverReachesTheModel() {
        controller.keyPressed()
        microphone.deliver(seconds: 5, speech: false)
        clock += 5
        controller.keyReleased()
        XCTAssertEqual(transcriber.chunkLengths, [], "Stille geht nicht an das Modell, also keine Halluzinationen")
    }

    func testAtEndModeInsertsOnceAfterRelease() {
        controller.mode = .atEnd
        controller.keyPressed()
        microphone.deliver(seconds: 12, speech: true)
        microphone.deliver(seconds: 1, speech: false)
        microphone.deliver(seconds: 5, speech: true)
        XCTAssertEqual(inserted, [], "Während der Aufnahme wird nichts eingefügt")

        clock += 18
        controller.keyReleased()
        XCTAssertEqual(inserted, ["Stück 1"])
        XCTAssertEqual(microphone.buffer?.count, 0, "Nach dem Diktat ist das Audio gelöscht")
    }

    // MARK: Live-Chunking

    func testLiveModeInsertsAtPauseWhileStillSpeaking() {
        controller.keyPressed()
        microphone.deliver(seconds: 11, speech: true)
        microphone.deliver(seconds: 1, speech: false)
        XCTAssertEqual(inserted, ["Stück 1"], "Erstes Stück erscheint, während die Taste noch gehalten wird")
        XCTAssertEqual(controller.state, .recording)

        microphone.deliver(seconds: 4, speech: true)
        clock += 16
        controller.keyReleased()
        XCTAssertEqual(inserted, ["Stück 1", " Stück 2"], "Zweites Stück mit Leerzeichen angehängt")
        XCTAssertEqual(finished, ["Stück 1 Stück 2"])
    }

    func testLiveChunksShareLanguageAndContext() {
        controller.keyPressed()
        microphone.deliver(seconds: 11, speech: true)
        microphone.deliver(seconds: 1, speech: false)
        microphone.deliver(seconds: 4, speech: true)
        clock += 16
        controller.keyReleased()
        XCTAssertEqual(transcriber.languages, [nil, "de"], "Sprache wird einmal erkannt und beibehalten")
        XCTAssertEqual(transcriber.prompts, [nil, "Stück 1"], "Vorheriges Stück gibt Zusammenhang")
    }

    func testLiveChunksCoverTheAudioWithoutGapOrOverlap() {
        controller.keyPressed()
        microphone.deliver(seconds: 11, speech: true)
        microphone.deliver(seconds: 1, speech: false)
        microphone.deliver(seconds: 4, speech: true)
        clock += 16
        controller.keyReleased()
        XCTAssertEqual(transcriber.chunkLengths.reduce(0, +), Int(16 * AudioBuffer.sampleRate))
    }
}
