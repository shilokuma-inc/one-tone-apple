//
//  NeonGlowTests.swift
//  OneToneTests
//

import XCTest
@testable import OneTone

final class NeonGlowTests: XCTestCase {

    func testGlowIsOffWhileStopped() {
        for time in stride(from: 0.0, to: 5.0, by: 0.1) {
            XCTAssertEqual(NeonGlow.intensity(at: time, isActive: false, reduceMotion: false), 0)
            XCTAssertEqual(NeonGlow.intensity(at: time, isActive: false, reduceMotion: true), 0)
        }
    }

    func testGlowIsSteadyWithReduceMotion() {
        for time in stride(from: 0.0, to: 5.0, by: 0.1) {
            XCTAssertEqual(NeonGlow.intensity(at: time, isActive: true, reduceMotion: true), 1)
        }
    }

    func testGlowPulseStaysBrightAndSlow() {
        let samples = stride(from: 0.0, to: Theme.glowPulsePeriod, by: 1.0 / 60).map {
            NeonGlow.intensity(at: $0, isActive: true, reduceMotion: false)
        }
        // 消えたり大きく明滅したりせず、ゆらぎの幅に収まる
        XCTAssertGreaterThanOrEqual(samples.min() ?? 0, 1 - Theme.glowPulseDepth - 1e-9)
        XCTAssertLessThanOrEqual(samples.max() ?? 2, 1 + 1e-9)
        // 1 フレーム（60fps）あたりの変化が小さい（急な明滅にならない）
        let maxStep = zip(samples, samples.dropFirst()).map { abs($1 - $0) }.max() ?? 0
        XCTAssertLessThan(maxStep, 0.01)
        // 周期は 1 秒より遅い
        XCTAssertGreaterThan(Theme.glowPulsePeriod, 1)
    }

