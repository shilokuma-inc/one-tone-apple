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

    func testTopSegmentIsThemeAccent() {
        for theme in ThemeColor.allCases {
            XCTAssertEqual(LevelMeter.segmentHex(LevelMeter.segmentCount - 1, accentHex: theme.accentHex), theme.accentHex, "\(theme)")
            XCTAssertEqual(LevelMeter.segmentColor(LevelMeter.segmentCount - 1, theme: theme), theme.accent, "\(theme)")
        }
    }

    func testSegmentsGetDeeperToTheRight() {
        // 左ほど淡く、右ほど濃い（Q1 の A）。消灯の色との差（相対輝度）が右へ行くほど増える
        for theme in ThemeColor.allCases {
            let luminances = (0..<LevelMeter.segmentCount).map {
                ColorContrast.relativeLuminance(LevelMeter.segmentHex($0, accentHex: theme.accentHex))
            }
            for index in 1..<luminances.count {
                XCTAssertGreaterThan(luminances[index], luminances[index - 1], "\(theme) \(index)")
            }
            XCTAssertGreaterThan(luminances[0], ColorContrast.relativeLuminance(Theme.surfaceRaisedHex), "\(theme)")
        }
    }

    func testFaintestSegmentStandsOutFromUnlit() {
        // いちばん淡いセグメントでも消灯と見分けられる。基準（minimumLitContrast）は緩めない
        for theme in ThemeColor.allCases {
            let faintest = LevelMeter.segmentHex(0, accentHex: theme.accentHex)
            XCTAssertGreaterThanOrEqual(ColorContrast.ratio(faintest, Theme.surfaceRaisedHex), LevelMeter.minimumLitContrast, "\(theme)")
        }
        XCTAssertGreaterThanOrEqual(LevelMeter.minimumLitContrast, 1.5)
    }

    func testColorDependsOnlyOnPosition() {
        // 濃さは位置で決まる。左端は faintestAccentRatio、右端は 1 で、範囲の外の位置は端に寄せる
        XCTAssertEqual(LevelMeter.accentRatio(0), LevelMeter.faintestAccentRatio, accuracy: 1e-9)
        XCTAssertEqual(LevelMeter.accentRatio(LevelMeter.segmentCount - 1), 1, accuracy: 1e-9)
        XCTAssertEqual(LevelMeter.accentRatio(-1), LevelMeter.accentRatio(0), accuracy: 1e-9)
        XCTAssertEqual(LevelMeter.accentRatio(LevelMeter.segmentCount), 1, accuracy: 1e-9)
    }
}
