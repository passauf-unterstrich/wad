// ChunkPlannerTests.swift
// Prüft, wo das Live-Chunking schneidet: nur in Pausen, nie zu früh, spätestens beim Notschnitt.

import XCTest

final class ChunkPlannerTests: XCTestCase {
    private func s(_ seconds: Double) -> Int { Int(seconds * AudioBuffer.sampleRate) }

    func testNoCutBeforeMinimumLength() {
        let speech = [s(0)..<s(4), s(5)..<s(8)]
        XCTAssertNil(ChunkPlanner.cutPoint(speech: speech, length: s(9)))
    }

    func testCutsInTheMiddleOfAPauseAfterMinimum() {
        let speech = [s(0)..<s(11), s(12)..<s(14)]
        XCTAssertEqual(ChunkPlanner.cutPoint(speech: speech, length: s(14)), s(11.5))
    }

    func testIgnoresShortBreathingGaps() {
        let speech = [s(0)..<s(11), s(11.3)..<s(14)]
        XCTAssertNil(ChunkPlanner.cutPoint(speech: speech, length: s(14)))
    }

    func testCutsInTrailingSilenceWhenSpeakerPauses() {
        let speech = [s(0)..<s(12)]
        XCTAssertEqual(ChunkPlanner.cutPoint(speech: speech, length: s(13)), s(12.5))
    }

    func testEmergencyCutWithoutAnyPause() {
        let speech = [s(0)..<s(31)]
        XCTAssertEqual(ChunkPlanner.cutPoint(speech: speech, length: s(31)), ChunkPlanner.maxChunk)
    }

    func testEmergencyCutPrefersLongestShortGap() {
        let speech = [s(0)..<s(15), s(15.4)..<s(20), s(20.2)..<s(31)]
        XCTAssertEqual(ChunkPlanner.cutPoint(speech: speech, length: s(31)), s(15.2))
    }

    func testSilenceIsNotSpeech() {
        XCTAssertFalse(ChunkPlanner.containsSpeech([]))
        XCTAssertFalse(ChunkPlanner.containsSpeech([s(1)..<s(1.1)]))
        XCTAssertTrue(ChunkPlanner.containsSpeech([s(1)..<s(2)]))
    }
}
