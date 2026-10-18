//
//  NoteInputTests.swift
//  OneToneTests
//

import XCTest
@testable import OneTone

final class NoteInputTests: XCTestCase {
    // MARK: - 半音へのスナップ

    func testSnappedReturnsExactSemitoneFrequency() {
        XCTAssertEqual(NoteInput.snapped(445), 440, accuracy: 1e-9)
        XCTAssertEqual(NoteInput.snapped(1000), MusicalNote(.b, octave: 5)!.frequency, accuracy: 1e-9)
        XCTAssertEqual(NoteInput.snapped(100), MusicalNote(.g, octave: 2)!.frequency, accuracy: 1e-9)
    }

    func testSnappedIsIdempotent() {
        for note in MusicalNote.all {
            XCTAssertEqual(NoteInput.snapped(note.frequency), note.frequency, note.name)
            XCTAssertEqual(NoteInput.snapped(NoteInput.snapped(note.frequency * 1.01)), NoteInput.snapped(note.frequency * 1.01), note.name)
        }
    }

    /// Hz モードの範囲の端（20Hz / 20kHz）から切り替えても、範囲内の端の音にする
    func testSnappedKeepsFrequencyRangeEdgesInRange() {
        XCTAssertEqual(NoteInput.note(for: 20), MusicalNote.lowest)
        XCTAssertEqual(NoteInput.note(for: 20000), MusicalNote.highest)
        XCTAssertTrue(FrequencyInput.range.contains(NoteInput.snapped(20)))
        XCTAssertTrue(FrequencyInput.range.contains(NoteInput.snapped(20000)))
    }

    func testInvalidFrequencyFallsBackToA4() {
        XCTAssertEqual(NoteInput.note(for: 0).name, "A4")
        XCTAssertEqual(NoteInput.note(for: .nan).name, "A4")
    }

    // MARK: - 音名とオクターブの選択

    func testNoteFromPitchClassAndOctave() {
        XCTAssertEqual(NoteInput.note(.fSharp, octave: 3).name, "F#3")
        XCTAssertEqual(NoteInput.note(.a, octave: 4).frequency, 440, accuracy: 1e-9)
    }

    /// 範囲外の組み合わせは近い方の端の音にする
    func testOutOfRangeCombinationsClampToEdges() {
        XCTAssertEqual(NoteInput.note(.c, octave: 0), MusicalNote.lowest)
        XCTAssertEqual(NoteInput.note(.dSharp, octave: 0), MusicalNote.lowest)
        XCTAssertEqual(NoteInput.note(.e, octave: 10), MusicalNote.highest)
        XCTAssertEqual(NoteInput.note(.b, octave: 10), MusicalNote.highest)
    }

    func testOctavesCoverRange() {
        XCTAssertEqual(NoteInput.octaves, 0...10)
    }

    // MARK: - プリセット

    func testPresets() {
        XCTAssertEqual(NoteInput.presets.map(\.name), ["A3", "C4", "A4", "C5"])
    }

    // MARK: - 半音ずつの調整

    func testClampedTransposedStopsAtEdges() {
        XCTAssertEqual(MusicalNote.highest.clampedTransposed(by: 1), MusicalNote.highest)
        XCTAssertEqual(MusicalNote.lowest.clampedTransposed(by: -1), MusicalNote.lowest)
        XCTAssertEqual(NoteInput.note(.a, octave: 4).clampedTransposed(by: 1).name, "A#4")
        XCTAssertEqual(NoteInput.note(.c, octave: 4).clampedTransposed(by: -1).name, "B3")
    }

    // MARK: - ノブの刻み

    func testContinuousScaleKeepsFrequency() {
        XCTAssertEqual(KnobScale.continuous.snapped(445.3), 445.3)
    }

    func testSemitoneScaleSnaps() {
        XCTAssertEqual(KnobScale.semitone.snapped(445.3), 440, accuracy: 1e-9)
    }

    func testSemitoneAccessibilityStepsOneSemitone() {
        let up = KnobScale.semitone.accessibilityAdjusted(440, up: true)
        let down = KnobScale.semitone.accessibilityAdjusted(440, up: false)
        XCTAssertEqual(NoteInput.note(for: up).name, "A#4")
        XCTAssertEqual(NoteInput.note(for: down).name, "G#4")
        XCTAssertEqual(up, NoteInput.snapped(up))
    }

    func testContinuousAccessibilityStepMatchesKnobMapping() {
        XCTAssertEqual(KnobScale.continuous.accessibilityAdjusted(440, up: true), KnobMapping.adjusted(440, by: KnobMapping.accessibilityStep), accuracy: 1e-9)
    }

    /// 半音（約 2pt）に満たないドラッグを重ねても、スナップ前の位置から動かせば音が変わる
    func testSmallDragsAccumulateBeforeSnapping() {
        var unsnapped = 440.0
        var snapped = 440.0
        for _ in 0..<10 {
            unsnapped = KnobMapping.adjusted(unsnapped, by: KnobMapping.positionDelta(dx: 0, dy: -0.5, isFine: false))
            snapped = KnobScale.semitone.snapped(unsnapped)
        }
        XCTAssertGreaterThan(snapped, 440)
    }

    // MARK: - モードの読み出し

    func testStoredModeFallsBackToDefault() throws {
        let suiteName = "NoteInputTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        XCTAssertEqual(FrequencyMode.stored(in: defaults), .hertz)
        defaults.set("note", forKey: FrequencyMode.storageKey)
        XCTAssertEqual(FrequencyMode.stored(in: defaults), .note)
        defaults.set("unknown", forKey: FrequencyMode.storageKey)
        XCTAssertEqual(FrequencyMode.stored(in: defaults), .hertz)
    }

    /// 撮影モードでは保存値ではなくシーンのモードで撮る
    func testScreenshotDemoUsesSceneMode() {
        XCTAssertEqual(FrequencyMode.displayed(stored: .note, screenshotScene: .sine), .hertz)
        XCTAssertEqual(FrequencyMode.displayed(stored: .hertz, screenshotScene: .chord), .chord)
        XCTAssertEqual(FrequencyMode.displayed(stored: .chord, screenshotScene: .note), .note)
        XCTAssertEqual(FrequencyMode.displayed(stored: .note, screenshotScene: nil), .note)
    }
}
