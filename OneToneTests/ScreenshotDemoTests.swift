//
//  ScreenshotDemoTests.swift
//  OneToneTests
//

import XCTest
@testable import OneTone

final class ScreenshotDemoTests: XCTestCase {
    func testSceneIsReadFromLaunchArguments() {
        XCTAssertEqual(ScreenshotDemo.scene(from: ["-screenshot-demo", "-screenshot-scene", "square"]), .square)
        XCTAssertEqual(ScreenshotDemo.scene(from: ["-screenshot-scene", "sawtooth", "-screenshot-demo"]), .sawtooth)
    }

    func testUnknownOrMissingSceneFallsBackToFirstScene() {
        XCTAssertEqual(ScreenshotDemo.scene(from: ["-screenshot-demo"]), .sine)
        XCTAssertEqual(ScreenshotDemo.scene(from: ["-screenshot-demo", "-screenshot-scene"]), .sine)
        XCTAssertEqual(ScreenshotDemo.scene(from: ["-screenshot-demo", "-screenshot-scene", "noise"]), .sine)
    }

    func testArgumentValueIsReadOnlyWhenPresent() {
        XCTAssertEqual(ScreenshotDemo.argument("-screenshot-output", in: ["-screenshot-output", "/tmp/a.png"]), "/tmp/a.png")
        XCTAssertNil(ScreenshotDemo.argument("-screenshot-output", in: ["-screenshot-output"]))
        XCTAssertNil(ScreenshotDemo.argument("-screenshot-output", in: ["-screenshot-demo"]))
    }

    func testAudioManagerForScreenshotPresentsSceneWithoutEngine() {
        let manager = AudioManager.forScreenshot(.sawtooth)
        XCTAssertTrue(manager.isPlaying)
        XCTAssertFalse(manager.audioEngine.isRunning)
        XCTAssertEqual(manager.currentFrequency, 100)
        XCTAssertEqual(manager.currentWaveform, .sawtooth)
        XCTAssertFalse(AudioManager.forScreenshot(nil).isPlaying)
    }

    func testEachAppStoreSceneHasDistinctWaveform() {
        // App Store の Hz モードの 3 枚で別々の波形を見せる前提なので、重複したら設定ミス
        let waveforms = ScreenshotDemo.Scene.appStoreScenes.filter { $0.frequencyMode == .hertz }.map(\.waveform)
        XCTAssertEqual(waveforms.count, 3)
        XCTAssertEqual(Set(waveforms).count, waveforms.count)
        for scene in ScreenshotDemo.Scene.allCases {
            XCTAssertTrue(FrequencyInput.range.contains(scene.frequency), "\(scene) の周波数が範囲外")
        }
    }

    func testAppStoreScenesKeepTheirLaunchNames() {
        // AppStore/screenshots.json の scene と一致させている名前なので、変わったら撮影が既定の画面に化ける
        XCTAssertEqual(ScreenshotDemo.Scene.appStoreScenes.map(\.rawValue), ["sine", "square", "sawtooth", "note", "chord"])
    }

    /// App Store 用で Hz・音名・和音の 3 つのモードを見せる
    func testAppStoreScenesShowEveryFrequencyMode() {
        XCTAssertEqual(Set(ScreenshotDemo.Scene.appStoreScenes.map(\.frequencyMode)), Set(FrequencyMode.allCases))
        XCTAssertEqual(ScreenshotDemo.Scene.note.frequencyMode, .note)
        XCTAssertEqual(ScreenshotDemo.Scene.chord.frequencyMode, .chord)
        // チュートリアルの画像は、音名・和音のページ以外は Hz モードのまま撮る
        for scene in ScreenshotDemo.Scene.allCases where !ScreenshotDemo.Scene.appStoreScenes.contains(scene) {
            let expected: FrequencyMode = scene == .tutorialNote ? .note : scene == .tutorialChord ? .chord : .hertz
            XCTAssertEqual(scene.frequencyMode, expected, "\(scene)")
        }
    }

    /// 音名モードのシーンはちょうどの音（C5）で、プリセットが選択中に見える
    func testNoteSceneIsExactPresetNote() {
        let note = NoteInput.note(for: ScreenshotDemo.Scene.note.frequency)
        XCTAssertEqual(note.name, "C5")
        XCTAssertEqual(ScreenshotDemo.Scene.note.frequency, NoteInput.snapped(ScreenshotDemo.Scene.note.frequency))
        XCTAssertTrue(NoteInput.presets.contains(note))
    }

