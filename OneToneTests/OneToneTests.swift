//
//  OneToneTests.swift
//  OneToneTests
//
//  Created by 村石 拓海 on 2024/05/28.
//

import XCTest
@testable import OneTone

final class OneToneTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testStopToneWithoutPlayingKeepsIsPlayingFalse() {
        let manager = AudioManager()
        manager.stopTone()
        XCTAssertFalse(manager.isPlaying)
    }

    func testStopToneResetsIsPlaying() {
        let manager = AudioManager()
        manager.playTone(frequency: 440)
        XCTAssertTrue(manager.isPlaying)
        manager.stopTone()
        XCTAssertFalse(manager.isPlaying)
    }

    func testUpdateFrequencyAfterStopDoesNotRestartPlayback() {
        let manager = AudioManager()
        manager.playTone(frequency: 440)
        manager.stopTone()
        manager.updateFrequency(1000)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertEqual(manager.currentFrequency, 1000)
    }

    func testToneGeneratorSamplesStayInRange() {
        var generator = ToneGenerator(sampleRate: 48000, frequency: 440)
        for _ in 0..<48000 {
            let sample = generator.nextSample()
            XCTAssertLessThanOrEqual(abs(sample), 1)
            XCTAssertTrue((0..<1).contains(generator.phase))
        }
    }

    func testToneGeneratorCompletesOneCyclePerPeriod() {
        // 48000 / 480 = 100 サンプルでちょうど 1 周期
        var generator = ToneGenerator(sampleRate: 48000, frequency: 480)
        let first = generator.nextSample()
        for _ in 0..<99 {
            _ = generator.nextSample()
        }
        XCTAssertEqual(generator.nextSample(), first, accuracy: 1e-6)
    }

    func testToneGeneratorOutputsSineWave() {
        // 1 周期 4 サンプルなら 0, 1, 0, -1 になる
        var generator = ToneGenerator(sampleRate: 4, frequency: 1)
        let samples = (0..<4).map { _ in generator.nextSample() }
        XCTAssertEqual(samples[0], 0, accuracy: 1e-6)
        XCTAssertEqual(samples[1], 1, accuracy: 1e-6)
        XCTAssertEqual(samples[2], 0, accuracy: 1e-6)
        XCTAssertEqual(samples[3], -1, accuracy: 1e-6)
    }

    func testToneGeneratorKeepsPhaseWhenFrequencyChanges() {
        let sampleRate = 48000.0
        var generator = ToneGenerator(sampleRate: sampleRate, frequency: 440)
        for _ in 0..<1234 {
            _ = generator.nextSample()
        }
        let phaseBeforeChange = generator.phase
        generator.frequency = 1000

        // 周波数を変えても位相はリセットされず、そこから新しい周波数ぶんだけ進む
        XCTAssertEqual(generator.phase, phaseBeforeChange)
        let sample = generator.nextSample()
        XCTAssertEqual(sample, Float(sin(2 * Double.pi * phaseBeforeChange)), accuracy: 1e-6)
        let expectedPhase = phaseBeforeChange + 1000 / sampleRate
        XCTAssertEqual(generator.phase, expectedPhase - floor(expectedPhase), accuracy: 1e-12)
    }

    func testToneGeneratorAdjacentSamplesAreContinuousAcrossFrequencyChange() {
        // 1 サンプルあたりの変化量は、使った周波数のうち高い方で 2π × f / fs 以下に収まる（位相が飛ぶとこれを超える）
        let sampleRate = 48000.0
        let maxStep = Float(2 * Double.pi * 2000 / sampleRate) + 1e-4
        var generator = ToneGenerator(sampleRate: sampleRate, frequency: 200)
        var previous = generator.nextSample()
        for index in 1..<4800 {
            if index % 480 == 0 {
                generator.frequency = generator.frequency == 200 ? 2000 : 200
            }
            let sample = generator.nextSample()
            XCTAssertLessThanOrEqual(abs(sample - previous), maxStep)
            previous = sample
        }
    }
    // MARK: - ParameterSmoother

    func testSmootherConvergesToTargetWithoutOvershoot() {
        var smoother = ParameterSmoother(value: 0, sampleRate: 48000, timeConstant: 0.005)
        smoother.target = 1
        var previous = smoother.current
        // 時定数の 10 倍（50ms）で差分は e^-10 ≒ 0.005% 未満になる
        for _ in 0..<2400 {
            let value = smoother.next()
            XCTAssertGreaterThanOrEqual(value, previous)
            XCTAssertLessThanOrEqual(value, 1)
            previous = value
        }
        XCTAssertEqual(smoother.current, 1, accuracy: 1e-4)
    }

    func testSmootherReachesAbout63PercentAfterTimeConstant() {
        var smoother = ParameterSmoother(value: 100, sampleRate: 48000, timeConstant: 0.005)
        smoother.target = 200
        for _ in 0..<240 {
            _ = smoother.next()
        }
        XCTAssertEqual(smoother.current, 100 + 100 * (1 - exp(-1)), accuracy: 1e-6)
    }

    func testSmootherSnapSkipsInterpolation() {
        var smoother = ParameterSmoother(value: 0, sampleRate: 48000, timeConstant: 0.005)
        smoother.snap(to: 440)
        XCTAssertEqual(smoother.current, 440)
        XCTAssertEqual(smoother.next(), 440)
    }

    // MARK: - ToneSynthesizer

    func testSynthesizerIsSilentBeforePlaying() {
        var synthesizer = ToneSynthesizer(sampleRate: 48000, frequency: 440, volume: 1, waveform: .sine)
        synthesizer.update(frequency: 440, volume: 1, waveform: .sine, isPlaying: false)
        XCTAssertTrue(synthesizer.isSilent)
    }

    func testSynthesizerFadesInFromSilence() {
        var synthesizer = ToneSynthesizer(sampleRate: 48000, frequency: 440, volume: 1, waveform: .sine)
        synthesizer.update(frequency: 440, volume: 1, waveform: .sine, isPlaying: true)
        XCTAssertFalse(synthesizer.isSilent)
        // 立ち上がりの 1 周期目は最大振幅に届かない（いきなり ±1 にならない）
        let firstCycle = (0..<109).map { _ in abs(synthesizer.nextSample()) }
        XCTAssertLessThan(firstCycle.max()!, 0.5)
        // 十分な時間が経てば最大振幅まで上がる
        for _ in 0..<4800 {
            _ = synthesizer.nextSample()
        }
        let settled = (0..<109).map { _ in abs(synthesizer.nextSample()) }
        XCTAssertEqual(settled.max()!, 1, accuracy: 0.01)
    }

    func testSynthesizerFadesOutAndBecomesSilentAfterStop() {
        var synthesizer = ToneSynthesizer(sampleRate: 48000, frequency: 440, volume: 1, waveform: .sine)
        synthesizer.update(frequency: 440, volume: 1, waveform: .sine, isPlaying: true)
        for _ in 0..<4800 {
            _ = synthesizer.nextSample()
        }
        synthesizer.update(frequency: 440, volume: 1, waveform: .sine, isPlaying: false)
        // 停止直後はまだフェードアウト中で、すぐには無音にならない
        XCTAssertFalse(synthesizer.isSilent)
        var previousPeak = Float.greatestFiniteMagnitude
        // 約 -80dB まで下がるのは時定数の約 9.2 倍（46ms）。余裕を見て 1 周期 × 30（68ms）回す
        for _ in 0..<30 {
            let peak = (0..<109).map { _ in abs(synthesizer.nextSample()) }.max()!
            XCTAssertLessThanOrEqual(peak, previousPeak + 1e-6)
            previousPeak = peak
        }
        synthesizer.update(frequency: 440, volume: 1, waveform: .sine, isPlaying: false)
        XCTAssertTrue(synthesizer.isSilent)
    }

    func testSynthesizerGlidesFrequencyWhilePlaying() {
        var synthesizer = ToneSynthesizer(sampleRate: 48000, frequency: 440, volume: 1, waveform: .sine)
        synthesizer.update(frequency: 440, volume: 1, waveform: .sine, isPlaying: true)
        for _ in 0..<4800 {
            _ = synthesizer.nextSample()
        }
        synthesizer.update(frequency: 880, volume: 1, waveform: .sine, isPlaying: true)
        _ = synthesizer.nextSample()
        // 1 サンプル目では目標に届かず、中間の周波数になっている
        XCTAssertGreaterThan(synthesizer.generator.frequency, 440)
        XCTAssertLessThan(synthesizer.generator.frequency, 880)
        for _ in 0..<2400 {
            _ = synthesizer.nextSample()
        }
        XCTAssertEqual(synthesizer.generator.frequency, 880, accuracy: 0.1)
    }

    func testSynthesizerStartsAtTargetFrequencyFromSilence() {
        var synthesizer = ToneSynthesizer(sampleRate: 48000, frequency: 440, volume: 1, waveform: .sine)
        // 停止中に周波数を変えてから鳴らしたときは、前の周波数から滑らせない
        synthesizer.update(frequency: 1000, volume: 1, waveform: .sine, isPlaying: true)
        _ = synthesizer.nextSample()
        XCTAssertEqual(synthesizer.generator.frequency, 1000)
    }

    func testSynthesizerOutputHasNoLargeJumpOnStartAndStop() {
        // 開始・停止をまたいでも、隣り合うサンプルの差は正弦波の 1 サンプル分の変化量を超えない
        let sampleRate = 48000.0
        let maxStep = Float(2 * Double.pi * 440 / sampleRate) + 1e-3
        var synthesizer = ToneSynthesizer(sampleRate: sampleRate, frequency: 440, volume: 1, waveform: .sine)
        var previous: Float = 0
        for index in 0..<9600 {
            if index % 1024 == 0 {
                synthesizer.update(frequency: 440, volume: 1, waveform: .sine, isPlaying: (index / 1024) % 2 == 0)
            }
            let sample = synthesizer.nextSample()
            XCTAssertLessThanOrEqual(abs(sample - previous), maxStep)
            previous = sample
        }
    }
    func testSynthesizerScalesOutputByVolume() {
        var synthesizer = ToneSynthesizer(sampleRate: 48000, frequency: 440, volume: 0.25, waveform: .sine)
        synthesizer.update(frequency: 440, volume: 0.25, waveform: .sine, isPlaying: true)
        for _ in 0..<4800 {
            _ = synthesizer.nextSample()
        }
        let peak = (0..<109).map { _ in abs(synthesizer.nextSample()) }.max()!
        XCTAssertEqual(peak, 0.25, accuracy: 0.005)
    }

    func testSynthesizerAppliesVolumeChangeWhilePlayingSmoothly() {
        let sampleRate = 48000.0
        var synthesizer = ToneSynthesizer(sampleRate: sampleRate, frequency: 440, volume: 1, waveform: .sine)
        synthesizer.update(frequency: 440, volume: 1, waveform: .sine, isPlaying: true)
        for _ in 0..<4800 {
            _ = synthesizer.nextSample()
        }
        // 再生中に音量を下げると、段差を出さずに新しい音量へ移る
        synthesizer.update(frequency: 440, volume: 0.1, waveform: .sine, isPlaying: true)
        let maxStep = Float(2 * Double.pi * 440 / sampleRate) + 1e-3
        var previous = synthesizer.nextSample()
        for _ in 0..<4800 {
            let sample = synthesizer.nextSample()
            XCTAssertLessThanOrEqual(abs(sample - previous), maxStep)
            previous = sample
        }
        let peak = (0..<109).map { _ in abs(synthesizer.nextSample()) }.max()!
        XCTAssertEqual(peak, 0.1, accuracy: 0.005)
    }

    func testSynthesizerClampsVolumeToValidRange() {
        var synthesizer = ToneSynthesizer(sampleRate: 48000, frequency: 440, volume: 1, waveform: .sine)
        synthesizer.update(frequency: 440, volume: 3, waveform: .sine, isPlaying: true)
        for _ in 0..<4800 {
            XCTAssertLessThanOrEqual(abs(synthesizer.nextSample()), 1)
        }

        var muted = ToneSynthesizer(sampleRate: 48000, frequency: 440, volume: 1, waveform: .sine)
        muted.update(frequency: 440, volume: -1, waveform: .sine, isPlaying: true)
        for _ in 0..<480 {
            XCTAssertEqual(muted.nextSample(), 0)
        }
    }

    func testUpdateVolumeKeepsCurrentVolume() {
        let manager = AudioManager()
        XCTAssertEqual(manager.currentVolume, 0.5)
        manager.updateVolume(0.8)
        XCTAssertEqual(manager.currentVolume, 0.8)
    }
    // MARK: - Waveform

    func testWaveformValuesAtKeyPhases() {
        let phases = [0, 0.25, 0.5, 0.75]
        let expected: [Waveform: [Double]] = [
            .sine: [0, 1, 0, -1],
            .square: [1, 1, -1, -1],
            .triangle: [0, 1, 0, -1],
            .sawtooth: [0, 0.5, -1, -0.5],
        ]
        for (waveform, values) in expected {
            for (phase, value) in zip(phases, values) {
                XCTAssertEqual(waveform.value(at: phase), value, accuracy: 1e-9, "\(waveform) @ \(phase)")
            }
        }
    }

    func testWaveformValuesStayInRange() {
        for waveform in Waveform.allCases {
            for step in 0..<1000 {
                let value = waveform.value(at: Double(step) / 1000)
                XCTAssertLessThanOrEqual(abs(value), 1, "\(waveform)")
            }
        }
    }

    func testTriangleWaveIsContinuous() {
        // 三角波は周期の境目（1 → 0）も含めて段差が無い
        var previous = Waveform.triangle.value(at: 0.999)
        for step in 0..<1000 {
            let value = Waveform.triangle.value(at: Double(step) / 1000)
            XCTAssertLessThanOrEqual(abs(value - previous), 0.004 + 1e-9)
            previous = value
        }
    }

    // MARK: - ToneSynthesizer（波形）

    func testSynthesizerCrossfadesWaveformWithoutJump() {
        var synthesizer = ToneSynthesizer(sampleRate: 48000, frequency: 440, volume: 1, waveform: .sine)
        synthesizer.update(frequency: 440, volume: 1, waveform: .sine, isPlaying: true)
        for _ in 0..<4800 {
            _ = synthesizer.nextSample()
        }
        // サイン波が 0 付近を通る位置で矩形波（±1）へ切り替えても、いきなり ±1 に飛ばない
        var previous = synthesizer.nextSample()
        while abs(previous) > 0.05 {
            previous = synthesizer.nextSample()
        }
        synthesizer.update(frequency: 440, volume: 1, waveform: .square, isPlaying: true)
        XCTAssertEqual(synthesizer.waveform, .square)
        let next = synthesizer.nextSample()
        XCTAssertLessThan(abs(next - previous), 0.1)

        // クロスフェードが終われば矩形波そのものになる
        for _ in 0..<4800 {
            _ = synthesizer.nextSample()
        }
        for _ in 0..<109 {
            XCTAssertEqual(abs(synthesizer.nextSample()), 1, accuracy: 0.001)
        }
    }

    func testSynthesizerStartsWithSelectedWaveformFromSilence() {
        var synthesizer = ToneSynthesizer(sampleRate: 48000, frequency: 440, volume: 1, waveform: .sine)
        // 停止中に選び直した波形は、クロスフェードせずにそのまま鳴り始める
        synthesizer.update(frequency: 440, volume: 1, waveform: .square, isPlaying: true)
        for _ in 0..<4800 {
            _ = synthesizer.nextSample()
        }
        for _ in 0..<109 {
            XCTAssertEqual(abs(synthesizer.nextSample()), 1, accuracy: 0.001)
        }
    }

    func testUpdateWaveformKeepsCurrentWaveform() {
        let manager = AudioManager()
        XCTAssertEqual(manager.currentWaveform, .sine)
        manager.updateWaveform(.triangle)
        XCTAssertEqual(manager.currentWaveform, .triangle)
    }
    // MARK: - FrequencyInput

    func testFrequencyInputAcceptsValuesInRange() {
        XCTAssertEqual(FrequencyInput.parse("440"), 440)
        XCTAssertEqual(FrequencyInput.parse("20"), 20)
        XCTAssertEqual(FrequencyInput.parse("20000"), 20000)
        XCTAssertEqual(FrequencyInput.parse("1234.5"), 1234.5)
        XCTAssertEqual(FrequencyInput.parse(" 1000 "), 1000)
    }

    func testFrequencyInputRejectsOutOfRangeOrInvalidValues() {
        for text in ["19.9", "20001", "0", "-440", "", "abc", "440Hz", "nan", "inf"] {
            XCTAssertNil(FrequencyInput.parse(text), text)
        }
    }

    func testFrequencyInputFormatRoundsToInteger() {
        XCTAssertEqual(FrequencyInput.format(439.6), "440")
        XCTAssertEqual(FrequencyInput.format(20), "20")
        XCTAssertEqual(FrequencyInput.format(19999.4), "19999")
    }

    func testPresetIsSelectedWhenDisplayedFrequencyMatches() {
        XCTAssertTrue(FrequencyInput.isPresetSelected(440, frequency: 440))
        // 表示（1Hz 単位）が一致すれば選択中とみなす
        XCTAssertTrue(FrequencyInput.isPresetSelected(440, frequency: 439.6))
        XCTAssertTrue(FrequencyInput.isPresetSelected(1000, frequency: 1000.4))
        XCTAssertFalse(FrequencyInput.isPresetSelected(440, frequency: 439.4))
        XCTAssertFalse(FrequencyInput.isPresetSelected(440, frequency: 1000))
        // 選択中になるプリセットは高々 1 つ
        for frequency in [20.0, 100, 440, 1000, 10000, 20000] {
            let selected = FrequencyInput.presets.filter { FrequencyInput.isPresetSelected($0, frequency: frequency) }
            XCTAssertLessThanOrEqual(selected.count, 1)
        }
    }

    func testFaderMovesUpWhenDraggedUp() {
        // 溝の長さだけ上へドラッグすると 0% から 100% になる
        XCTAssertEqual(FaderMapping.volume(from: 0, dragHeight: -Double(FaderMapping.trackHeight)), 1, accuracy: 1e-9)
        XCTAssertEqual(FaderMapping.volume(from: 0.5, dragHeight: -Double(FaderMapping.trackHeight) / 4), 0.75, accuracy: 1e-9)
        XCTAssertEqual(FaderMapping.volume(from: 0.5, dragHeight: Double(FaderMapping.trackHeight) / 4), 0.25, accuracy: 1e-9)
        // 動かさなければ始点のまま（掴んだ位置へ飛ばない）
        XCTAssertEqual(FaderMapping.volume(from: 0.3, dragHeight: 0), 0.3, accuracy: 1e-9)
    }

    func testFaderStopsAtEnds() {
        XCTAssertEqual(FaderMapping.volume(from: 0.9, dragHeight: -1000), 1)
        XCTAssertEqual(FaderMapping.volume(from: 0.1, dragHeight: 1000), 0)
        XCTAssertEqual(FaderMapping.clamped(1.2), 1)
        XCTAssertEqual(FaderMapping.clamped(-0.2), 0)
    }

    func testFaderPercentMatchesPreviousVolumeLabel() {
        // 以前の「Volume: 50%」表示と同じ四捨五入
        XCTAssertEqual(FaderMapping.percent(for: 0.5), 50)
        XCTAssertEqual(FaderMapping.percent(for: 0.004), 0)
        XCTAssertEqual(FaderMapping.percent(for: 0.005), 1)
        XCTAssertEqual(FaderMapping.percent(for: 1), 100)
    }

    func testWaveformIconFollowsWaveformDefinition() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        for waveform in Waveform.allCases {
            let points = WaveformIcon.points(for: waveform, in: rect)
            XCTAssertEqual(points.count, WaveformIcon.sampleCount + 1)
            // 左端から右端まで、上下は枠に収まる
            XCTAssertEqual(points.first?.x ?? -1, 0, accuracy: 1e-9)
            XCTAssertEqual(points.last?.x ?? -1, 100, accuracy: 1e-9)
            XCTAssertTrue(points.allSatisfy { $0.y >= -1e-9 && $0.y <= 40 + 1e-9 })
            // 各点の高さは音の定義と同じ値（上が 1、下が -1）
            for (index, point) in points.enumerated().dropLast() {
                let phase = Double(index) / Double(WaveformIcon.sampleCount)
                XCTAssertEqual(point.y, 20 - 20 * waveform.value(at: phase), accuracy: 1e-9)
            }
        }
    }

    func testWaveformIconsDiffer() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 40)
        let shapes = Waveform.allCases.map { WaveformIcon.points(for: $0, in: rect).map(\.y) }
        for i in shapes.indices {
            for j in shapes.indices where i < j {
                XCTAssertNotEqual(shapes[i], shapes[j])
            }
        }
    }

    func testDeckLayoutSwitchesByWidth() {
        // iPhone（縦）は縦積み、iPad の縦向き・広げた macOS は横並び
        XCTAssertFalse(DeckLayout.isSideBySide(width: 390))
        XCTAssertFalse(DeckLayout.isSideBySide(width: 430))
        XCTAssertTrue(DeckLayout.isSideBySide(width: 768))
        XCTAssertTrue(DeckLayout.isSideBySide(width: 1024))
        // 横並びにする幅には、パネル 2 枚の幅に近い余裕がある
        XCTAssertGreaterThanOrEqual(DeckLayout.sideBySideMinWidth, DeckLayout.panelMaxWidth * 1.5)
        // macOS の最小ウィンドウは横並びにならない幅
        XCTAssertFalse(DeckLayout.isSideBySide(width: DeckLayout.minimumWindowSize.width))
    }

    func testFrequencyPresets() {
        XCTAssertEqual(FrequencyInput.presets, [100, 440, 1000, 10000])
        XCTAssertEqual(FrequencyInput.presets.map(FrequencyInput.presetLabel), ["100 Hz", "440 Hz", "1 kHz", "10 kHz"])
        for preset in FrequencyInput.presets {
            XCTAssertNotNil(FrequencyInput.parse(FrequencyInput.format(preset)))
        }
    }

    func testFormattedFrequencyRoundTripsThroughParse() {
        // 入力欄に表示した値をそのまま確定しても、範囲内の値として受け付けられる
        for frequency in [20.0, 20.4, 440, 999.5, 19999.6, 20000] {
            let parsed = FrequencyInput.parse(FrequencyInput.format(frequency))
            XCTAssertNotNil(parsed, "\(frequency)")
            XCTAssertEqual(parsed!, frequency, accuracy: 0.5)
        }
    }
}
