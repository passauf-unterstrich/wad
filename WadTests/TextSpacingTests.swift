// TextSpacingTests.swift
// Prüft Sprachen ohne Leerzeichen zwischen Wörtern: Japanisch und Chinesisch dürfen beim Zusammensetzen
// von Stücken keine Leerzeichen bekommen, alle anderen Sprachen bleiben wie bisher.

import XCTest

final class TextSpacingTests: XCTestCase {
    func testLatinTextGetsSpacesExceptBeforePunctuation() {
        XCTAssertEqual(TextSpacing.join("Hallo", "Welt"), "Hallo Welt")
        XCTAssertEqual(TextSpacing.join("Hallo", ", Welt"), "Hallo, Welt")
        XCTAssertEqual(TextSpacing.join("", "Welt"), "Welt")
        XCTAssertEqual(TextSpacing.join("Hallo ", "Welt"), "Hallo Welt")
    }

    func testJapaneseAndChineseStayWithoutSpaces() {
        XCTAssertEqual(TextSpacing.join("今日は", "天気がいいです。"), "今日は天気がいいです。")
        XCTAssertEqual(TextSpacing.join("カタカナー", "です"), "カタカナーです")
        XCTAssertEqual(TextSpacing.join("今天天气很好。", "我们出去吧"), "今天天气很好。我们出去吧")
        XCTAssertEqual(TextSpacing.join("Wad", "を使います"), "Wadを使います")
        XCTAssertEqual(TextSpacing.join("使うのは", "Wad"), "使うのはWad")
        XCTAssertEqual(TextSpacing.join("はい！", "ＯＫ"), "はい！ＯＫ")
    }

    func testKoreanKeepsItsSpaces() {
        XCTAssertEqual(TextSpacing.join("안녕하세요", "감사합니다"), "안녕하세요 감사합니다")
    }

    // MARK: Vokabeln

    func testJapaneseTermsAreReplacedInsideText() {
        let vocabulary = Vocabulary(text: "ワット -> Wad")
        XCTAssertEqual(vocabulary.apply(to: "ワットを使います"), "Wadを使います")
    }

    func testChineseTermsAreReplacedInsideText() {
        let vocabulary = Vocabulary(text: "瓦德 -> Wad")
        XCTAssertEqual(vocabulary.apply(to: "我用瓦德听写"), "我用Wad听写")
    }

    func testLatinTermsAreFoundNextToJapanese() {
        let vocabulary = Vocabulary(text: "Watt -> Wad")
        XCTAssertEqual(vocabulary.apply(to: "Wattを使います"), "Wadを使います")
        XCTAssertEqual(vocabulary.apply(to: "Wattestäbchenを使います"), "Wattestäbchenを使います", "Ganze Wörter gelten weiter")
    }

    func testReplacementThatMergesWithItsNeighbourDoesNotCrash() {
        let vocabulary = Vocabulary(text: "ワット -> \u{0301}")
        XCTAssertEqual(vocabulary.apply(to: "eワット").count, 1, "Der Akzent verschmilzt mit dem e, der Text wird kürzer")
    }

    func testLowercaseLeavesJapaneseAlone() {
        XCTAssertEqual("WadをOKで使う".lowercased(), "wadをokで使う")
    }

    // MARK: Vorschau-Fenster

    func testPreviewJoinsJapaneseWithoutSpaces() {
        let page = PageTextView()
        page.beginDictation(atCursor: false)
        page.appendFinal("今日は")
        page.appendFinal("天気がいいです。")
        page.setDraft("明日も")
        XCTAssertEqual(page.string, "今日は天気がいいです。明日も")
        XCTAssertEqual(page.pageText, "今日は天気がいいです。")
    }

    func testPreviewInsertsJapaneseInsideTextWithoutSpaces() {
        let page = PageTextView()
        page.beginDictation(atCursor: false)
        page.appendFinal("今日はです")
        page.setSelectedRange(NSRange(location: 3, length: 0))
        page.beginDictation(atCursor: true)
        page.appendFinal("いい天気")
        XCTAssertEqual(page.pageText, "今日はいい天気です")
    }