    func testTitleHueSwingsAroundThemeColorOncePerPeriod() {
        let period = Theme.titleHueSwingPeriod
        let amplitude = Theme.titleHueSwingAmplitude
        XCTAssertGreaterThan(period, 1, "タイトルの色相の揺れは以前の 1 秒周期より遅くする")
        XCTAssertEqual(amplitude, 30, "選んだ色の周りで ±30° 揺らす（判断ログ #91）")
        // 選んだ色（0°）から始まり、1/4 周期で +振幅、半周期で 0°、3/4 周期で -振幅、1 周期で 0° に戻る
        XCTAssertEqual(TitleView.hueDegrees(at: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(TitleView.hueDegrees(at: period / 4), amplitude, accuracy: 1e-6)
        XCTAssertEqual(TitleView.hueDegrees(at: period / 2), 0, accuracy: 1e-6)
        XCTAssertEqual(TitleView.hueDegrees(at: period * 3 / 4), -amplitude, accuracy: 1e-6)
        XCTAssertEqual(TitleView.hueDegrees(at: period * 3 + period / 4), amplitude, accuracy: 1e-6)
    }

    func testTitleHueStaysWithinSwingAmplitude() {
        let amplitude = Theme.titleHueSwingAmplitude
        for time in stride(from: 0.0, to: 100.0, by: 0.37) {
            let hue = TitleView.hueDegrees(at: time)
            XCTAssertGreaterThanOrEqual(hue, -amplitude - 1e-9)
            XCTAssertLessThanOrEqual(hue, amplitude + 1e-9)
        }
    }

    func testTitleHueSwingIsSmooth() {
        // 30fps の 1 フレームあたりの変化が小さく、折り返しで角度が飛ばない（往復で滑らかに動く）
        let samples = stride(from: 0.0, to: Theme.titleHueSwingPeriod * 2, by: 1.0 / 30).map(TitleView.hueDegrees(at:))
        let maxStep = zip(samples, samples.dropFirst()).map { abs($1 - $0) }.max() ?? .infinity
        XCTAssertLessThan(maxStep, 1)
    }

    func testPausableClockDoesNotAdvanceWhileStopped() {
        let origin = Date(timeIntervalSinceReferenceDate: 1000)
        var clock = PausableClock()
        XCTAssertEqual(clock.elapsed(at: origin), 0)
        clock.start(at: origin)
        XCTAssertEqual(clock.elapsed(at: origin + 3), 3, accuracy: 1e-9)
        clock.stop(at: origin + 3)
        // 止めている間は進まない
        XCTAssertEqual(clock.elapsed(at: origin + 10), 3, accuracy: 1e-9)
        // 再開した瞬間は止めたときと同じ値から続く（色が飛ばない）
        clock.start(at: origin + 10)
        XCTAssertEqual(clock.elapsed(at: origin + 10), 3, accuracy: 1e-9)
        XCTAssertEqual(clock.elapsed(at: origin + 12), 5, accuracy: 1e-9)
    }

    func testPausableClockIgnoresRepeatedStartAndStop() {
        let origin = Date(timeIntervalSinceReferenceDate: 1000)
        var clock = PausableClock()
        clock.stop(at: origin)
        XCTAssertEqual(clock.elapsed(at: origin + 5), 0)
        clock.start(at: origin)
        clock.start(at: origin + 2)
        XCTAssertEqual(clock.elapsed(at: origin + 4), 4, accuracy: 1e-9)
        clock.stop(at: origin + 4)
        clock.stop(at: origin + 6)
        XCTAssertEqual(clock.elapsed(at: origin + 8), 4, accuracy: 1e-9)
    }

    // MARK: - ロゴのマークのバーの動き（LogoMarkMotion）

    private func sound(
        _ frequencies: [Double] = [440],
        volume: Double = 1,
        waveform: Waveform = .sine
    ) -> LogoSound {
        LogoSound(frequencies: ToneFrequencies(frequencies), volume: volume, waveform: waveform)
    }

    func testBarsKeepIconShapeWhenNotAnimating() {
        // 停止中・Reduce Motion・撮影モード（isAnimating が false）はアイコンの形
        for phase in [0, 0.3, 12.7] {
            XCTAssertEqual(LogoMarkMotion.barScales(phase: phase, sound: sound(), isAnimating: false), LogoMarkMotion.restingScales)
        }
        XCTAssertEqual(LogoMarkMotion.restingScales, [1, 1, 1, 1, 1])
    }

    func testBarsStartFromIconShape() {
        // 位相 0（動き始め）はアイコンの形なので、再生を始めた瞬間に飛ばない
        for waveform in Waveform.allCases {
            for scale in LogoMarkMotion.barScales(phase: 0, sound: sound(waveform: waveform), isAnimating: true) {
                XCTAssertEqual(Double(scale), 1, accuracy: 1e-9, "\(waveform)")
            }
        }
    }

    func testBarsStayWithinIconLengthAndDepth() {
        let chord = sound([220, 277.18, 329.63])
        for waveform in Waveform.allCases {
            for current in [sound(waveform: waveform), LogoSound(frequencies: chord.frequencies, volume: 1, waveform: waveform)] {
                for step in 0..<600 {
                    let scales = LogoMarkMotion.barScales(phase: Double(step) * 0.0137, sound: current, isAnimating: true)
                    XCTAssertEqual(scales.count, 5)
                    for scale in scales {
                        // アイコンの長さを超えず（図柄からはみ出さない）、深さより縮まない
                        XCTAssertLessThanOrEqual(Double(scale), 1 + 1e-9)
                        XCTAssertGreaterThanOrEqual(Double(scale), 1 - Theme.LogoMotion.maxDepth - 1e-9)
                    }
                }
            }
        }
    }

    func testSilentToneDoesNotMoveBars() {
        // 音量 0 なら鳴っていないので動かさない
        for phase in [0.25, 0.5, 3.4] {
            for scale in LogoMarkMotion.barScales(phase: phase, sound: sound(volume: 0), isAnimating: true) {
                XCTAssertEqual(Double(scale), 1, accuracy: 1e-9)
            }
        }
        // 音量が大きいほど深く縮む
        XCTAssertLessThan(LogoMarkMotion.depth(volume: 0.3), LogoMarkMotion.depth(volume: 0.8))
        XCTAssertEqual(LogoMarkMotion.depth(volume: 2), Theme.LogoMotion.maxDepth)
    }

    func testBarsDoNotJumpBetweenFrames() {
        // 1/30 秒（描画の間隔）進んだときの長さの変化が小さい（いちばん速い 20kHz・和音・音量 100% でも）
        let fastest = [sound([20000]), sound([10000, 12599, 14983])]
        for base in fastest {
            let rate = LogoMarkMotion.baseRate(for: base.frequencies)
            for waveform in Waveform.allCases {
                let current = LogoSound(frequencies: base.frequencies, volume: 1, waveform: waveform)
                var previous = LogoMarkMotion.barScales(phase: 0, sound: current, isAnimating: true)
                for frame in 1...300 {
                    let scales = LogoMarkMotion.barScales(phase: rate * Double(frame) / 30, sound: current, isAnimating: true)
                    for (now, before) in zip(scales, previous) {
                        XCTAssertLessThan(abs(Double(now - before)), 0.3, "\(waveform) frame \(frame)")
                    }
                    previous = scales
                }
            }
        }
    }

    func testBarsNeverMoveFasterThanFlashThreshold() {
        // どのバーも 1 秒に 3 往復を超えない（点滅に見えない）。いちばん速いのは 20kHz の根音と 1 オクターブ上の構成音
        let fastestRate = LogoMarkMotion.baseRate(for: ToneFrequencies(20000))
        XCTAssertEqual(fastestRate, Theme.LogoMotion.maxRate, accuracy: 1e-9)
        let widestChord = ToneFrequencies([10000, 15000, 20000])
        let factors = LogoMarkMotion.barRateFactors(for: widestChord) + LogoMarkMotion.barRateFactors(for: ToneFrequencies(20000))
        for factor in factors {
            XCTAssertLessThanOrEqual(fastestRate * factor, Theme.LogoMotion.maxBarRate)
        }
        XCTAssertLessThan(Theme.LogoMotion.maxBarRate, 3)
    }

    func testHigherToneMovesFaster() {
        let low = LogoMarkMotion.baseRate(for: ToneFrequencies(20))
        let middle = LogoMarkMotion.baseRate(for: ToneFrequencies(440))
        let high = LogoMarkMotion.baseRate(for: ToneFrequencies(20000))
        XCTAssertEqual(low, Theme.LogoMotion.minRate, accuracy: 1e-9)
        XCTAssertLessThan(low, middle)
        XCTAssertLessThan(middle, high)
        // 範囲外の周波数は端に寄せる
        XCTAssertEqual(LogoMarkMotion.baseRate(for: ToneFrequencies(5)), low, accuracy: 1e-9)
    }

    func testChordSpreadsBarsByChordTones() {
        // 単音はバーごとの倍率だけ。和音は中央（根音）を除き、構成音が高いバーほど速い
        let single = LogoMarkMotion.barRateFactors(for: ToneFrequencies(440))
        XCTAssertEqual(single, Theme.LogoMotion.barRateFactors)
        let chord = LogoMarkMotion.barRateFactors(for: ToneFrequencies([440, 554.37, 659.26]))
        XCTAssertEqual(chord[2], single[2], accuracy: 1e-9)
        for index in [0, 1, 3, 4] {
            XCTAssertGreaterThan(chord[index], single[index])
        }
        // 第 5 音（バー 1・3）は第 3 音（バー 0・4）より上がり幅が大きい
        XCTAssertGreaterThan(chord[1] / single[1], chord[0] / single[0])
    }

    func testWaveformsGiveDifferentMotion() {
        // どの波形も 1 往復の始めと終わりで 0（つなぎ目で途切れない）、途中は 0...1
        for waveform in Waveform.allCases {
            XCTAssertEqual(LogoMarkMotion.shape(waveform, phase: 0), 0, accuracy: 1e-9)
            XCTAssertEqual(LogoMarkMotion.shape(waveform, phase: 1), 0, accuracy: 1e-9)
            XCTAssertEqual(LogoMarkMotion.shape(waveform, phase: 0.9999), 0, accuracy: 1e-2)
            for step in 0...100 {
                let value = LogoMarkMotion.shape(waveform, phase: Double(step) / 100)
                XCTAssertGreaterThanOrEqual(value, -1e-9)
                XCTAssertLessThanOrEqual(value, 1 + 1e-9)
            }
        }
        // 動き始めの位置で形が違う（Square は端にとどまり、Triangle は一定の速さで縮む）
        let early = Waveform.allCases.map { LogoMarkMotion.shape($0, phase: 0.15) }
        XCTAssertEqual(Set(early.map { ($0 * 1000).rounded() }).count, Waveform.allCases.count)
        XCTAssertLessThan(LogoMarkMotion.shape(.square, phase: 0.15), LogoMarkMotion.shape(.sine, phase: 0.15))
        XCTAssertEqual(LogoMarkMotion.shape(.triangle, phase: 0.15), 0.3, accuracy: 1e-9)
        XCTAssertEqual(LogoMarkMotion.shape(.sawtooth, phase: 0.75), 1, accuracy: 1e-9)
    }

    func testPhaseAccumulatorKeepsPhaseWhenRateChanges() {
        var phase = PhaseAccumulator()
        phase.setRate(1, at: 0)
        XCTAssertEqual(phase.phase(at: 2), 2, accuracy: 1e-9)
        // 速さを変えた瞬間は同じ位相から続く（長さが飛ばない）
        phase.setRate(0.5, at: 2)
        XCTAssertEqual(phase.phase(at: 2), 2, accuracy: 1e-9)
        XCTAssertEqual(phase.phase(at: 4), 3, accuracy: 1e-9)
        // 時刻が戻っても位相は戻らない
        XCTAssertEqual(phase.phase(at: 1), 2, accuracy: 1e-9)
    }
}
