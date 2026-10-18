//
//  ChordInputTests.swift
//  OneToneTests
//

import XCTest
@testable import OneTone

final class ChordInputTests: XCTestCase {
    // MARK: - パッド

    func testPads() {
        XCTAssertEqual(ChordInput.pads.map(\.name), ["C", "G", "Am", "F", "D", "Em", "E", "Dm"])
    }

    func testPadsAreUnique() {
        XCTAssertEqual(Set(ChordInput.pads).count, ChordInput.pads.count)
    }

    /// 4 個ずつの段で余りが出ない
    func testPadsFillRows() {
        XCTAssertEqual(ChordInput.pads.count % ChordInput.padsPerRow, 0)
    }

    func testDefaultChordIsCMajorAndOnPads() {
        XCTAssertEqual(ChordInput.defaultChord.name, "C")
        XCTAssertTrue(ChordInput.pads.contains(ChordInput.defaultChord))
    }

    // MARK: - 鳴らす周波数

    func testFrequenciesOfCMajor() {
        let frequencies = ChordInput.frequencies(of: Chord(root: .c, quality: .major))
        XCTAssertEqual(frequencies.count, 3)
        XCTAssertEqual(frequencies[0], 261.6256, accuracy: 1e-4)
        XCTAssertEqual(frequencies[1], 329.6276, accuracy: 1e-4)
        XCTAssertEqual(frequencies[2], 391.9954, accuracy: 1e-4)
    }

    func testFrequenciesMatchChordForAllChords() {
        for chord in Chord.all {
            XCTAssertEqual(ChordInput.frequencies(of: chord).all, chord.frequencies, chord.name)
        }
    }

    /// どの種類も、同時に鳴らせる数（3）以内の構成音で、根音から高い方へ並ぶ
    func testEveryQualityFitsVoices() {
        for quality in ChordQuality.allCases {
            XCTAssertLessThanOrEqual(quality.intervals.count, ToneFrequencies.maxCount, "\(quality)")
            XCTAssertEqual(quality.intervals.first, 0, "\(quality)")
            XCTAssertEqual(quality.intervals, quality.intervals.sorted(), "\(quality)")
            XCTAssertEqual(Set(quality.intervals).count, quality.intervals.count, "\(quality)")
        }
    }

    // MARK: - 表記

    func testNotesLabel() {
        XCTAssertEqual(ChordInput.notesLabel(of: Chord(root: .c, quality: .major)), "C4 · E4 · G4")
        XCTAssertEqual(ChordInput.notesLabel(of: Chord(root: .a, quality: .minor)), "A4 · C5 · E5")
    }

    // MARK: - AudioManager で鳴らす

    func testPlayChordStartsPlaybackWithAllVoices() {
        let manager = AudioManager(startsEngine: false)
        let frequencies = ChordInput.frequencies(of: Chord(root: .a, quality: .minor))
        manager.playTone(frequencies: frequencies)
        XCTAssertTrue(manager.isPlaying)
        XCTAssertEqual(manager.currentFrequencies, frequencies)
        XCTAssertEqual(manager.currentFrequency, 440, accuracy: 1e-9)
    }
}
