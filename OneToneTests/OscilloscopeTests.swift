//
//  OscilloscopeTests.swift
//  OneToneTests
//

import XCTest
@testable import OneTone

final class OscilloscopeTests: XCTestCase {

    private func sine(count: Int, period: Double, phase: Double) -> [Float] {
        (0..<count).map { Float(sin(2 * Double.pi * (Double($0) / period + phase))) }
    }

    func testTriggeredWindowStartsAtLatestRisingZeroCrossing() {
        let samples = sine(count: 400, period: 50, phase: 0.3)
        let window = Oscilloscope.triggeredWindow(samples, length: 100)
        XCTAssertEqual(window.count, 100)
        // 後ろに 100 個残るゼロクロスのうち、最も新しいもの（表示が出力から遅れない）
        let start = (1...(samples.count - 100)).last { samples[$0 - 1] < 0 && samples[$0] >= 0 }!
        XCTAssertGreaterThan(start, samples.count - 100 - 50, "1 周期（50 サンプル）以内の新しい位置から切り出す")
        XCTAssertEqual(window, Array(samples[start..<(start + 100)]))
        XCTAssertGreaterThanOrEqual(window[0], 0)
    }

    func testTriggeredWindowKeepsWaveformInPlaceAcrossFrames() {
        // 読み出すたびに位相がずれていても、切り出した波形は同じ位置から始まる
        let first = Oscilloscope.triggeredWindow(sine(count: 400, period: 50, phase: 0.1), length: 100)
        let second = Oscilloscope.triggeredWindow(sine(count: 400, period: 50, phase: 0.6), length: 100)
        for (a, b) in zip(first, second) {
            XCTAssertEqual(a, b, accuracy: 0.15)
        }
    }

    func testTriggeredWindowFallsBackToLatestWhenSilent() {
        var samples = [Float](repeating: 0, count: 300)
        samples[299] = 0.5
        let window = Oscilloscope.triggeredWindow(samples, length: 100)
        XCTAssertEqual(window, Array(samples.suffix(100)))
    }

    func testTriggeredWindowWithTooFewSamplesReturnsThemAsIs() {
        XCTAssertEqual(Oscilloscope.triggeredWindow([0.1, 0.2], length: 100), [0.1, 0.2])
        XCTAssertEqual(Oscilloscope.triggeredWindow([], length: 100), [])
    }

    func testPathIsFlatWhenSilent() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let bounds = Oscilloscope.path(for: [], in: rect).boundingRect
        XCTAssertEqual(bounds.height, 0, accuracy: 1e-9)
        XCTAssertEqual(bounds.midY, 50, accuracy: 1e-9)
        XCTAssertEqual(bounds.width, 200, accuracy: 1e-9)
    }

    func testPathStaysInsideRectWithMargin() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 100)
        let bounds = Oscilloscope.path(for: [1, -1, 2, -2, 0], in: rect).boundingRect
        XCTAssertGreaterThanOrEqual(bounds.minY, 5 - 1e-9)
        XCTAssertLessThanOrEqual(bounds.maxY, 95 + 1e-9)
    }

    func testSearchRangeCoversOnePeriodOfLowestFrequency() {
        // 96kHz の出力でも、20Hz の 1 周期分をゼロクロスの探索範囲に取れる
        let searchRange = Oscilloscope.readLength - Oscilloscope.windowLength
        XCTAssertGreaterThanOrEqual(searchRange, Int(96000 / FrequencyInput.range.lowerBound))
        XCTAssertLessThanOrEqual(Oscilloscope.readLength, AudioManager.outputHistoryCapacity)
    }

    func testTriggeredWindowFindsCrossingAtLowestFrequency() {
        // 48kHz・20Hz（1 周期 2400 サンプル）でも、どの位相から読んでもトリガーできる
        for phase in stride(from: 0.0, to: 1.0, by: 0.1) {
            let samples = sine(count: Oscilloscope.readLength, period: 2400, phase: phase)
            let window = Oscilloscope.triggeredWindow(samples, length: Oscilloscope.windowLength)
            XCTAssertEqual(window.count, Oscilloscope.windowLength)
            XCTAssertEqual(window[0], 0, accuracy: 0.01, "phase \(phase)")
            XCTAssertGreaterThan(window[10], window[0])
        }
    }
}
