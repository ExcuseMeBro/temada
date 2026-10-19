import Foundation

@MainActor enum HistoryTests {
    static func run() {
        ScrollTests.run()
        let captions = Captions()
        var originals: [String] = [], translations: [String] = []
        for index in 0..<240 {
            let original = "Sentence \(index) Привет salom."
            let translation = "Tarjima \(index) Hello перевод."
            originals.append(original); translations.append(translation)
            try! captions.consume(NativeTests.frame(original, translation, source: index.isMultiple(of: 2) ? "system" : "microphone", inputDone: true, outputDone: true))
        }
        guard captions.rows.count == 240 else {
            fputs("HISTORY_SELFTEST: FAIL — scrollback lost completed transcript/translation rows beyond 48\n", stderr); exit(1)
        }
        precondition(captions.rows.map(\.original) == originals && captions.rows.map(\.translation) == translations)
        precondition(Set(captions.rows.map(\.id)).count == 240)
        let longOriginal = String(repeating: "full original Привет salom ", count: 100)
        let longTranslation = String(repeating: "full translation tarjima перевод ", count: 100)
        try! captions.consume(NativeTests.frame(longOriginal, longTranslation, inputDone: true, outputDone: true))
        precondition(captions.rows.count == 241 && captions.rows.last?.original == longOriginal && captions.rows.last?.translation == longTranslation)
        let oldRows = captions.rows
        try! captions.beginMeeting()
        precondition(captions.rows == oldRows)
        try! captions.consume(NativeTests.frame("Next meeting.", "Keyingi uchrashuv.", inputDone: true, outputDone: true))
        precondition(captions.rows.count == 242 && Array(captions.rows.prefix(241)) == oldRows && Set(captions.rows.map(\.id)).count == 242)
        let translationFirst = Captions()
        try! translationFirst.consume(NativeTests.frame(nil, "Tarjima oldin.", outputDone: true))
        precondition(translationFirst.rows.count == 1 && translationFirst.rows[0].translation == "Tarjima oldin.")
        try! translationFirst.consume(NativeTests.frame("Original later.", nil, inputDone: true))
        precondition(translationFirst.rows.count == 1 && translationFirst.rows[0].original == "Original later.")
        let beforeInvalidSource = translationFirst.rows
        do { try translationFirst.consume(WireFrame(kind: "text", source: "unknown", interim: "not valid")); preconditionFailure("Invalid source accepted") } catch {}
        precondition(translationFirst.rows == beforeInvalidSource)
        let bounded = Captions(historyMaxBytes: 1)
        do {
            for _ in 0..<49 { try bounded.consume(NativeTests.frame("Hi.", "Salom.", inputDone: true, outputDone: true)) }
            preconditionFailure("History byte bound bypassed")
        } catch CaptionTimeline.ModelError.historyLimit {} catch { preconditionFailure("Wrong history error") }
        precondition(bounded.rows.count == 49 && bounded.rows.first?.original == "Hi.", "History bound silently dropped text")
        let rowBounded = Captions(historyMaxRows: 2)
        do {
            for _ in 0..<51 { try rowBounded.consume(NativeTests.frame("Hi.", "Salom.", inputDone: true, outputDone: true)) }
            preconditionFailure("History row bound bypassed")
        } catch CaptionTimeline.ModelError.historyLimit {} catch { preconditionFailure("Wrong row-bound error") }
        precondition(rowBounded.rows.count == 51)
        let beforeRejectedStart = rowBounded.rows
        do { try rowBounded.beginMeeting(); preconditionFailure("New meeting bypassed history cap") } catch {}
        precondition(rowBounded.rows == beforeRejectedStart, "Rejected meeting start erased history")
        captions.clear(); precondition(captions.rows.isEmpty)
        try! captions.consume(NativeTests.frame("After clear.", "Tozalangandan keyin.", inputDone: true, outputDone: true))
        precondition(captions.rows.count == 1)
        var follow = CaptionFollowState()
        precondition(follow.latest); follow.userScrolling(); precondition(!follow.latest)
        follow.settled(offset: 0, viewport: 190, content: 1200); precondition(!follow.latest)
        follow.settled(offset: 1010, viewport: 190, content: 1200); precondition(follow.latest)
        print("HISTORY_SELFTEST: PASS — 240 full EN/RU/UZ pairs, both sources, stable IDs across starts, long/translation-first text, explicit clear, bounded fail-without-loss, follow/backscroll state")
    }
}
