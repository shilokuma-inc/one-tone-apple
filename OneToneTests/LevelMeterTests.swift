//
//  LevelMeterTests.swift
//  OneToneTests
//

import XCTest
@testable import OneTone

final class LevelMeterTests: XCTestCase {

    private func sine(amplitude: Double, count: Int = 4800) -> [Float] {
        (0..<count).map { Float(amplitude * sin(2 * Double.pi * 440 * Double($0) / 48000)) }
    }

    func testSilenceIsMinusInfinity() {
        XCTAssertEqual(LevelMeter.rmsDecibels([]), -.infinity)
        XCTAssertEqual(LevelMeter.rmsDecibels([0, 0, 0]), -.infinity)
        XCTAssertEqual(LevelMeter.litSegmentCount(decibels: -.infinity), 0)
        XCTAssertEqual(LevelMeter.label(decibels: -.infinity), "-inf dB")
    }

    func testFullScaleSineIsAboutMinus3dB() {
        XCTAssertEqual(LevelMeter.rmsDecibels(sine(amplitude: 1)), -3.01, accuracy: 0.05)
        // 音量 50% なら 6dB 下がる
        XCTAssertEqual(LevelMeter.rmsDecibels(sine(amplitude: 0.5)), -9.03, accuracy: 0.05)
    }

    func testConstantFullScaleIsZeroDecibels() {
        XCTAssertEqual(LevelMeter.rmsDecibels([1, -1, 1, -1]), 0, accuracy: 1e-9)
        XCTAssertEqual(LevelMeter.litSegmentCount(decibels: 0), LevelMeter.segmentCount)
        XCTAssertEqual(LevelMeter.litSegmentCount(decibels: 6), LevelMeter.segmentCount)
    }

    func testLitSegmentsGrowWithLevel() {
        XCTAssertEqual(LevelMeter.litSegmentCount(decibels: LevelMeter.floorDecibels), 0)
        XCTAssertEqual(LevelMeter.litSegmentCount(decibels: -30), LevelMeter.segmentCount / 2)
        var previous = 0
        for decibels in stride(from: -70.0, through: 0, by: 1) {
            let count = LevelMeter.litSegmentCount(decibels: decibels)
            XCTAssertGreaterThanOrEqual(count, previous)
            previous = count
        }
    }

    func testLabelRoundsToWholeDecibels() {
        XCTAssertEqual(LevelMeter.label(decibels: -9.03), "-9 dB")
        XCTAssertEqual(LevelMeter.label(decibels: -0.4), "0 dB")
    }

    func testOnlyTopSegmentsUseWarningColor() {
        // 上端の -6dB より大きい 2 セグメントだけが警告色
        let warning = (0..<LevelMeter.segmentCount).filter { LevelMeter.segmentColor($0) == Theme.accentSecondary }
        XCTAssertEqual(warning, [18, 19])
    }
}
