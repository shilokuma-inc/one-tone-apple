//
//  TutorialTests.swift
//  OneToneTests
//

import XCTest
@testable import OneTone

final class TutorialTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        // 標準の UserDefaults を汚さないよう、テストごとに専用の suite を使う
        suiteName = "TutorialTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    // MARK: - ページ定義

    func testPagesFollowAgreedOrder() {
        XCTAssertEqual(Tutorial.pages.map(\.id), [.welcome, .playback, .frequency, .volume, .waveform, .note, .chord])
        XCTAssertEqual(Tutorial.pages.map(\.id), TutorialPage.ID.allCases)
    }

    // 文言は端末の言語で訳されるので、ロケールに依存しないようキー（英語の原文）で比べる

    func testEveryPageHasTextAndDistinctImage() {
        for page in Tutorial.pages {
            XCTAssertFalse(page.title.key.isEmpty, "\(page.id) のタイトルが空")
            XCTAssertFalse(page.message.key.isEmpty, "\(page.id) の本文が空")
        }
        let imageNames = Tutorial.pages.map(\.imageName)
        XCTAssertEqual(Set(imageNames).count, imageNames.count)
        XCTAssertEqual(Tutorial.pages.first?.imageName, "Tutorial-welcome")
    }

    func testVolumePageWarnsAboutHearingAndSpeakers() throws {
        let page = try XCTUnwrap(Tutorial.pages.first { $0.id == .volume })
        let caution = try XCTUnwrap(page.caution).key
        XCTAssertTrue(caution.localizedCaseInsensitiveContains("hearing"))
        XCTAssertTrue(caution.localizedCaseInsensitiveContains("speakers"))
    }

    func testOnlyFrequencyAndWaveformPagesHaveTrials() {
        let trials = Dictionary(uniqueKeysWithValues: Tutorial.pages.map { ($0.id, $0.trial) })
        XCTAssertEqual(trials[.frequency], .tone(frequency: 440))
        XCTAssertEqual(trials[.waveform], .waveforms(frequency: 440))
        for id in [TutorialPage.ID.welcome, .playback, .volume, .note, .chord] {
            XCTAssertEqual(trials[id], .some(nil), "\(id) に試聴は無い")
        }
    }

    func testFrequencyPageMentionsRangeAndPresets() throws {
        let message = try XCTUnwrap(Tutorial.pages.first { $0.id == .frequency }).message.key
        for label in ["20 Hz", "20 kHz"] + FrequencyInput.presets.map(FrequencyInput.presetLabel) {
            XCTAssertTrue(message.contains(label), "周波数ページに \(label) が無い")
        }
    }

    func testWaveformPageMentionsEveryWaveform() throws {
        let message = try XCTUnwrap(Tutorial.pages.first { $0.id == .waveform }).message.key
        for waveform in Waveform.allCases {
            XCTAssertTrue(message.contains(waveform.displayName), "波形ページに \(waveform.displayName) が無い")
        }
    }

    /// 音名・和音モードのページは、設定の FREQUENCY MODE の選び方と例の音名・コード名（訳さない）を書く
    func testNoteAndChordPagesMentionModeAndExamples() throws {
        let note = try XCTUnwrap(Tutorial.pages.first { $0.id == .note }).message.key
        for word in ["FREQUENCY MODE", FrequencyMode.note.label, "A4", "C#5"] {
            XCTAssertTrue(note.contains(word), "音名ページに \(word) が無い")
        }
        let chord = try XCTUnwrap(Tutorial.pages.first { $0.id == .chord }).message.key
        for word in ["FREQUENCY MODE", FrequencyMode.chord.label, "C, G, or Am", "Major", "Minor"] {
            XCTAssertTrue(chord.contains(word), "和音ページに \(word) が無い")
        }
        for name in ["C", "G", "Am"] {
            XCTAssertTrue(ChordInput.pads.map(\.name).contains(name), "和音ページの \(name) がパッドに無い")
        }
    }

    /// 画像を撮る前のページは記号を出す。既存のページの画像はアプリに入っている
    func testPlaceholderSymbolsAndImages() {
        XCTAssertEqual(Tutorial.pages.first { $0.id == .note }?.placeholderSymbol, "music.note")
        XCTAssertEqual(Tutorial.pages.first { $0.id == .chord }?.placeholderSymbol, "pianokeys")
        for id in [TutorialPage.ID.welcome, .playback, .frequency, .volume, .waveform] {
            XCTAssertTrue(TutorialImage.exists(named: "Tutorial-\(id.rawValue)"), "\(id) の画像が無い")
        }
        XCTAssertFalse(TutorialImage.exists(named: "Tutorial-does-not-exist"))
    }

    // MARK: - 既読

    func testStoreIsUnseenByDefault() {
        XCTAssertFalse(TutorialSeenStore(defaults: defaults).hasSeen)
    }

    func testEveryDismissalMarksAsSeen() throws {
        for dismissal in [TutorialDismissal.skipped, .completed, .closed] {
            let name = "TutorialTests.\(UUID().uuidString)"
            let isolated = try XCTUnwrap(UserDefaults(suiteName: name))
            defer { isolated.removePersistentDomain(forName: name) }

            let store = TutorialSeenStore(defaults: isolated)
            store.record(dismissal)
            XCTAssertTrue(store.hasSeen, "\(dismissal) で既読にならない")
        }
    }

    func testStoreUsesAppStorageKey() {
        // ContentView の @AppStorage("hasSeenTutorial") と同じ値を読み書きする
        TutorialSeenStore(defaults: defaults).record(.skipped)
        XCTAssertTrue(defaults.bool(forKey: "hasSeenTutorial"))
        XCTAssertEqual(Tutorial.hasSeenKey, "hasSeenTutorial")
    }

    // MARK: - 自動表示

    func testPresentsAutomaticallyOnlyWhenUnseen() {
        XCTAssertTrue(Tutorial.shouldPresentAutomatically(hasSeen: false, arguments: []))
        XCTAssertFalse(Tutorial.shouldPresentAutomatically(hasSeen: true, arguments: []))
    }

    func testDoesNotPresentAutomaticallyInScreenshotDemo() {
        XCTAssertFalse(Tutorial.shouldPresentAutomatically(hasSeen: false, arguments: ["-screenshot-demo", "-screenshot-scene", "sine"]))
    }

    func testDoesNotPresentAutomaticallyWithSkipArgument() {
        XCTAssertFalse(Tutorial.shouldPresentAutomatically(hasSeen: false, arguments: ["-skip-tutorial"]))
    }

    func testStoreAndAutomaticPresentationWorkTogether() {
        let store = TutorialSeenStore(defaults: defaults)
        XCTAssertTrue(Tutorial.shouldPresentAutomatically(hasSeen: store.hasSeen, arguments: []))
        store.record(.closed)
        XCTAssertFalse(Tutorial.shouldPresentAutomatically(hasSeen: store.hasSeen, arguments: []))
    }

    // MARK: - ページ送り

    func testPagerMovesWithinBounds() {
        var pager = TutorialPager(pageCount: 3)
        XCTAssertTrue(pager.isFirstPage)
        pager.back()
        XCTAssertEqual(pager.index, 0)

        pager.next()
        pager.next()
        XCTAssertEqual(pager.index, 2)
        XCTAssertTrue(pager.isLastPage)
        pager.next()
        XCTAssertEqual(pager.index, 2)

        pager.back()
        XCTAssertEqual(pager.index, 1)
        XCTAssertFalse(pager.isFirstPage)
        XCTAssertFalse(pager.isLastPage)
    }

    func testPagerClampsDirectSelection() {
        var pager = TutorialPager(pageCount: 5)
        pager.show(10)
        XCTAssertEqual(pager.index, 4)
        pager.show(-1)
        XCTAssertEqual(pager.index, 0)
    }

    func testPagerDefaultsToTutorialPageCount() {
        XCTAssertEqual(TutorialPager().pageCount, Tutorial.pages.count)
    }
}
