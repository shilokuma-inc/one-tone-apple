//
//  ChordTests.swift
//  OneToneTests
//

import XCTest
@testable import OneTone

final class ChordTests: XCTestCase {
    // MARK: - 種類

    func testQualitiesAreMajorAndMinorOnly() {
        XCTAssertEqual(ChordQuality.allCases, [.major, .minor])
    }

    func testIntervals() {
        XCTAssertEqual(ChordQuality.major.intervals, [0, 4, 7])
        XCTAssertEqual(ChordQuality.minor.intervals, [0, 3, 7])
    }

    /// rawValue は保存に使うので変えない
    func testQualityRawValuesAreStable() {
        XCTAssertEqual(ChordQuality.major.rawValue, "major")
        XCTAssertEqual(ChordQuality.minor.rawValue, "minor")
    }

    // MARK: - コード名

    func testNames() {
        XCTAssertEqual(Chord(root: .c, quality: .major).name, "C")
        XCTAssertEqual(Chord(root: .a, quality: .minor).name, "Am")
        XCTAssertEqual(Chord(root: .fSharp, quality: .minor).name, "F#m")
        XCTAssertEqual(Chord(root: .aSharp, quality: .major).name, "A#")
    }

    func testAllHas24UniqueChordsInRootOrder() {
        XCTAssertEqual(Chord.all.count, 24)
        XCTAssertEqual(Set(Chord.all.map(\.name)).count, 24)
        XCTAssertEqual(Chord.all.prefix(4).map(\.name), ["C", "Cm", "C#", "C#m"])
        XCTAssertEqual(Chord.all.suffix(2).map(\.name), ["B", "Bm"])
    }

    // MARK: - 構成音

    func testCMajorIsC4E4G4() {
        let chord = Chord(root: .c, quality: .major)
        XCTAssertEqual(chord.notes.map(\.name), ["C4", "E4", "G4"])
        let expected = [261.6256, 329.6276, 391.9954]
        XCTAssertEqual(chord.frequencies.count, 3)
        for (frequency, value) in zip(chord.frequencies, expected) {
            XCTAssertEqual(frequency, value, accuracy: 1e-4)
        }
    }

    func testAMinorIsA4C5E5() {
        let chord = Chord(root: .a, quality: .minor)
        XCTAssertEqual(chord.notes.map(\.name), ["A4", "C5", "E5"])
        XCTAssertEqual(chord.frequencies[0], 440, accuracy: 1e-9)
    }

    func testBMajorCrossesIntoNextOctave() {
        XCTAssertEqual(Chord(root: .b, quality: .major).notes.map(\.name), ["B4", "D#5", "F#5"])
    }

    func testRootIsInRootOctave() {
        for chord in Chord.all {
            XCTAssertEqual(chord.notes.first?.pitchClass, chord.root, chord.name)
            XCTAssertEqual(chord.notes.first?.octave, Chord.rootOctave, chord.name)
        }
    }

    func testEveryChordHasThreeAscendingNotesWithItsIntervals() {
        for chord in Chord.all {
            let numbers = chord.notes.map(\.number)
            XCTAssertEqual(numbers.count, 3, chord.name)
            XCTAssertEqual(numbers.map { $0 - numbers[0] }, chord.quality.intervals, chord.name)
        }
    }

    /// 同時に鳴らせる最大の音の数（3）を超えない
    func testNoChordHasMoreThanThreeNotes() {
        for chord in Chord.all {
            XCTAssertLessThanOrEqual(chord.notes.count, 3, chord.name)
        }
    }

    func testAllFrequenciesAreInsideFrequencyRange() {
        for chord in Chord.all {
            for frequency in chord.frequencies {
                XCTAssertTrue(FrequencyInput.range.contains(frequency), "\(chord.name) の \(frequency)Hz が範囲外")
            }
        }
    }
}
