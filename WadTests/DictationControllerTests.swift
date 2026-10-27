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
        controller.onText = { [unowned self] text, _ in inserted.append(text) }
        controller.onDictationFinished = { [unowned self] text, _, _ in finished.append(text) }
        controller.onNotice = { [unowned self] in notices.append($0) }
    }

    /// Lässt die Taste los, so wie es das System danach auch selbst sieht.
    private func release() {
        keyIsDown = false
        controller.keyReleased()
    }

    // MARK: Absicherungen

    func testFalseReleaseWhileKeyIsStillDownIsIgnored() {
        controller.keyPressed()
        clock += 1
        controller.keyReleased()          // keyIsDown bleibt true: ein falsches Signal eines anderen Programms
        XCTAssertEqual(controller.state, .recording, "Solange die Taste unten ist, wird aufgenommen")
        XCTAssertTrue(microphone.isRunning)
    }

    func testUnexpectedStopKeepsWhatWasSaidAndTellsTheUser() {
        controller.keyPressed()
        microphone.deliver(seconds: 3, speech: true)
        clock += 3
        controller.stopUnexpectedly(reason: "weil kein Mikrofon mehr verfügbar ist")
        XCTAssertEqual(inserted, ["Stück 1"], "Das Gesagte geht nicht verloren")
        XCTAssertEqual(notices.count, 1)
        XCTAssertFalse(microphone.isRunning)
    }

    func testLockKeepsTheDictationWithoutPastingIt() {
        controller.keyPressed()
        microphone.deliver(seconds: 3, speech: true)
        clock += 3
        controller.stopUnexpectedly(reason: "weil der Bildschirm gesperrt wurde", insert: false)
        XCTAssertEqual(inserted, [], "Auf dem Sperrbildschirm wird nichts eingefügt")
        XCTAssertEqual(finished, ["Stück 1"], "Das Diktat landet trotzdem unter „Letzte Diktate“")
        XCTAssertEqual(notices, ["Aufnahme gestoppt, weil der Bildschirm gesperrt wurde. Der Text liegt unter „Letzte Diktate“."])
    }

    func testPressAndReleaseStartsAndStopsMicrophone() {
        controller.keyPressed()
        XCTAssertEqual(controller.state, .recording)
        XCTAssertTrue(microphone.isRunning)

        clock += 1
        release()
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

    // MARK: Freies Diktieren

    func testHandsFreeKeepsRecordingWithoutKey() {
        keyIsDown = false
        controller.startHandsFree()
        clock += 60
        controller.checkSafeguards()
        controller.checkSafeguards()
        XCTAssertEqual(controller.state, .recording, "Beim freien Diktieren zählt die Taste nicht")
    }

    func testKeyPressStopsHandsFree() {
        controller.startHandsFree()
        microphone.deliver(seconds: 3, speech: true)
        clock += 3
        controller.keyPressed()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(inserted, ["Stück 2"], "Stück 1 war der graue Entwurf, der nie eingefügt wird")
        release()
        XCTAssertEqual(microphone.startCount, 1, "Der Druck zum Stoppen startet keine neue Aufnahme")
    }

    // MARK: Doppeltipp

    /// Ein kurzer Tipp ohne andere Tasten: drücken, 0,1 Sekunden, loslassen.
    private func tap(isAlone: Bool = true) {
        keyIsDown = true
        controller.keyPressed(isAlone: isAlone)
        clock += 0.1
        keyIsDown = false
        controller.keyReleased(isAlone: isAlone)
    }

    func testDoubleTapStartsHandsFreeAndItsReleaseKeepsItRunning() {
        tap()
        XCTAssertEqual(controller.state, .idle, "Der erste Tipp wird still verworfen")
        XCTAssertEqual(notices, [])
        clock += 0.2
        controller.keyPressed(isAlone: true)
        XCTAssertTrue(controller.isHandsFree)
        clock += 2
        release()
        controller.checkSafeguards()
        controller.checkSafeguards()
        XCTAssertEqual(controller.state, .recording, "Loslassen und Gegenprüfung beenden freies Diktieren nicht")
        XCTAssertEqual(transcriber.chunkLengths, [], "Der erste Tipp erreicht das Modell nie")
    }

    func testSlowSecondPressIsNormalHold() {
        tap()
        clock += DictationController.doubleTapWindow + 0.05
        controller.keyPressed(isAlone: true)
        XCTAssertEqual(controller.state, .recording)
        XCTAssertFalse(controller.isHandsFree)
    }

    func testTapWithOtherKeysDoesNotCount() {
        tap(isAlone: false)
        clock += 0.1
        controller.keyPressed(isAlone: true)
        XCTAssertFalse(controller.isHandsFree, "⌥ plus Buchstabe oder ⌥⇧ ist kein Tipp")

        release()
        clock += 1
        tap()
        clock += 0.1
        controller.keyPressed(isAlone: false)
        XCTAssertFalse(controller.isHandsFree, "Eine andere Taste zwischen den Tipps zählt auch")
    }

    func testHoldThenQuickPressIsNoDoubleTap() {
        controller.keyPressed(isAlone: true)
        clock += 1
        release()
        clock += 0.1
        controller.keyPressed(isAlone: true)
        XCTAssertFalse(controller.isHandsFree, "Nur ein zu kurzer Druck ist die erste Hälfte")
    }

    func testStopTapNeedsHalfASecond() {
        tap()
        clock += 0.1
        controller.keyPressed(isAlone: true)
        release()
        clock += 0.2
        tap()
        XCTAssertEqual(controller.state, .recording, "Ein dritter Tipp direkt danach stoppt nicht")
        XCTAssertTrue(controller.isHandsFree)
        clock += DictationController.minHandsFreeBeforeStop
        controller.keyPressed(isAlone: true)
        XCTAssertFalse(controller.isHandsFree)
        XCTAssertNotEqual(controller.state, .recording)
    }

    func testNoRestartRightAfterStop() {
        controller.startHandsFree()
        clock += 2
        controller.keyPressed(isAlone: true)
        release()
        clock += 0.1
        tap()
        clock += 0.1
        controller.keyPressed(isAlone: true)
        XCTAssertFalse(controller.isHandsFree, "Eine Sekunde nach dem Stopp startet kein Doppeltipp")
        release()
        XCTAssertEqual(microphone.isRunning, false)

        clock += DictationController.doubleTapPause
        tap()
        clock += 0.1
        controller.keyPressed(isAlone: true)
        XCTAssertTrue(controller.isHandsFree)
    }

    func testDoubleTapWithFailingMicrophoneStaysIdle() {
        tap()
        microphone.failsToStart = true
        clock += 0.1
        controller.keyPressed(isAlone: true)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertFalse(controller.isHandsFree)
    }

    func testHandsFreeIsAlwaysLiveWithDraftsAndLeavesTheModeAlone() {
        var drafts: [String] = []
        controller.onDraft = { draft, _ in drafts.append(draft) }
        controller.mode = .atEnd
        controller.startHandsFree()
        microphone.deliver(seconds: 2, speech: true)
        XCTAssertFalse(drafts.isEmpty, "Freies Diktieren zeigt immer den grauen Entwurf")
        microphone.deliver(seconds: 9, speech: true)
        microphone.deliver(seconds: 1, speech: false)
        XCTAssertEqual(inserted.count, 1, "Stücke kommen schon während des Diktats")
        clock += 12
        controller.stopHandsFree()

        drafts = []
        controller.keyPressed()
        microphone.deliver(seconds: 11, speech: true)
        microphone.deliver(seconds: 1, speech: false)
        XCTAssertEqual(inserted.count, 1, "Mit gehaltener Taste gilt wieder „Nach dem Diktat“")
        XCTAssertEqual(drafts, [])
        clock += 12
        release()
        XCTAssertEqual(inserted.count, 2)
        XCTAssertEqual(controller.mode, .atEnd)
    }

    func testHandsFreeEndsAtItsLimitAndDelivers() {
        controller.handsFreeLimit = 2 * 60
        controller.startHandsFree()
        microphone.deliver(seconds: 3, speech: true)
        clock += 2 * 60
        controller.checkSafeguards()
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(inserted, ["Stück 2"], "Stück 1 war der graue Entwurf, der nie eingefügt wird")
        XCTAssertEqual(notices.count, 1)
    }

    // MARK: Umwandlung

    func testNewRecordingStartsWhileStillProcessing() {
        var pending: [() -> Void] = []
        controller = DictationController(
            capture: microphone, transcriber: transcriber,
            isKeyPhysicallyDown: { [unowned self] in keyIsDown },
            now: { [unowned self] in clock },
            background: { pending.append($0) }, main: { $0() })
        controller.onText = { [unowned self] text, _ in inserted.append(text) }

        controller.keyPressed()
        microphone.deliver(seconds: 3, speech: true)
        clock += 3
        release()
        XCTAssertEqual(controller.state, .processing)

        keyIsDown = true
        controller.keyPressed()
        XCTAssertEqual(controller.state, .recording, "Wer weiterspricht, wird sofort wieder aufgenommen")

        pending.forEach { $0() }
        XCTAssertEqual(inserted, ["Stück 1"])
        XCTAssertEqual(controller.state, .recording, "Die alte Umwandlung beendet die neue Aufnahme nicht")
    }

    func testShortTapIsDiscardedWithoutTranscription() {
        controller.keyPressed()
        microphone.deliver(seconds: 0.1, speech: true)
        clock += DictationController.minDuration / 2
        release()
        XCTAssertEqual(transcriber.chunkLengths, [])
        XCTAssertEqual(inserted, [])
    }

    func testSilenceNeverReachesTheModel() {
        controller.keyPressed()
        microphone.deliver(seconds: 5, speech: false)
        clock += 5
        release()
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
        release()
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
        release()
        XCTAssertEqual(inserted, ["Stück 1", " Stück 2"], "Zweites Stück mit Leerzeichen angehängt")
        XCTAssertEqual(finished, ["Stück 1 Stück 2"])
    }

    func testLiveChunksShareLanguageAndContext() {
        controller.keyPressed()
        microphone.deliver(seconds: 11, speech: true)
        microphone.deliver(seconds: 1, speech: false)
        microphone.deliver(seconds: 4, speech: true)
        clock += 16
        release()
        XCTAssertEqual(transcriber.languages, [nil, "de"], "Sprache wird einmal erkannt und beibehalten")
        XCTAssertEqual(transcriber.prompts, [nil, "Stück 1"], "Vorheriges Stück gibt Zusammenhang")
    }

    func testLiveChunksCoverTheAudioWithoutGapOrOverlap() {
        controller.keyPressed()
        microphone.deliver(seconds: 11, speech: true)
        microphone.deliver(seconds: 1, speech: false)
        microphone.deliver(seconds: 4, speech: true)
        clock += 16
        release()
        XCTAssertEqual(transcriber.chunkLengths.reduce(0, +), Int(16 * AudioBuffer.sampleRate))
    }

    // MARK: Sprache und Modus (SPEC 1.3, 1.5)

    func testFixedLanguageGoesToEveryChunk() {
        controller.language = "de"
        controller.keyPressed()
        microphone.deliver(seconds: 11, speech: true)
        microphone.deliver(seconds: 1, speech: false)
        microphone.deliver(seconds: 4, speech: true)
        clock += 16
        release()
        XCTAssertEqual(transcriber.languages, ["de", "de"], "Fest gewählte Sprache, kein Raten")
    }

    func testModeChangeDuringRecordingAppliesToNextDictation() {
        controller.keyPressed()
        controller.mode = .atEnd
        microphone.deliver(seconds: 11, speech: true)
        microphone.deliver(seconds: 1, speech: false)
        XCTAssertEqual(inserted, ["Stück 1"], "Die laufende Aufnahme bleibt live")
    }

    func testDictationAfterLockIsNotDelivered() {
        var delivered: [Bool] = []
        controller.onDictationFinished = { _, isDelivered, _ in delivered.append(isDelivered) }
        controller.keyPressed()
        microphone.deliver(seconds: 3, speech: true)
        clock += 3
        controller.stopUnexpectedly(reason: "weil der Bildschirm gesperrt wurde", insert: false)
        XCTAssertEqual(delivered, [false], "Gesperrt: nur in den Verlauf, nicht in die Zwischenablage")
    }

    func testPreviewGetsDraftsBeforeTheFirstChunkIsReady() {
        var drafts: [String] = []
        controller.deliversDrafts = true
        controller.onDraft = { draft, _ in drafts.append(draft) }
        controller.keyPressed()
        microphone.deliver(seconds: 2, speech: true)
        XCTAssertEqual(drafts.count, 1, "Nach 1,5 Sekunden gibt es schon vorläufigen Text")
        XCTAssertEqual(inserted, [], "Vorläufiger Text wird nie eingefügt")
        XCTAssertEqual(microphone.buffer?.count, Int(2 * AudioBuffer.sampleRate), "Probelauf löscht kein Audio")
    }

    func testNoDraftsWithoutPreview() {
        var drafts: [String] = []
        controller.onDraft = { draft, _ in drafts.append(draft) }
        controller.keyPressed()
        microphone.deliver(seconds: 5, speech: true)
        XCTAssertEqual(drafts, [])
    }
}
