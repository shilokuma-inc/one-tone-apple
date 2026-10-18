//
//  ToneSettingsTests.swift
//  OneToneTests
//

import XCTest
@testable import OneTone

final class ToneSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        // 標準の UserDefaults を汚さないよう、テストごとに専用の suite を使う
        suiteName = "ToneSettingsTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
    }

    // MARK: - 既定値

    func testDefaultIs440HzHalfVolumeSine() {
        XCTAssertEqual(ToneSettings.default, ToneSettings(frequency: 440, volume: 0.5, waveform: .sine))
    }

    func testLoadWithoutStoredValuesReturnsDefault() {
        XCTAssertEqual(ToneSettingsStore(defaults: defaults).load(), .default)
    }

    // MARK: - 保存と復元

    func testSavedValuesAreRestored() {
        let store = ToneSettingsStore(defaults: defaults)
        store.save(frequency: 1234.5)
        store.save(volume: 0.8)
        store.save(waveform: .sawtooth)

        // 次回の起動を想定し、別のインスタンスで読む
        XCTAssertEqual(ToneSettingsStore(defaults: defaults).load(), ToneSettings(frequency: 1234.5, volume: 0.8, waveform: .sawtooth))
    }

    func testEveryWaveformRoundTrips() {
        let store = ToneSettingsStore(defaults: defaults)
        for waveform in Waveform.allCases {
            store.save(waveform: waveform)
            XCTAssertEqual(store.load().waveform, waveform)
        }
    }

    func testRangeBoundsAreRestored() {
        let store = ToneSettingsStore(defaults: defaults)
        for (frequency, volume) in [(20.0, 0.0), (20000.0, 1.0)] {
            store.save(frequency: frequency)
            store.save(volume: volume)
            XCTAssertEqual(store.load().frequency, frequency)
            XCTAssertEqual(store.load().volume, volume)
        }
    }

    func testValuesStoredAsIntegersAreRestored() {
        defaults.set(1000, forKey: ToneSettingsStore.frequencyKey)
        defaults.set(1, forKey: ToneSettingsStore.volumeKey)
        XCTAssertEqual(ToneSettingsStore(defaults: defaults).load().frequency, 1000)
        XCTAssertEqual(ToneSettingsStore(defaults: defaults).load().volume, 1)
    }

    // MARK: - 範囲外・壊れた値

    func testOutOfRangeFrequencyFallsBackToDefault() {
        for value in [19.9, 20000.1, 0, -440, .nan, .infinity] {
            defaults.set(value, forKey: ToneSettingsStore.frequencyKey)
            XCTAssertEqual(ToneSettingsStore(defaults: defaults).load().frequency, ToneSettings.default.frequency, "\(value)")
        }
    }

    func testOutOfRangeVolumeFallsBackToDefault() {
        for value in [-0.01, 1.01, 100, .nan] {
            defaults.set(value, forKey: ToneSettingsStore.volumeKey)
            XCTAssertEqual(ToneSettingsStore(defaults: defaults).load().volume, ToneSettings.default.volume, "\(value)")
        }
    }

    func testUnknownWaveformFallsBackToDefault() {
        for value in [4.0, -1, 0.5, 256] {
            defaults.set(value, forKey: ToneSettingsStore.waveformKey)
            XCTAssertEqual(ToneSettingsStore(defaults: defaults).load().waveform, ToneSettings.default.waveform, "\(value)")
        }
    }

    func testValuesOfWrongTypeFallBackToDefault() {
        // 文字列は `double(forKey:)` だと数値に変換されてしまうが、壊れた値として扱う
        for value in ["1000", "abc", Data([1, 2]), [440], ["frequency": 440]] as [Any] {
            defaults.set(value, forKey: ToneSettingsStore.frequencyKey)
            defaults.set(value, forKey: ToneSettingsStore.volumeKey)
            defaults.set(value, forKey: ToneSettingsStore.waveformKey)
            XCTAssertEqual(ToneSettingsStore(defaults: defaults).load(), .default, "\(value)")
        }
        defaults.set(true, forKey: ToneSettingsStore.volumeKey)
        defaults.set(true, forKey: ToneSettingsStore.waveformKey)
        XCTAssertEqual(ToneSettingsStore(defaults: defaults).load(), .default)
    }

    func testOnlyBrokenItemFallsBackToDefault() {
        let store = ToneSettingsStore(defaults: defaults)
        store.save(frequency: 1000)
        store.save(waveform: .square)
        defaults.set("loud", forKey: ToneSettingsStore.volumeKey)
        XCTAssertEqual(store.load(), ToneSettings(frequency: 1000, volume: 0.5, waveform: .square))
    }

    // MARK: - 撮影モード

    func testScreenshotModeDoesNotUseStore() {
        for scene in ScreenshotDemo.Scene.allCases {
            XCTAssertNil(ToneSettingsStore.forLaunch(screenshotScene: scene, defaults: defaults), "\(scene)")
        }
        XCTAssertNotNil(ToneSettingsStore.forLaunch(screenshotScene: nil, defaults: defaults))
    }

    func testScreenshotModeIgnoresStoredValues() {
        let store = ToneSettingsStore(defaults: defaults)
        store.save(frequency: 15000)
        store.save(volume: 1)
        store.save(waveform: .sawtooth)

        for scene in ScreenshotDemo.Scene.allCases {
            let initial = ToneSettings.initial(screenshotScene: scene, store: store)
            XCTAssertEqual(initial.settings, ToneSettings(frequency: scene.frequency, volume: scene.volume, waveform: scene.waveform), "\(scene)")
            // 撮影モードでは保存値が上限を超えていても制限せず、ダイアログも出さない
            XCTAssertFalse(initial.volumeWasCapped, "\(scene)")
        }
    }

    func testCreatingScreenshotContentViewDoesNotWriteDefaults() {
        for scene in ScreenshotDemo.Scene.allCases {
            _ = ContentView(screenshotScene: scene, defaults: defaults)
        }
        XCTAssertNil(defaults.object(forKey: ToneSettingsStore.frequencyKey))
        XCTAssertNil(defaults.object(forKey: ToneSettingsStore.volumeKey))
        XCTAssertNil(defaults.object(forKey: ToneSettingsStore.waveformKey))
    }

    func testInitialSettingsOutsideScreenshotModeComeFromStore() {
        let store = ToneSettingsStore(defaults: defaults)
        store.save(frequency: 100)
        store.save(volume: 0.1)
        store.save(waveform: .triangle)
        XCTAssertEqual(
            ToneSettings.initial(screenshotScene: nil, store: store),
            ToneSettingsRestoration(settings: ToneSettings(frequency: 100, volume: 0.1, waveform: .triangle), volumeWasCapped: false)
        )
    }

    // MARK: - 起動時の音量の上限

    func testVolumeAtOrBelowLimitIsRestoredAsIs() {
        let store = ToneSettingsStore(defaults: defaults)
        for volume in [0.0, 0.1, 0.2] {
            store.save(volume: volume)
            let restoration = store.restore()
            XCTAssertEqual(restoration.settings.volume, volume)
            XCTAssertFalse(restoration.volumeWasCapped, "\(volume)")
        }
    }

    func testVolumeAboveLimitIsLoweredToLimit() {
        let store = ToneSettingsStore(defaults: defaults)
        for volume in [(0.2).nextUp, 0.2001, 0.5, 1.0] {
            store.save(volume: volume)
            let restoration = store.restore()
            XCTAssertEqual(restoration.settings.volume, 0.2, "\(volume)")
            XCTAssertTrue(restoration.volumeWasCapped, "\(volume)")
        }
    }

    func testLoweredVolumeIsSavedAgain() {
        let store = ToneSettingsStore(defaults: defaults)
        store.save(volume: 1)
        _ = store.restore()
        XCTAssertEqual(store.load().volume, 0.2)
        // 下げた値を保存し直したので、次の起動ではダイアログを出さない
        XCTAssertFalse(store.restore().volumeWasCapped)
    }

    func testCappingKeepsFrequencyAndWaveform() {
        let store = ToneSettingsStore(defaults: defaults)
        store.save(frequency: 1000)
        store.save(volume: 0.9)
        store.save(waveform: .square)
        XCTAssertEqual(store.restore().settings, ToneSettings(frequency: 1000, volume: 0.2, waveform: .square))
    }

    func testDefaultVolumeWithoutSavedValueIsNotCapped() {
        // 既定値（50%）は保存値ではないので下げない（初回起動でダイアログを出さない）
        let restoration = ToneSettingsStore(defaults: defaults).restore()
        XCTAssertEqual(restoration.settings, .default)
        XCTAssertFalse(restoration.volumeWasCapped)
        XCTAssertNil(defaults.object(forKey: ToneSettingsStore.volumeKey))
    }

    func testBrokenSavedVolumeFallsBackToDefaultWithoutCapping() {
        defaults.set("loud", forKey: ToneSettingsStore.volumeKey)
        let restoration = ToneSettingsStore(defaults: defaults).restore()
        XCTAssertEqual(restoration.settings.volume, ToneSettings.default.volume)
        XCTAssertFalse(restoration.volumeWasCapped)
    }

    func testInitialSettingsOutsideScreenshotModeAreCapped() {
        let store = ToneSettingsStore(defaults: defaults)
        store.save(volume: 0.8)
        let first = ToneSettings.initial(screenshotScene: nil, store: store)
        XCTAssertEqual(first.settings.volume, 0.2)
        XCTAssertTrue(first.volumeWasCapped)
        XCTAssertFalse(ToneSettings.initial(screenshotScene: nil, store: store).volumeWasCapped, "保存し直したので 2 回目は下げない")
    }

    func testVolumeCapNoticeUsesFormattedKey() {
        XCTAssertEqual(VolumeCapNotice.title.key, "Volume Lowered")
        XCTAssertEqual(VolumeCapNotice.message.key, "To prevent a sudden loud sound, the volume was lowered to %lld%%.")
        XCTAssertEqual(VolumeCapNotice.percent, 20)
    }

    // MARK: - 和音モードのコード

    func testDefaultChordIsC() {
        XCTAssertEqual(ToneSettings.default.chord, Chord(root: .c, quality: .major))
    }

    func testSavedChordIsRestored() {
        let store = ToneSettingsStore(defaults: defaults)
        store.save(chord: Chord(root: .fSharp, quality: .minor))
        XCTAssertEqual(store.load().chord.name, "F#m")
    }

    /// 保存値は変えない約束の形（根音は 0〜11 の数値、種類は文字列）
    func testChordIsStoredAsStableRawValues() {
        ToneSettingsStore(defaults: defaults).save(chord: Chord(root: .a, quality: .minor))
        XCTAssertEqual(ToneSettingsStore.chordRootKey, "toneChordRoot")
        XCTAssertEqual(ToneSettingsStore.chordQualityKey, "toneChordQuality")
        XCTAssertEqual(defaults.integer(forKey: ToneSettingsStore.chordRootKey), 9)
        XCTAssertEqual(defaults.string(forKey: ToneSettingsStore.chordQualityKey), "minor")
    }

    /// 根音と種類のどちらかが壊れていたら、コードは既定（C）に戻し、他の保存値は残す
    func testBrokenChordFallsBackToDefault() {
        let store = ToneSettingsStore(defaults: defaults)
        store.save(frequency: 1234)
        let broken: [(Any?, Any?)] = [
            (12, "major"),
            (-1, "minor"),
            (2.5, "major"),
            ("2", "major"),
            (true, "major"),
            (2, "sus4"),
            (2, 1),
            (nil, "major"),
            (2, nil),
        ]
        for (root, quality) in broken {
            defaults.set(root, forKey: ToneSettingsStore.chordRootKey)
            defaults.set(quality, forKey: ToneSettingsStore.chordQualityKey)
            let loaded = store.load()
            XCTAssertEqual(loaded.chord, ToneSettings.default.chord, "\(String(describing: root)) / \(String(describing: quality))")
            XCTAssertEqual(loaded.frequency, 1234)
        }
    }

    /// 和音のコードを足す前に保存された値（周波数・音量・波形だけ）もそのまま読める
    func testValuesSavedBeforeChordStillLoad() {
        let store = ToneSettingsStore(defaults: defaults)
        store.save(frequency: 880)
        store.save(volume: 0.1)
        store.save(waveform: .triangle)
        XCTAssertEqual(store.load(), ToneSettings(frequency: 880, volume: 0.1, waveform: .triangle, chord: ChordInput.defaultChord))
    }

    // MARK: - 表示モードに合わせた音

    func testPreparedSnapsFrequencyOnlyInNoteMode() {
        let settings = ToneSettings(frequency: 445, volume: 0.5, waveform: .sine, chord: Chord(root: .a, quality: .minor))
        XCTAssertEqual(settings.prepared(for: .note).frequency, 440, accuracy: 1e-9)
        XCTAssertEqual(settings.prepared(for: .hertz).frequency, 445)
        XCTAssertEqual(settings.prepared(for: .chord).frequency, 445)
        XCTAssertEqual(settings.prepared(for: .note).chord, settings.chord)
    }

    func testFrequenciesForEachMode() {
        let aMinor = Chord(root: .a, quality: .minor)
        let settings = ToneSettings(frequency: 1000, volume: 0.5, waveform: .sine, chord: aMinor)
        XCTAssertEqual(settings.frequencies(for: .hertz), ToneFrequencies(1000))
        XCTAssertEqual(settings.frequencies(for: .note), ToneFrequencies(1000))
        XCTAssertEqual(settings.frequencies(for: .chord), ChordInput.frequencies(of: aMinor))
        // 音名モードで起動したときは、半音にそろえた周波数の単音を鳴らす
        XCTAssertEqual(settings.prepared(for: .note).frequencies(for: .note).all, [MusicalNote(.b, octave: 5)!.frequency])
    }

    // MARK: - 既定値に戻す

    func testResetRemovesSavedValues() {
        let store = ToneSettingsStore(defaults: defaults)
        store.save(frequency: 15000)
        store.save(volume: 0.9)
        store.save(waveform: .sawtooth)
        defaults.set(FrequencyMode.chord.rawValue, forKey: FrequencyMode.storageKey)
        store.save(chord: Chord(root: .b, quality: .minor))
        store.reset()
        XCTAssertNil(defaults.object(forKey: ToneSettingsStore.chordRootKey))
        XCTAssertNil(defaults.object(forKey: ToneSettingsStore.chordQualityKey))
        XCTAssertNil(defaults.object(forKey: FrequencyMode.storageKey))
        XCTAssertNil(defaults.object(forKey: ToneSettingsStore.frequencyKey))
        XCTAssertNil(defaults.object(forKey: ToneSettingsStore.volumeKey))
        XCTAssertNil(defaults.object(forKey: ToneSettingsStore.waveformKey))
        XCTAssertEqual(store.load(), .default)
    }

    func testNextLaunchAfterResetIsDefaultWithoutCapping() {
        let store = ToneSettingsStore(defaults: defaults)
        store.save(volume: 0.9)
        store.reset()
        // 既定の 50% は保存された音量ではないので、20% に下げずダイアログも出さない
        XCTAssertEqual(store.restore(), ToneSettingsRestoration(settings: .default, volumeWasCapped: false))
    }

    func testResetLeavesOtherSettingsUntouched() {
        defaults.set(true, forKey: Tutorial.hasSeenKey)
        defaults.set("other", forKey: ThemeColor.storageKey)
        ToneSettingsStore(defaults: defaults).reset()
        XCTAssertTrue(defaults.bool(forKey: Tutorial.hasSeenKey))
        XCTAssertEqual(defaults.string(forKey: ThemeColor.storageKey), "other")
    }

    func testResetNotifiesWithItsDefaults() {
        let posted = expectation(forNotification: ToneSettingsStore.didResetNotification, object: defaults)
        ToneSettingsStore(defaults: defaults).reset()
        wait(for: [posted], timeout: 1)
    }

    func testResetConfirmationUsesFormattedKey() {
        XCTAssertEqual(ToneSettingsResetConfirmation.title.key, "Reset to Defaults?")
        XCTAssertEqual(ToneSettingsResetConfirmation.message.key, "Frequency, volume, and waveform will return to %@ Hz, %lld%%, and %@, and the frequency mode to %@.")
    }

    // MARK: - AudioManager への反映

    func testApplySetsAllValuesWithoutStartingPlayback() {
        let manager = AudioManager(startsEngine: false)
        manager.apply(ToneSettings(frequency: 1000, volume: 0.2, waveform: .square))
        XCTAssertEqual(manager.currentFrequency, 1000)
        XCTAssertEqual(manager.currentVolume, 0.2)
        XCTAssertEqual(manager.currentWaveform, .square)
        XCTAssertFalse(manager.isPlaying)
    }
}
