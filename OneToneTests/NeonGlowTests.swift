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

    /// 動き始めてから `time` 秒、同じ音を鳴らし続けたときのバーの長さの比
    private func scales(_ sound: LogoSound, after time: TimeInterval) -> [CGFloat] {
        var phases = LogoMarkPhases()
        phases.setRates(LogoMarkMotion.barRates(for: sound.frequencies), at: 0)
        return LogoMarkMotion.barScales(phases: phases.phases(at: time), sound: sound, isAnimating: true)
    }

    func testBarsKeepIconShapeWhenNotAnimating() {
        // 停止中・Reduce Motion・撮影モード（isAnimating が false）はアイコンの形
        for phase in [0, 0.3, 12.7] {
            let phases = Array(repeating: phase, count: 5)
            XCTAssertEqual(LogoMarkMotion.barScales(phases: phases, sound: sound(), isAnimating: false), LogoMarkMotion.restingScales)
        }
        XCTAssertEqual(LogoMarkMotion.restingScales, [1, 1, 1, 1, 1])
    }

    func testBarsStartFromIconShape() {
        // 動き始め（位相 0）はアイコンの形なので、再生を始めた瞬間に飛ばない
        for waveform in Waveform.allCases {
            for scale in scales(sound(waveform: waveform), after: 0) {
                XCTAssertEqual(Double(scale), 1, accuracy: 1e-9, "\(waveform)")
            }
        }
    }

    func testBarsStayWithinIconLengthAndDepth() {
        let chord = [220, 277.18, 329.63]
        for waveform in Waveform.allCases {
            for current in [sound(waveform: waveform), sound(chord, waveform: waveform)] {
                for step in 0..<600 {
                    let scales = scales(current, after: Double(step) * 0.0137)
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
        for time in [0.25, 0.5, 3.4] {
            for scale in scales(sound(volume: 0), after: time) {
                XCTAssertEqual(Double(scale), 1, accuracy: 1e-9)
            }
        }
        // 音量が大きいほど深く縮む
        XCTAssertLessThan(LogoMarkMotion.depth(volume: 0.3), LogoMarkMotion.depth(volume: 0.8))
        XCTAssertEqual(LogoMarkMotion.depth(volume: 2), Theme.LogoMotion.maxDepth)
    }

    func testBarsDoNotJumpBetweenFrames() {
        // 1/30 秒（描画の間隔）進んだときの長さの変化が小さい（いちばん速い 20kHz・和音・音量 100% でも）
        for frequencies in [[20000.0], [10000, 12599, 14983]] {
            for waveform in Waveform.allCases {
                let current = sound(frequencies, waveform: waveform)
                var previous = scales(current, after: 0)
                for frame in 1...300 {
                    let now = scales(current, after: Double(frame) / 30)
                    for (after, before) in zip(now, previous) {
                        XCTAssertLessThan(abs(Double(after - before)), 0.3, "\(waveform) frame \(frame)")
                    }
                    previous = now
                }
            }
        }
    }

    func testBarsNeverMoveFasterThanFlashThreshold() {
        // どのバーも 1 秒に 3 往復を超えない（点滅に見えない）。いちばん速いのは 20kHz の根音と 1 オクターブ上の構成音
        XCTAssertEqual(LogoMarkMotion.baseRate(for: ToneFrequencies(20000)), Theme.LogoMotion.maxRate, accuracy: 1e-9)
        for frequencies in [ToneFrequencies(20000), ToneFrequencies([10000, 15000, 20000]), ToneFrequencies(20)] {
            for rate in LogoMarkMotion.barRates(for: frequencies) {
                XCTAssertGreaterThan(rate, 0)
                XCTAssertLessThanOrEqual(rate, Theme.LogoMotion.maxBarRate)
            }
        }
        // 今の値の組み合わせでは、上限で抑えなくても上限に届かない（抑えると速さの違いが消えるため）
        let widest = LogoMarkMotion.barRateFactors(for: ToneFrequencies([10000, 15000, 20000]))
        XCTAssertLessThan(Theme.LogoMotion.maxRate * (widest.max() ?? 0), Theme.LogoMotion.maxBarRate)
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

    func testPhasesStayContinuousWhenRatesChange() {
        var phases = LogoMarkPhases()
        phases.setRates([1, 1, 1, 1, 1], at: 0)
        XCTAssertEqual(phases.phases(at: 2), [2, 2, 2, 2, 2])
        // 速さを変えた瞬間はバーごとに同じ位相から続く（長さが飛ばない）
        phases.setRates([0.5, 1, 2, 1, 0.5], at: 2)
        XCTAssertEqual(phases.phases(at: 2), [2, 2, 2, 2, 2])
        XCTAssertEqual(phases.phases(at: 4), [3, 4, 6, 4, 3])
        // 時刻が戻っても位相は戻らない
        XCTAssertEqual(phases.phases(at: 1), [2, 2, 2, 2, 2])
    }

    func testChangingChordQualityDoesNotJumpBars() {
        // 30 秒鳴らしてから、根音が同じまま C → Cm に替えても（基本の速さは同じで、バーごとの倍率だけが変わる）長さが飛ばない
        let major = sound([261.63, 329.63, 392.0])
        let minor = sound([261.63, 311.13, 392.0])
        XCTAssertEqual(LogoMarkMotion.baseRate(for: major.frequencies), LogoMarkMotion.baseRate(for: minor.frequencies))
        XCTAssertNotEqual(LogoMarkMotion.barRates(for: major.frequencies), LogoMarkMotion.barRates(for: minor.frequencies))
        var phases = LogoMarkPhases()
        phases.setRates(LogoMarkMotion.barRates(for: major.frequencies), at: 0)
        let before = LogoMarkMotion.barScales(phases: phases.phases(at: 30), sound: minor, isAnimating: true)
        phases.setRates(LogoMarkMotion.barRates(for: minor.frequencies), at: 30)
        let after = LogoMarkMotion.barScales(phases: phases.phases(at: 30), sound: minor, isAnimating: true)
        XCTAssertEqual(before, after)
        // 単音から和音に替えたときも同じ
        var single = LogoMarkPhases()
        single.setRates(LogoMarkMotion.barRates(for: ToneFrequencies(261.63)), at: 0)
        let atSwitch = single.phases(at: 30)
        single.setRates(LogoMarkMotion.barRates(for: major.frequencies), at: 30)
        XCTAssertEqual(single.phases(at: 30), atSwitch)
    }

    func testRestartingStartsBarsFromIconShape() {
        // 止めてから再生し直すと、途中の位相ではなく 0（アイコンの形）から動き始める
        let current = sound()
        var phases = LogoMarkPhases()
        phases.setRates(LogoMarkMotion.barRates(for: current.frequencies), at: 0)
        let playing = LogoMarkMotion.barScales(phases: phases.phases(at: 1.3), sound: current, isAnimating: true)
        XCTAssertTrue(playing.contains { $0 < 0.99 })
        phases.restart(at: 1.3)
        XCTAssertEqual(phases.phases(at: 1.3), [0, 0, 0, 0, 0])
        XCTAssertEqual(LogoMarkMotion.barScales(phases: phases.phases(at: 1.3), sound: current, isAnimating: true), LogoMarkMotion.restingScales)
        // 速さはそのまま
        XCTAssertEqual(phases.rates, LogoMarkMotion.barRates(for: current.frequencies))
        XCTAssertEqual(phases.phases(at: 2.3)[2], phases.rates[2], accuracy: 1e-9)
    }
}
