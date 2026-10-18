//
//  FrequencyKnobTests.swift
//  OneToneTests
//

import XCTest
@testable import OneTone

final class FrequencyKnobTests: XCTestCase {

    func testPositionCoversRangeLogarithmically() {
        XCTAssertEqual(KnobMapping.position(for: 20), 0, accuracy: 1e-9)
        XCTAssertEqual(KnobMapping.position(for: 20000), 1, accuracy: 1e-9)
        // 20Hz〜20kHz は 3 桁なので、1 桁ごとに 1/3 ずつ進む
        XCTAssertEqual(KnobMapping.position(for: 200), 1.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(KnobMapping.position(for: 2000), 2.0 / 3, accuracy: 1e-9)
    }

    func testPositionAndFrequencyRoundTrip() {
        for frequency in [20.0, 100, 440, 1000, 10000, 20000] {
            let position = KnobMapping.position(for: frequency)
            XCTAssertEqual(KnobMapping.frequency(for: position), frequency, accuracy: frequency * 1e-9)
        }
    }

    func testOutOfRangeIsClamped() {
        XCTAssertEqual(KnobMapping.position(for: 1), 0, accuracy: 1e-9)
        XCTAssertEqual(KnobMapping.position(for: 100000), 1, accuracy: 1e-9)
        XCTAssertEqual(KnobMapping.frequency(for: -0.5), 20, accuracy: 1e-9)
        XCTAssertEqual(KnobMapping.frequency(for: 1.5), 20000, accuracy: 1e-6)
    }

    func testAdjustedStopsAtRangeEnds() {
        XCTAssertEqual(KnobMapping.adjusted(20000, by: 0.1), 20000, accuracy: 1e-6)
        XCTAssertEqual(KnobMapping.adjusted(20, by: -0.1), 20, accuracy: 1e-9)
        XCTAssertGreaterThan(KnobMapping.adjusted(440, by: KnobMapping.accessibilityStep), 440)
        XCTAssertLessThan(KnobMapping.adjusted(440, by: -KnobMapping.accessibilityStep), 440)
    }

    func testAngleSpansSweep() {
        XCTAssertEqual(KnobMapping.angle(for: 0), -135, accuracy: 1e-9)
        XCTAssertEqual(KnobMapping.angle(for: 0.5), 0, accuracy: 1e-9)
        XCTAssertEqual(KnobMapping.angle(for: 1), 135, accuracy: 1e-9)
    }

    func testDragUpOrRightIncreases() {
        XCTAssertGreaterThan(KnobMapping.positionDelta(dx: 0, dy: -10, isFine: false), 0)
        XCTAssertGreaterThan(KnobMapping.positionDelta(dx: 10, dy: 0, isFine: false), 0)
        XCTAssertLessThan(KnobMapping.positionDelta(dx: 0, dy: 10, isFine: false), 0)
        // 全域を動かすのに必要な量だけ上へドラッグすると、ちょうど全域動く
        XCTAssertEqual(KnobMapping.positionDelta(dx: 0, dy: -KnobMapping.pointsPerFullRange, isFine: false), 1, accuracy: 1e-9)
    }

    func testFineAdjustmentScalesDown() {
        let normal = KnobMapping.positionDelta(dx: 0, dy: -24, isFine: false)
        let fine = KnobMapping.positionDelta(dx: 0, dy: -24, isFine: true)
        XCTAssertEqual(fine, normal * KnobMapping.fineAdjustmentRatio, accuracy: 1e-12)
    }
}