    /// 和音モードのシーンは Am で、パッドが選択中に見える
    func testChordSceneShowsPadChord() {
        XCTAssertEqual(ScreenshotDemo.Scene.chord.chord.name, "Am")
        XCTAssertTrue(ChordInput.pads.contains(ScreenshotDemo.Scene.chord.chord))
        XCTAssertEqual(ScreenshotDemo.Scene.tutorialChord.chord.name, "G")
        XCTAssertTrue(ChordInput.pads.contains(ScreenshotDemo.Scene.tutorialChord.chord))
        for scene in ScreenshotDemo.Scene.allCases where scene != .chord && scene != .tutorialChord {
            XCTAssertEqual(scene.chord, ChordInput.defaultChord, "\(scene)")
        }
    }

    func testAudioManagerForChordScenePresentsChord() {
        let manager = AudioManager.forScreenshot(.chord)
        XCTAssertTrue(manager.isPlaying)
        XCTAssertFalse(manager.audioEngine.isRunning)
        XCTAssertEqual(manager.currentFrequencies, ChordInput.frequencies(of: Chord(root: .a, quality: .minor)))
        XCTAssertEqual(manager.currentWaveform, .sine)
    }

    func testTutorialScenesCoverEveryTutorialPage() {
        // チュートリアルのアセット名（Tutorial-<ページ名>）と撮影の場面名（tutorial-<ページ名>）を対応させている
        let tutorialScenes = ScreenshotDemo.Scene.allCases.filter { !ScreenshotDemo.Scene.appStoreScenes.contains($0) }
        XCTAssertEqual(tutorialScenes.map(\.rawValue), ["tutorial-welcome", "tutorial-playback", "tutorial-frequency", "tutorial-volume", "tutorial-waveform", "tutorial-note", "tutorial-chord"])
        XCTAssertEqual(tutorialScenes.map(\.rawValue), TutorialPage.ID.allCases.map { "tutorial-\($0.rawValue)" })
        XCTAssertEqual(ScreenshotDemo.scene(from: ["-screenshot-scene", "tutorial-frequency"]), .tutorialFrequency)
    }

    func testTutorialScenesShowTheirPage() {
        XCTAssertEqual(ScreenshotDemo.Scene.tutorialFrequency.scrollTarget, .frequency)
        XCTAssertTrue(FrequencyInput.presets.contains(ScreenshotDemo.Scene.tutorialFrequency.frequency), "プリセットが選択中に見えない")
        XCTAssertLessThan(ScreenshotDemo.Scene.tutorialVolume.volume, 0.5)
        XCTAssertEqual(ScreenshotDemo.Scene.tutorialWaveform.waveform, .triangle)
        // Hz モードの 3 枚は先頭のまま（既存の画像の見た目を変えない）
        for scene in ScreenshotDemo.Scene.appStoreScenes where scene.frequencyMode == .hertz {
            XCTAssertNil(scene.scrollTarget, "App Store 用の \(scene) の見た目が変わる")
        }
        // 音名・和音モードの画面は、縦積み（iPhone）で FREQUENCY パネルが写る位置まで送る
        XCTAssertEqual(ScreenshotDemo.Scene.note.scrollTarget, .frequency)
        XCTAssertEqual(ScreenshotDemo.Scene.chord.scrollTarget, .frequency)
        XCTAssertEqual(ScreenshotDemo.Scene.tutorialNote.scrollTarget, .frequency)
        XCTAssertEqual(ScreenshotDemo.Scene.tutorialChord.scrollTarget, .frequency)
        // チュートリアルの音名のページはちょうどのプリセットの音（A4）で、パッドが選択中に見える
        let tutorialNote = NoteInput.note(for: ScreenshotDemo.Scene.tutorialNote.frequency)
        XCTAssertEqual(tutorialNote.name, "A4")
        XCTAssertEqual(ScreenshotDemo.Scene.tutorialNote.frequency, tutorialNote.frequency, accuracy: 1e-9)
        XCTAssertTrue(NoteInput.presets.contains(tutorialNote))
    }

    func testPresentAsPlayingFillsOutputHistoryWithoutAudioEngine() {
        let manager = AudioManager(startsEngine: false)
        manager.presentAsPlaying(frequency: 440, volume: 0.8, waveform: .square)

        XCTAssertTrue(manager.isPlaying)
        XCTAssertEqual(manager.currentFrequency, 440)
        XCTAssertEqual(manager.currentWaveform, .square)
        // 末尾（最新）はフェードインが終わっていて、矩形波の振幅（= 音量）になっている
        let latest = manager.latestOutputSamples(Oscilloscope.windowLength)
        XCTAssertEqual(latest.count, Oscilloscope.windowLength)
        XCTAssertEqual(Double(latest.map { abs($0) }.max() ?? 0), 0.8, accuracy: 0.01)
    }
}
