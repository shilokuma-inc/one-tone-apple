//
//  MusicalNoteTests.swift
//  OneToneTests
//

import XCTest
@testable import OneTone

final class MusicalNoteTests: XCTestCase {
    // MARK: - 音名 → 周波数

    func testA4Is440Hz() throws {
        let a4 = try XCTUnwrap(MusicalNote(.a, octave: 4))
        XCTAssertEqual(a4.number, 69)
        XCTAssertEqual(a4.frequency, 440, accuracy: 1e-9)
        XCTAssertEqual(a4.name, "A4")
    }

    func testMiddleCIsC4() throws {
        let c4 = try XCTUnwrap(MusicalNote(number: 60))
        XCTAssertEqual(c4.pitchClass, .c)
        XCTAssertEqual(c4.octave, 4)
        XCTAssertEqual(c4.name, "C4")
        XCTAssertEqual(c4.frequency, 261.6256, accuracy: 1e-4)
    }

    func testKnownFrequencies() throws {
        let expected: [(PitchClass, Int, Double)] = [
            (.a, 3, 220),
            (.a, 5, 880),
            (.e, 4, 329.6276),
            (.cSharp, 5, 554.3653),
            (.fSharp, 2, 92.4986),
            (.b, 0, 30.8677),
        ]
        for (pitchClass, octave, frequency) in expected {
            let note = try XCTUnwrap(MusicalNote(pitchClass, octave: octave))
            XCTAssertEqual(note.frequency, frequency, accuracy: 1e-4, note.name)
        }
    }

    func testOctaveDoublesFrequency() throws {
        for note in MusicalNote.all {
            guard let upper = note.transposed(by: 12) else { continue }
            XCTAssertEqual(upper.frequency / note.frequency, 2, accuracy: 1e-9, note.name)
        }
    }

    /// オクターブは C で切り替わる（B3 の次は C4）
    func testOctaveChangesAtC() throws {
        let b3 = try XCTUnwrap(MusicalNote(.b, octave: 3))
        let c4 = try XCTUnwrap(b3.transposed(by: 1))
        XCTAssertEqual(b3.name, "B3")
        XCTAssertEqual(c4.name, "C4")
    }

    func testNamesUseSharps() {
        XCTAssertEqual(PitchClass.allCases.map(\.name), ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"])
        XCTAssertEqual(MusicalNote(.fSharp, octave: 5)?.name, "F#5")
        XCTAssertEqual(MusicalNote(.cSharp, octave: 10)?.name, "C#10")
    }

    // MARK: - 扱える範囲（20Hz〜20kHz）

    func testRangeIsE0ToDSharp10() {
        XCTAssertEqual(MusicalNote.lowest.name, "E0")
        XCTAssertEqual(MusicalNote.highest.name, "D#10")
        XCTAssertEqual(MusicalNote.all.count, 120)
        XCTAssertEqual(MusicalNote.all.first, MusicalNote.lowest)
        XCTAssertEqual(MusicalNote.all.last, MusicalNote.highest)
    }

    func testAllNotesAreInsideFrequencyRange() {
        for note in MusicalNote.all {
            XCTAssertTrue(FrequencyInput.range.contains(note.frequency), "\(note.name) が範囲外")
        }
    }

    func testNeighborsOfRangeAreOutsideFrequencyRange() {
        // 1 つ外の音は範囲に入らないので、扱える範囲はこれより広げられない
        let belowLowest = MusicalNote.referenceFrequency * pow(2, Double(MusicalNote.lowest.number - 1 - MusicalNote.referenceNumber) / 12)
        let aboveHighest = MusicalNote.referenceFrequency * pow(2, Double(MusicalNote.highest.number + 1 - MusicalNote.referenceNumber) / 12)
        XCTAssertLessThan(belowLowest, FrequencyInput.range.lowerBound)
        XCTAssertGreaterThan(aboveHighest, FrequencyInput.range.upperBound)
    }

    func testOutOfRangeNotesAreNil() {
        XCTAssertNil(MusicalNote(.dSharp, octave: 0))
        XCTAssertNil(MusicalNote(.e, octave: 10))
        XCTAssertNil(MusicalNote(number: 0))
        XCTAssertNil(MusicalNote(number: -1))
        XCTAssertNil(MusicalNote(number: 136))
        XCTAssertNil(MusicalNote.highest.transposed(by: 1))
        XCTAssertNil(MusicalNote.lowest.transposed(by: -1))
    }

    // MARK: - 周波数 → 最寄りの音名

    func testExactFrequenciesMapToTheirNotes() {
        for note in MusicalNote.all {
            XCTAssertEqual(MusicalNote(nearestTo: note.frequency), note, note.name)
        }
    }

    func testNearestRoundsToClosestSemitone() {
        XCTAssertEqual(MusicalNote(nearestTo: 445)?.name, "A4")
        XCTAssertEqual(MusicalNote(nearestTo: 1000)?.name, "B5")
        XCTAssertEqual(MusicalNote(nearestTo: 100)?.name, "G2")
        XCTAssertEqual(MusicalNote(nearestTo: 10000)?.name, "D#9")
        // A4 と A#4 のちょうど中間（50 セント）より少しでも下なら A4、上なら A#4
        let midpoint = 440 * pow(2, 0.5 / 12)
        XCTAssertEqual(MusicalNote(nearestTo: midpoint * 0.9999)?.name, "A4")
        XCTAssertEqual(MusicalNote(nearestTo: midpoint * 1.0001)?.name, "A#4")
    }

    /// 範囲の端の周波数のうち 20Hz は、四捨五入すると範囲外の D#0 になるので端の音（E0）にする。20kHz は D#10 で範囲内
    func testFrequencyRangeEdgesClampToRangeEdges() {
        XCTAssertEqual(MusicalNote(nearestTo: FrequencyInput.range.lowerBound), MusicalNote.lowest)
        XCTAssertEqual(MusicalNote(nearestTo: FrequencyInput.range.upperBound), MusicalNote.highest)
    }

    func testFrequenciesOutsideRangeClampToRangeEdges() {
        XCTAssertEqual(MusicalNote(nearestTo: 1), MusicalNote.lowest)
        XCTAssertEqual(MusicalNote(nearestTo: 0.001), MusicalNote.lowest)
        XCTAssertEqual(MusicalNote(nearestTo: 100_000), MusicalNote.highest)
        XCTAssertEqual(MusicalNote(nearestTo: .greatestFiniteMagnitude), MusicalNote.highest)
    }

    func testInvalidFrequenciesAreNil() {
        XCTAssertNil(MusicalNote(nearestTo: 0))
        XCTAssertNil(MusicalNote(nearestTo: -440))
        XCTAssertNil(MusicalNote(nearestTo: .infinity))
        XCTAssertNil(MusicalNote(nearestTo: .nan))
    }

    func testExactNumber() {
        XCTAssertEqual(MusicalNote.exactNumber(for: 440), 69, accuracy: 1e-12)
        XCTAssertEqual(MusicalNote.exactNumber(for: 880), 81, accuracy: 1e-12)
        XCTAssertEqual(MusicalNote.exactNumber(for: 440 * pow(2, 0.25 / 12)), 69.25, accuracy: 1e-9)
    }

    // MARK: - 並び

    func testComparableByPitch() throws {
        let c4 = try XCTUnwrap(MusicalNote(.c, octave: 4))
        let b3 = try XCTUnwrap(MusicalNote(.b, octave: 3))
        XCTAssertLessThan(b3, c4)
        XCTAssertEqual(MusicalNote.all, MusicalNote.all.sorted())
    }
}