    func testPreviewHandlesCharactersThatTakeTwoPlaces() {
        let page = PageTextView()
        page.beginDictation(atCursor: false)
        page.appendFinal("𠮷")
        page.appendFinal("野家")
        XCTAssertEqual(page.pageText, "𠮷野家")
    }

    // MARK: Diktat

    private func session(language: String?, hint: String? = nil, transcriber: FakeTranscriber) -> DictationSession {
        let audio = AudioBuffer(maxDuration: 60)
        let samples = [Float](repeating: 0.5, count: Int(2 * AudioBuffer.sampleRate))
        samples.withUnsafeBufferPointer { audio.append($0) }
        return DictationSession(audio: audio, transcriber: transcriber, language: language, vocabularyHint: hint)
    }

    private func dictate(_ session: DictationSession, chunks: Int) -> [String] {
        (0..<chunks).compactMap { _ in
            let samples = [Float](repeating: 0.5, count: Int(2 * AudioBuffer.sampleRate))
            samples.withUnsafeBufferPointer { session.audio.append($0) }
            return session.transcribeRemainder()
        }
    }

    func testLiveChunksInJapaneseGetNoSpace() {
        let transcriber = FakeTranscriber()
        transcriber.texts = ["今日は", "天気がいいです。"]
        let session = session(language: "ja", transcriber: transcriber)
        XCTAssertEqual(dictate(session, chunks: 2), ["今日は", "天気がいいです。"])
        XCTAssertEqual(session.fullText, "今日は天気がいいです。")
    }

    func testAutoDetectedJapaneseAlsoGetsNoSpace() {
        let transcriber = FakeTranscriber()
        transcriber.texts = ["今日は", "天気がいいです。"]
        transcriber.detectedLanguage = "ja"
        let session = session(language: nil, transcriber: transcriber)
        XCTAssertEqual(dictate(session, chunks: 2), ["今日は", "天気がいいです。"])
        XCTAssertEqual(session.fullText, "今日は天気がいいです。")
    }

    func testChunksInFinnishKeepSpaces() {
        let transcriber = FakeTranscriber()
        transcriber.texts = ["Hyvää", "huomenta."]
        let session = session(language: "fi", transcriber: transcriber)
        XCTAssertEqual(dictate(session, chunks: 2), ["Hyvää", " huomenta."])
        XCTAssertEqual(session.fullText, "Hyvää huomenta.")
    }

    func testChineseGetsTheSimplifiedHintWithVocabulary() {
        let transcriber = FakeTranscriber()
        let session = session(language: "zh", hint: "Wad.", transcriber: transcriber)
        _ = dictate(session, chunks: 2)
        XCTAssertEqual(transcriber.prompts, ["Wad. 以下是普通话的句子。", "Wad. 以下是普通话的句子。 Stück 1"])
    }

    func testChineseHintWorksWithoutVocabulary() {
        let transcriber = FakeTranscriber()
        _ = dictate(session(language: "zh", transcriber: transcriber), chunks: 1)
        XCTAssertEqual(transcriber.prompts, ["以下是普通话的句子。"])
    }

    func testAutoDetectedChineseGetsTheHintFromTheSecondChunk() {
        let transcriber = FakeTranscriber()
        transcriber.detectedLanguage = "zh"
        _ = dictate(session(language: nil, transcriber: transcriber), chunks: 2)
        XCTAssertEqual(transcriber.prompts, [nil, "以下是普通话的句子。 Stück 1"])
    }

    func testOtherLanguagesGetNoChineseHint() {
        for language in ["de", "ja", "fi", "sw"] {
            let transcriber = FakeTranscriber()
            _ = dictate(session(language: language, hint: "Wad.", transcriber: transcriber), chunks: 1)
            XCTAssertEqual(transcriber.prompts, ["Wad."], language)
        }
    }

