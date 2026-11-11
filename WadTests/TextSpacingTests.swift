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

    // MARK: Absätze automatisch (1.3.2)

    func testShortPauseMakesNoParagraph() {
        var planner = ParagraphPlanner()
        XCTAssertEqual(planner.layout("Eins. Zwei.", after: nil, pause: 0), "Eins. Zwei.")
        XCTAssertEqual(planner.layout("Drei.", after: "Eins. Zwei.", pause: 1.9), " Drei.")
    }

    func testOneSentenceMakesNoParagraph() {
        var planner = ParagraphPlanner()
        XCTAssertEqual(planner.layout("Eins.", after: nil, pause: 0), "Eins.")
        XCTAssertEqual(planner.layout("Zwei.", after: "Eins.", pause: 3), " Zwei.")
    }

    func testLongPauseAfterTwoSentencesMakesParagraph() {
        var planner = ParagraphPlanner()
        XCTAssertEqual(planner.layout("Eins. Zwei.", after: nil, pause: 0), "Eins. Zwei.")
        XCTAssertEqual(planner.layout("Drei.", after: "Eins. Zwei.", pause: 2.5), "\n\nDrei.")
        // Danach zählt der neue Absatz von vorn.
        XCTAssertEqual(planner.layout("Vier.", after: "\n\nDrei.", pause: 2.5), " Vier.")
    }

    func testNoParagraphInsideASentence() {
        var planner = ParagraphPlanner()
        _ = planner.layout("Eins. Zwei. Und dann", after: nil, pause: 0)
        XCTAssertEqual(planner.layout("ging es weiter.", after: "Eins. Zwei. Und dann", pause: 3), " ging es weiter.")
    }

    func testParagraphAfterSixSentencesEvenWithoutPause() {
        var planner = ParagraphPlanner()
        XCTAssertEqual(planner.layout("Eins. Zwei. Drei. Vier. Fünf. Sechs. Sieben. Acht.", after: nil, pause: 0),
                       "Eins. Zwei. Drei. Vier. Fünf. Sechs.\n\nSieben. Acht.")
        var other = ParagraphPlanner()
        let first = other.layout("Eins. Zwei. Drei. Vier. Fünf. Sechs.", after: nil, pause: 0)
        XCTAssertEqual(first, "Eins. Zwei. Drei. Vier. Fünf. Sechs.")
        XCTAssertEqual(other.layout("Sieben.", after: first, pause: 0), "\n\nSieben.")
    }

    func testParagraphsInJapanese() {
        var planner = ParagraphPlanner()
        XCTAssertEqual(planner.layout("一。二。三。四。五。六。七。", after: nil, pause: 0), "一。二。三。四。五。六。\n\n七。")
        var other = ParagraphPlanner()
        _ = other.layout("一。二。", after: nil, pause: 0)
        XCTAssertEqual(other.layout("三。", after: "一。二。", pause: 2.5), "\n\n三。")
    }

    func testGreetingGetsItsOwnLine() {
        var planner = ParagraphPlanner()
        XCTAssertEqual(planner.layout("Hallo Anna, wie geht es dir? Ich wollte fragen. Kommst du morgen?", after: nil, pause: 0),
                       "Hallo Anna,\n\nwie geht es dir? Ich wollte fragen. Kommst du morgen?")
        var english = ParagraphPlanner()
        XCTAssertEqual(english.layout("Dear John, thanks for the call. See you soon.", after: nil, pause: 0),
                       "Dear John,\n\nthanks for the call. See you soon.")
    }

    func testGreetingWordsThatAreAlsoOrdinaryWordsNeedAName() {
        var love = ParagraphPlanner()
        XCTAssertEqual(love.layout("Liebe ist schön, aber anstrengend. Das weiß jeder. Wirklich.", after: nil, pause: 0),
                       "Liebe ist schön, aber anstrengend. Das weiß jeder. Wirklich.")
        var anna = ParagraphPlanner()
        XCTAssertEqual(anna.layout("Liebe Anna, danke für alles. Es war schön. Bis bald.", after: nil, pause: 0),
                       "Liebe Anna,\n\ndanke für alles. Es war schön. Bis bald.")
        var all = ParagraphPlanner()
        XCTAssertEqual(all.layout("Hallo zusammen, kurz zum Termin. Er ist morgen. Bitte kommt pünktlich.", after: nil, pause: 0),
                       "Hallo zusammen,\n\nkurz zum Termin. Er ist morgen. Bitte kommt pünktlich.")
    }

    func testShortClosingsInMessagesNeedAName() {
        let cases = [
            ("Kommst du morgen? Gruß Linus", "Kommst du morgen?\n\nGruß\nLinus"),
            ("Bin gleich da. LG, Anna.", "Bin gleich da.\n\nLG\nAnna"),
            ("Danke dir. Viele Grüsse, Linus", "Danke dir.\n\nViele Grüsse\nLinus"),
            ("Bis morgen. Viele liebe Grüße, Anna", "Bis morgen.\n\nViele liebe Grüße\nAnna"),
            ("Das war's. Danke.", "Das war's. Danke."),
            ("Gruß Linus", "Gruß Linus"),
        ]
        for (text, expected) in cases {
            var planner = ParagraphPlanner()
            XCTAssertEqual(planner.layout(text, after: nil, pause: 0), expected)
        }
    }

    func testBrandNamesAreNoClosing() {
        var planner = ParagraphPlanner()
        XCTAssertEqual(planner.layout("Ich kaufe einen Fernseher. Er ist neu. LG ist gut.", after: nil, pause: 0),
                       "Ich kaufe einen Fernseher. Er ist neu. LG ist gut.")
    }

    func testShortMessageKeepsItsGreeting() {
        var planner = ParagraphPlanner()
        XCTAssertEqual(planner.layout("Hey, bin gleich da.", after: nil, pause: 0), "Hey, bin gleich da.")
        // Nur im ersten Stück eines Diktats.
        XCTAssertEqual(planner.layout("Hallo Anna, wie geht's? Gut. Schön.", after: "Hey, bin gleich da.", pause: 0),
                       " Hallo Anna, wie geht's? Gut. Schön.")
    }

    func testClosingGetsItsOwnParagraphAndTheNameItsOwnLine() {
        var planner = ParagraphPlanner()
        XCTAssertEqual(planner.layout("Ich komme vorbei. Dann bis morgen. Viele Grüße, Linus.", after: nil, pause: 0),
                       "Ich komme vorbei. Dann bis morgen.\n\nViele Grüße\nLinus")
        var english = ParagraphPlanner()
        XCTAssertEqual(english.layout("Thanks a lot. Talk soon. Best regards, Anna Maria Schmidt!", after: nil, pause: 0),
                       "Thanks a lot. Talk soon.\n\nBest regards\nAnna Maria Schmidt")
    }

    func testClosingWithoutNameOrInItsOwnPiece() {
        var planner = ParagraphPlanner()
        XCTAssertEqual(planner.layout("Das war's. Bis bald. Liebe Grüße an alle.", after: nil, pause: 0),
                       "Das war's. Bis bald.\n\nLiebe Grüße an alle.")
        var other = ParagraphPlanner()
        let first = other.layout("Das war's. Bis bald.", after: nil, pause: 0)
        XCTAssertEqual(other.layout("Viele Grüße, Linus.", after: first, pause: 0.7), "\n\nViele Grüße\nLinus")
    }

    func testClosingNeedsALetterBeforeIt() {
        var planner = ParagraphPlanner()
        XCTAssertEqual(planner.layout("Viele Grüße, Linus.", after: nil, pause: 0), "Viele Grüße, Linus.")
        var other = ParagraphPlanner()
        XCTAssertEqual(other.layout("Ich soll viele Grüße ausrichten. Von Anna. Und Tom.", after: nil, pause: 0),
                       "Ich soll viele Grüße ausrichten. Von Anna. Und Tom.")
    }

    func testGroupsSplitOnlyAtLongPauses() {
        let groups = ParagraphPlanner.groups(speech: [10..<20, 25..<35, 60..<70], length: 80, pause: 20, minSpeech: 5)
        XCTAssertEqual(groups.map(\.range), [0..<47, 47..<80])
        XCTAssertEqual(groups.map(\.pauseBefore), [10, 25])
        // Ein Räuspern nach der Pause bleibt bei seinen Nachbarn.
        let merged = ParagraphPlanner.groups(speech: [10..<20, 50..<52], length: 60, pause: 20, minSpeech: 5)
        XCTAssertEqual(merged.map(\.range), [0..<60])
    }

    func testSpokenParagraph() {
        XCTAssertEqual(SpokenPunctuation.apply(to: "Erster Teil Absatz zweiter Teil"), "Erster Teil\n\nZweiter Teil")
        XCTAssertEqual(SpokenPunctuation.apply(to: "Erster Teil. Absatz.\n\nDann weiter."), "Erster Teil.\n\nDann weiter.")
        XCTAssertEqual(SpokenPunctuation.apply(to: "Erster Teil. Neuer Absatz. Dann weiter."), "Erster Teil.\n\nDann weiter.")
        XCTAssertEqual(SpokenPunctuation.apply(to: "Eins. Absatz, neuer Absatz. Zwei."), "Eins.\n\nZwei.")
        for text in ["Der Absatz ist zu lang.", "Siehe Absatz 2.", "Im zweiten Absatz steht es."] {
            XCTAssertEqual(SpokenPunctuation.apply(to: text), text)
        }
    }

    func testNeverTwoBlankLinesInARow() {
        XCTAssertEqual(TextSpacing.trimmingLeadingBreak("\n\nZwei.", after: "\n"), "Zwei.")
        XCTAssertEqual(TextSpacing.trimmingLeadingBreak(" Zwei.", after: "\n"), "Zwei.")
        XCTAssertEqual(TextSpacing.trimmingLeadingBreak("\n\nZwei.", after: "."), "\n\nZwei.")
        let page = PageTextView()
        page.beginDictation(atCursor: false)
        page.appendFinal("Eins.\n\n")
        page.appendFinal("\n\nZwei.")
        XCTAssertEqual(page.pageText, "Eins.\n\nZwei.")
    }

    /// Ein Diktat aus Sprache, Stille, Sprache, in Sekunden.
    private func paragraphSession(autoParagraphs: Bool, transcriber: FakeTranscriber) -> DictationSession {
        let audio = AudioBuffer(maxDuration: 60)
        for (seconds, speech) in [(1.0, true), (2.5, false), (1.0, true)] {
            let samples = [Float](repeating: speech ? 0.5 : 0, count: Int(seconds * AudioBuffer.sampleRate))
            samples.withUnsafeBufferPointer { audio.append($0) }
        }
        return DictationSession(audio: audio, transcriber: transcriber, language: "de", autoParagraphs: autoParagraphs)
    }

    func testSessionMakesParagraphAtLongPauseOnlyWhenSwitchedOn() {
        let transcriber = FakeTranscriber()
        transcriber.texts = ["Eins. Zwei.", "Drei."]
        let session = paragraphSession(autoParagraphs: true, transcriber: transcriber)
        XCTAssertEqual(session.transcribeRemainder(), "Eins. Zwei.\n\nDrei.")
        XCTAssertEqual(session.fullText, "Eins. Zwei.\n\nDrei.")
        XCTAssertEqual(transcriber.chunkLengths.count, 2)
        XCTAssertEqual(transcriber.prompts.last, "Eins. Zwei.")

        let plain = FakeTranscriber()
        plain.texts = ["Eins. Zwei. Drei."]
        let off = paragraphSession(autoParagraphs: false, transcriber: plain)
        XCTAssertEqual(off.transcribeRemainder(), "Eins. Zwei. Drei.")
        XCTAssertEqual(plain.chunkLengths, [Int(4.5 * AudioBuffer.sampleRate)])
    }

    func testPauseAcrossPiecesCountsTheSilenceAtTheEnd() {
        let transcriber = FakeTranscriber()
        transcriber.texts = ["Eins. Zwei.", "Drei."]
        let audio = AudioBuffer(maxDuration: 60)
        let session = DictationSession(audio: audio, transcriber: transcriber, language: "de", autoParagraphs: true)
        func add(_ seconds: Double, speech: Bool) {
            let samples = [Float](repeating: speech ? 0.5 : 0, count: Int(seconds * AudioBuffer.sampleRate))
            samples.withUnsafeBufferPointer { audio.append($0) }
        }
        add(1, speech: true); add(1.5, speech: false)
        XCTAssertEqual(session.transcribeRemainder(), "Eins. Zwei.")
        add(1, speech: false); add(1, speech: true)
        XCTAssertEqual(session.transcribeRemainder(), "\n\nDrei.")
    }
}