    // MARK: Leerzeichen nach dem Satzende (1.3.1)

    func testMissingSpaceAfterSentenceIsAdded() {
        XCTAssertEqual(TextSpacing.separatingSentences("Das ist gut.Dann gehen wir."), "Das ist gut. Dann gehen wir.")
        XCTAssertEqual(TextSpacing.separatingSentences("Wirklich?Ja!Schön"), "Wirklich? Ja! Schön")
        XCTAssertEqual(TextSpacing.separatingSentences("Das ist gut. Dann"), "Das ist gut. Dann")
    }

    func testAbbreviationsNumbersAndNamesStay() {
        for text in ["z.B. morgen", "Die U.S.A. sind groß", "Version 3.5 kommt", "linushundt.com/wad",
                     "mit ASP.NET", "Wad.app", "um 12.Mai", "今日は。明日"] {
            XCTAssertEqual(TextSpacing.separatingSentences(text), text)
        }
    }

    func testNewDictationAfterSentenceGetsSpace() {
        XCTAssertTrue(TextSpacing.needsSpace(between: ".", and: "D"))
        XCTAssertFalse(TextSpacing.needsSpace(between: nil, and: "D"))
        XCTAssertFalse(TextSpacing.needsSpace(between: " ", and: "D"))
        XCTAssertFalse(TextSpacing.needsSpace(between: "\n", and: "D"))
        XCTAssertFalse(TextSpacing.needsSpace(between: "(", and: "D"))
        XCTAssertFalse(TextSpacing.needsSpace(between: "„", and: "D"))
    }

    // MARK: Kleinschreibung (1.3.1)

    func testLowercaseHasNoCapitalsAndNoEszett() {
        XCTAssertEqual(TextSpacing.lowercased("Die Straße ist GROSS und weiß."), "die strasse ist gross und weiss.")
        XCTAssertEqual(TextSpacing.lowercased("STRAẞE"), "strasse")
        XCTAssertEqual(TextSpacing.lowercased("Ärger über Öl"), "ärger über öl")
    }

    // MARK: Angesagte Satzzeichen (1.3.1)

    func testSpokenPunctuationBecomesMarks() {
        XCTAssertEqual(SpokenPunctuation.apply(to: "Das ist gut Komma dann gehen wir Punkt"), "Das ist gut, dann gehen wir.")
        XCTAssertEqual(SpokenPunctuation.apply(to: "Das ist gut, Komma, dann gehen wir. Punkt."), "Das ist gut, dann gehen wir.")
        XCTAssertEqual(SpokenPunctuation.apply(to: "Wie geht es dir Fragezeichen mir geht es gut Ausrufezeichen"),
                       "Wie geht es dir? Mir geht es gut!")
        XCTAssertEqual(SpokenPunctuation.apply(to: "Hallo neue Zeile wie geht's"), "Hallo\nWie geht's")
        XCTAssertEqual(SpokenPunctuation.apply(to: "Hallo. Neuer Absatz. Wie geht's?"), "Hallo.\n\nWie geht's?")
        XCTAssertEqual(SpokenPunctuation.apply(to: "Einkaufen Doppelpunkt Milch"), "Einkaufen: Milch")
        XCTAssertEqual(SpokenPunctuation.apply(to: "Dear John comma how are you question mark"), "Dear John, how are you?")
        XCTAssertEqual(SpokenPunctuation.apply(to: " Punkt."), ".")
    }

    func testRealWordsStay() {
        for text in ["Das ist der springende Punkt.", "Wir treffen uns Punkt 12 Uhr.", "Punkt für Punkt.",
                     "Nach dem Komma kommt die Fünf.", "Ein wichtiger Punkt ist das.", "Unser Treffpunkt.",
                     "Es kommt eine neue Zeile.", "It was a period of change.", "Die Punkte zählen."] {
            XCTAssertEqual(SpokenPunctuation.apply(to: text), text)
        }
    }
}
