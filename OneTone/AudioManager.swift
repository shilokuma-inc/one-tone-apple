//
//  AudioManager.swift
//  OneTone
//
//  Created by 村石 拓海 on 2024/05/28.
//

import AVFoundation

class AudioManager: ObservableObject {
    /// 出力デバイスが無くサンプルレートが取れない環境向けのフォールバック
    private static let fallbackSampleRate: Double = 44100
    /// 波形表示・レベルメーター用に保持する出力サンプル数。48kHz で約 170ms 分あり、
    /// 20Hz（1 周期 2400 サンプル）の波形と、メーターの集計窓を十分に取れる
    static let outputHistoryCapacity = 8192

    let audioEngine: AVAudioEngine
    /// 実際の出力に合わせたサンプルレート（出力デバイスが無ければ `fallbackSampleRate`）
    let sampleRate: Double
    private let sourceNode: AVAudioSourceNode
    /// Play / Stop ボタンの活性制御に使うため、UI から購読できるようにする
    @Published private(set) var isPlaying: Bool = false
    /// 鳴らす周波数（単音なら 1 つ、和音なら構成音の最大 3 つ）
    private(set) var currentFrequencies = ToneFrequencies(FrequencyInput.defaultFrequency)
    /// 単音の周波数。和音のときは 1 つ目（根音）
    var currentFrequency: Double { currentFrequencies[0] }
    /// 0...1。以前の固定振幅と同じ 0.5 を初期値にする
    var currentVolume: Double = 0.5
    var currentWaveform: Waveform = .sine

    // レンダーブロックはリアルタイムスレッドで動き、ロックやメモリ確保ができない。
    // そのため状態は init で確保したポインタに置き、メインスレッドは値の書き込みだけを行う
    private let synthesizer: UnsafeMutablePointer<ToneSynthesizer>
    private let targetFrequencies: UnsafeMutablePointer<ToneFrequencies>
    private let targetVolume: UnsafeMutablePointer<Double>
    private let targetWaveform: UnsafeMutablePointer<Waveform>
    private let isRendering: UnsafeMutablePointer<Bool>
    /// レンダーブロックが実際に出力したサンプルの写し。UI は `latestOutputSamples(_:)` で描画のたびに読む
    private let outputSamples: SampleRingBuffer

    /// - Parameter startsEngine: false にすると AVAudioEngine を動かさない（音は出ず、レンダーブロックも呼ばれない）。
    ///   スクリーンショットの撮影モードで、`presentAsPlaying` により表示だけを再生中にするときに使う
    init(startsEngine: Bool = true) {
        // セッションを有効にしてから出力フォーマットを読まないと、iOS でサンプルレートが確定しない
        Self.configureAudioSession()
        audioEngine = AVAudioEngine()

        // サンプルレートは 44.1kHz 固定ではなく実際の出力に合わせる。
        // iOS は 48kHz が既定のため、固定値のままだと出力される周波数が指定値からずれる
        let outputSampleRate = audioEngine.outputNode.outputFormat(forBus: 0).sampleRate
        sampleRate = outputSampleRate > 0 ? outputSampleRate : Self.fallbackSampleRate

        synthesizer = .allocate(capacity: 1)
        synthesizer.initialize(to: ToneSynthesizer(sampleRate: sampleRate, frequencies: currentFrequencies, volume: currentVolume, waveform: currentWaveform))
        targetFrequencies = .allocate(capacity: 1)
        targetFrequencies.initialize(to: currentFrequencies)
        targetVolume = .allocate(capacity: 1)
        targetVolume.initialize(to: currentVolume)
        targetWaveform = .allocate(capacity: 1)
        targetWaveform.initialize(to: currentWaveform)
        isRendering = .allocate(capacity: 1)
        isRendering.initialize(to: false)
        outputSamples = SampleRingBuffer(capacity: Self.outputHistoryCapacity)

        let synthesizer = synthesizer
        let targetFrequencies = targetFrequencies
        let targetVolume = targetVolume
        let targetWaveform = targetWaveform
        let isRendering = isRendering
        let outputSamples = outputSamples
        sourceNode = AVAudioSourceNode { isSilence, _, frameCount, audioBufferList -> OSStatus in
            isSilence.pointee = ObjCBool(AudioManager.render(
                frameCount: Int(frameCount),
                into: UnsafeMutableAudioBufferListPointer(audioBufferList),
                synthesizer: synthesizer,
                frequencies: targetFrequencies.pointee,
                volume: targetVolume.pointee,
                waveform: targetWaveform.pointee,
                isPlaying: isRendering.pointee,
                outputSamples: outputSamples
            ))
            return noErr
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        audioEngine.attach(sourceNode)
        audioEngine.connect(sourceNode, to: audioEngine.mainMixerNode, format: format)
        guard startsEngine else { return }
        do {
            try audioEngine.start()
        } catch {
            print("AVAudioEngine の開始に失敗しました: \(error)")
        }
    }

    deinit {
        // レンダーブロックがポインタを参照しなくなってから解放する
        audioEngine.stop()
        synthesizer.deallocate()
        targetFrequencies.deallocate()
        targetVolume.deallocate()
        targetWaveform.deallocate()
        isRendering.deallocate()
        outputSamples.deallocate()
    }

    /// レンダーブロックの中身。AVAudioEngine 無しでテストから呼べるように切り出している。
    /// リアルタイムスレッドで呼ばれるため、ロック・メモリ確保・参照カウントの操作をしない。
    /// - Returns: 無音を出力したら true（`isSilence` に渡す）
    static func render(
        frameCount: Int,
        into buffers: UnsafeMutableAudioBufferListPointer,
        synthesizer: UnsafeMutablePointer<ToneSynthesizer>,
        frequencies: ToneFrequencies,
        volume: Double,
        waveform: Waveform,
        isPlaying: Bool,
        outputSamples: SampleRingBuffer
    ) -> Bool {
        synthesizer.pointee.update(
            frequencies: frequencies,
            volume: volume,
            waveform: waveform,
            isPlaying: isPlaying
        )
        // 停止後もフェードアウトが終わるまでは生成を続け、無音になってから止める
        guard !synthesizer.pointee.isSilent else {
            for buffer in buffers {
                memset(buffer.mData, 0, Int(buffer.mDataByteSize))
            }
            // 表示も実際の出力に合わせて無音にする。書かずにおくと、止めた瞬間の波形が履歴に残り続ける
            for _ in 0..<frameCount {
                outputSamples.write(0)
            }
            return true
        }
        for frame in 0..<frameCount {
            let sample = synthesizer.pointee.nextSample()
            // 出力チャンネル数はデバイスによって変わるため、決め打ちにせず実際の数だけ書き込む
            for buffer in buffers {
                buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = sample
            }
            outputSamples.write(sample)
        }
        return false
    }

    /// 直近に出力したサンプルを古い順に返す（モノラル・-1...1）。メインスレッドから描画のたびに呼ぶ。
    /// サンプルごとに `@Published` を更新するとメインスレッドが追いつかないため、UI が必要なときに取りに来る形にしている
    func latestOutputSamples(_ count: Int) -> [Float] {
        outputSamples.latest(count)
    }

    /// iOS はオーディオセッションのカテゴリを指定しないと、既定の .soloAmbient になり
    /// サイレントスイッチや画面ロックで音が止まってしまうため .playback を明示する。
    /// macOS には AVAudioSession が無いので何もしない。
    private static func configureAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
        } catch {
            print("AVAudioSession の設定に失敗しました: \(error)")
        }
        #endif
    }

    func playTone(frequency: Double) {
        playTone(frequencies: ToneFrequencies(frequency))
    }

    /// 和音（最大 3 音）を鳴らす
    func playTone(frequencies: ToneFrequencies) {
        updateFrequencies(frequencies)
        isRendering.pointee = true
        isPlaying = true
    }

    /// 再生中でも停止中でも呼んでよい。再生中は位相を保ったまま、数 ms かけて新しい周波数へ移る
    func updateFrequency(_ frequency: Double) {
        updateFrequencies(ToneFrequencies(frequency))
    }

    /// 単音・和音のどちらにも使う。再生中は各ボイスが位相を保ったまま数 ms かけて新しい周波数へ移り、
    /// 増えたボイスはフェードインし、減ったボイスはフェードアウトする
    func updateFrequencies(_ frequencies: ToneFrequencies) {
        currentFrequencies = frequencies
        // レンダーブロックとは排他しない（今の 1 つの周波数と同じ扱い）。書き込みの途中を読まれても、
        // 次のコールバックで正しい値に揃い、ボイスの周波数・レベルの補間で段差にはならない。
        // ただし単音 → 和音の途中（数が新しく周波数が古い）を読むと、増えたボイスが根音から数 ms 滑って入ることがある
        targetFrequencies.pointee = frequencies
    }

    /// 0...1 の音量。再生中も数 ms かけて即座に反映する
    func updateVolume(_ volume: Double) {
        currentVolume = volume
        targetVolume.pointee = volume
    }

    /// 再生中も途切れずに、数 ms のクロスフェードで新しい波形へ切り替える
    func updateWaveform(_ waveform: Waveform) {
        currentWaveform = waveform
        targetWaveform.pointee = waveform
    }

    func stopTone() {
        isRendering.pointee = false
        isPlaying = false
    }

    /// スクリーンショットの撮影モード用に、音を出さずに表示だけを「再生中」にする。
    ///
    /// 波形表示とレベルメーターは出力履歴を読んで描くので、履歴をその周波数・波形で合成したサンプルで満たしておく。
    /// エンジンを動かしていない（`init(startsEngine: false)`）ときだけ使う。動いていると、停止中のレンダーブロックが
    /// 履歴を無音で上書きし続け、ここで書いた波形がすぐ消える
    func presentAsPlaying(frequency: Double, volume: Double, waveform: Waveform) {
        presentAsPlaying(frequencies: ToneFrequencies(frequency), volume: volume, waveform: waveform)
    }

    /// 和音を鳴らしているように見せる（`presentAsPlaying(frequency:volume:waveform:)` の和音版）
    func presentAsPlaying(frequencies: ToneFrequencies, volume: Double, waveform: Waveform) {
        assert(!audioEngine.isRunning, "presentAsPlaying は AVAudioEngine を動かしていないときだけ使う")
        updateFrequencies(frequencies)
        updateVolume(volume)
        updateWaveform(waveform)
        var synthesizer = ToneSynthesizer(sampleRate: sampleRate, frequencies: frequencies, volume: volume, waveform: waveform)
        synthesizer.update(frequencies: frequencies, volume: volume, waveform: waveform, isPlaying: true)
        // 先頭のフェードインは履歴の古い側に入り、表示に使う末尾は振幅が落ち着いている
        for _ in 0..<outputSamples.capacity {
            outputSamples.write(synthesizer.nextSample())
        }
        isPlaying = true
    }
}

/// 位相を保持したまま 1 サンプルずつサイン波を生成する。
/// `AVAudioEngine` に依存しないため単体でテストでき、レンダーブロックからも値型のまま使える。
struct ToneGenerator {
    let sampleRate: Double
    var frequency: Double
    /// 1 周期を 0..<1 に正規化した位相。周波数を変えてもここは引き継ぐので波形が不連続にならない
    private(set) var phase: Double = 0

    init(sampleRate: Double, frequency: Double) {
        self.sampleRate = sampleRate
        self.frequency = frequency
    }

    mutating func nextSample() -> Float {
        Float(Waveform.sine.value(at: advance()))
    }

    /// 現在の位相を返し、1 サンプル分進める
    mutating func advance() -> Double {
        let current = phase
        phase += frequency / sampleRate
        // 長時間再生しても精度が落ちないよう、整数部を捨てて 0..<1 に保つ
        phase -= floor(phase)
        return current
    }
}

/// 出力する波形。位相 0 で 0 から立ち上がるよう、すべての波形の位相をサイン波にそろえている
enum Waveform: UInt8, CaseIterable, Identifiable {
    case sine
    case square
    case triangle
    case sawtooth

    var id: Self { self }

    /// 波形名。VoiceOver を含め、全言語で英語のまま出す（訳さない）ので `String` のままにしている
    var displayName: String {
        switch self {
        case .sine: return "Sine"
        case .square: return "Square"
        case .triangle: return "Triangle"
        case .sawtooth: return "Sawtooth"
        }
    }

    /// - Parameter phase: 1 周期を 0..<1 に正規化した位相
    /// - Returns: -1...1 のサンプル値
    func value(at phase: Double) -> Double {
        switch self {
        case .sine:
            return sin(2.0 * Double.pi * phase)
        case .square:
            return phase < 0.5 ? 1 : -1
        case .triangle:
            if phase < 0.25 {
                return 4 * phase
            } else if phase < 0.75 {
                return 2 - 4 * phase
            } else {
                return 4 * phase - 4
            }
        case .sawtooth:
            return phase < 0.5 ? 2 * phase : 2 * phase - 2
        }
    }
}

/// 目標値へ指数的に近づける 1 次のスムーザー。
/// 値が急に切り替わると波形に段差ができてクリックノイズになるため、サンプルごとに少しずつ寄せる。
struct ParameterSmoother {
    private(set) var current: Double
    var target: Double
    /// 1 サンプルで残り差分のどれだけを詰めるか。`timeConstant` 秒で差分の約 63% が埋まる
    private let coefficient: Double

    init(value: Double, sampleRate: Double, timeConstant: Double) {
        current = value
        target = value
        coefficient = 1 - exp(-1 / (timeConstant * sampleRate))
    }

    mutating func next() -> Double {
        current += (target - current) * coefficient
        return current
    }

    /// 補間を飛ばして目標値に揃える
    mutating func snap(to value: Double) {
        current = value
        target = value
    }
}

/// 同時に鳴らす周波数（単音なら 1 つ、和音なら最大 3 つ）。
/// レンダーブロックへ値のまま渡すため、配列ではなく固定長で持つ（コピーでメモリ確保・参照カウントが起きない）
struct ToneFrequencies: Equatable {
    /// 同時に鳴らせる音の数（和音はメジャー / マイナーの 3 和音だけ。Discussion #219 Q2）
    static let maxCount = 3

    /// 1...maxCount
    let count: Int
    private let values: (Double, Double, Double)

    /// 単音
    init(_ frequency: Double) {
        count = 1
        values = (frequency, frequency, frequency)
    }

    /// 1〜3 個の周波数。それ以外の個数はプログラムの誤りなので止める
    init(_ frequencies: [Double]) {
        precondition((1...Self.maxCount).contains(frequencies.count), "周波数は 1〜\(Self.maxCount) 個")
        count = frequencies.count
        let first = frequencies[0]
        values = (first, frequencies.count > 1 ? frequencies[1] : first, frequencies.count > 2 ? frequencies[2] : first)
    }

    /// `index` 番目の周波数。`count` 以上の番号は使わないボイスで、1 つ目と同じ値を返す
    subscript(index: Int) -> Double {
        switch index {
        case 0: return values.0
        case 1: return values.1
        case 2: return values.2
        default: preconditionFailure("ボイスの番号は 0..<\(Self.maxCount)")
        }
    }

    /// 鳴らす周波数（`count` 個）
    var all: [Double] {
        (0..<count).map { self[$0] }
    }

    static func == (lhs: ToneFrequencies, rhs: ToneFrequencies) -> Bool {
        lhs.all == rhs.all
    }
}

/// 和音の 1 音。位相を持つ発振器と、周波数・鳴らすかどうか（レベル）の補間を持つ
struct ToneVoice {
    private(set) var generator: ToneGenerator
    private var frequency: ParameterSmoother
    /// 0 で無音、1 で鳴らす。ボイスが増減したときに段差を出さないよう数 ms かけて移る
    private(set) var level: ParameterSmoother

    init(sampleRate: Double, frequency: Double, isActive: Bool) {
        generator = ToneGenerator(sampleRate: sampleRate, frequency: frequency)
        self.frequency = ParameterSmoother(value: frequency, sampleRate: sampleRate, timeConstant: ToneSynthesizer.smoothingTime)
        level = ParameterSmoother(value: isActive ? 1 : 0, sampleRate: sampleRate, timeConstant: ToneSynthesizer.smoothingTime)
    }

    /// 補間を飛ばして、その周波数・レベルで鳴り始める（無音から鳴らし始めるとき）
    mutating func snap(frequency newFrequency: Double, isActive: Bool) {
        frequency.snap(to: newFrequency)
        level.snap(to: isActive ? 1 : 0)
    }

    /// 再生中の変更。鳴らすボイスは今の周波数から滑らせ、新しく鳴らし始めるボイス（レベルが 0 のもの）は目標の周波数から始める。
    /// 鳴らさなくなったボイスは周波数を変えずにフェードアウトする。フェードアウトし切る前（約 46ms）に鳴らし直したボイスは、
    /// レベルが残っているので前の周波数から滑る（段差は出ない）
    mutating func glide(to newFrequency: Double, isActive: Bool) {
        if isActive {
            if level.current < ToneSynthesizer.silenceThreshold {
                frequency.snap(to: newFrequency)
            } else {
                frequency.target = newFrequency
            }
        }
        level.target = isActive ? 1 : 0
    }

    /// 1 サンプル分進める
    /// - Returns: このサンプルの位相（0..<1）とレベル（0...1）
    mutating func advance() -> (phase: Double, level: Double) {
        generator.frequency = frequency.next()
        return (generator.advance(), level.next())
    }
}

/// 周波数の補間と再生開始・停止時のフェードを含めて、出力サンプルを 1 つずつ作る。
/// レンダーブロックから呼ぶため、メモリ確保をしない値型にしている。
struct ToneSynthesizer {
    /// 周波数・音量・フェードの振幅・波形のクロスフェードを目標値へ寄せる時定数。数 ms で追従し、段差によるクリックノイズを出さない
    static let smoothingTime: Double = 0.005
    /// フェードアウト後、この振幅を下回ったら無音とみなす（約 -80dB）
    static let silenceThreshold: Double = 0.0001

    /// 最大 3 つのボイス。レンダーブロックで配列を確保しないよう固定長で持つ。使わないボイスはレベル 0 で休ませる
    private(set) var voices: (ToneVoice, ToneVoice, ToneVoice)
    private var volume: ParameterSmoother
    private var gain: ParameterSmoother
    private(set) var waveform: Waveform
    /// 切り替え前の波形。`crossfade` が 0 のときはこちらだけが鳴る
    private var previousWaveform: Waveform
    /// 0 で `previousWaveform`、1 で `waveform`。波形を切り替えた瞬間の段差をなくすため数 ms かけて移る
    private var crossfade: ParameterSmoother

    init(sampleRate: Double, frequency: Double, volume: Double, waveform: Waveform) {
        self.init(sampleRate: sampleRate, frequencies: ToneFrequencies(frequency), volume: volume, waveform: waveform)
    }

    init(sampleRate: Double, frequencies: ToneFrequencies, volume: Double, waveform: Waveform) {
        voices = (
            ToneVoice(sampleRate: sampleRate, frequency: frequencies[0], isActive: frequencies.count > 0),
            ToneVoice(sampleRate: sampleRate, frequency: frequencies[1], isActive: frequencies.count > 1),
            ToneVoice(sampleRate: sampleRate, frequency: frequencies[2], isActive: frequencies.count > 2)
        )
        self.volume = ParameterSmoother(value: volume, sampleRate: sampleRate, timeConstant: Self.smoothingTime)
        gain = ParameterSmoother(value: 0, sampleRate: sampleRate, timeConstant: Self.smoothingTime)
        self.waveform = waveform
        previousWaveform = waveform
        crossfade = ParameterSmoother(value: 1, sampleRate: sampleRate, timeConstant: Self.smoothingTime)
    }

    /// 1 つ目のボイスの発振器（単音のときに鳴っている音）
    var generator: ToneGenerator { voices.0.generator }

    /// フェードアウトが終わり、出力が無音になっているか
    var isSilent: Bool {
        gain.target == 0 && gain.current < Self.silenceThreshold
    }

    /// 単音の更新（`update(frequencies:volume:waveform:isPlaying:)` の 1 音版）
    mutating func update(
        frequency newFrequency: Double,
        volume newVolume: Double,
        waveform newWaveform: Waveform,
        isPlaying: Bool
    ) {
        update(frequencies: ToneFrequencies(newFrequency), volume: newVolume, waveform: newWaveform, isPlaying: isPlaying)
    }

    /// - Parameter newVolume: 0...1 の音量。範囲外は丸める
    mutating func update(
        frequencies newFrequencies: ToneFrequencies,
        volume newVolume: Double,
        waveform newWaveform: Waveform,
        isPlaying: Bool
    ) {
        let clampedVolume = min(max(newVolume, 0), 1)
        if gain.current < Self.silenceThreshold {
            // 無音から鳴らし始めるときは、前回の値から滑らせず目標の周波数・音量・波形・ボイス数でそのまま始める
            voices.0.snap(frequency: newFrequencies[0], isActive: newFrequencies.count > 0)
            voices.1.snap(frequency: newFrequencies[1], isActive: newFrequencies.count > 1)
            voices.2.snap(frequency: newFrequencies[2], isActive: newFrequencies.count > 2)
            volume.snap(to: clampedVolume)
            waveform = newWaveform
            previousWaveform = newWaveform
            crossfade.snap(to: 1)
        } else {
            voices.0.glide(to: newFrequencies[0], isActive: newFrequencies.count > 0)
            voices.1.glide(to: newFrequencies[1], isActive: newFrequencies.count > 1)
            voices.2.glide(to: newFrequencies[2], isActive: newFrequencies.count > 2)
            volume.target = clampedVolume
            if newWaveform != waveform {
                previousWaveform = waveform
                waveform = newWaveform
                crossfade.snap(to: 0)
                crossfade.target = 1
            }
        }
        if !isPlaying && isSilent {
            gain.snap(to: 0)
        }
        gain.target = isPlaying ? 1 : 0
    }

    /// 振幅 1 を上限としたサンプルを返す。
    ///
    /// 和音はボイスの和をレベルの合計（鳴っているボイスの数）で割って、単音と同じ振幅 1 に収める（クリップさせない）。
    /// 合計が 1 を下回るとき（ボイスの入れ替わりの途中など）は割らないので、単音の出力は今までと同じ値になる
    mutating func nextSample() -> Float {
        let mix = crossfade.next()
        let first = voices.0.advance()
        let second = voices.1.advance()
        let third = voices.2.advance()
        let sum = first.level * waveformValue(at: first.phase, mix: mix)
            + second.level * waveformValue(at: second.phase, mix: mix)
            + third.level * waveformValue(at: third.phase, mix: mix)
        let normalized = sum / max(first.level + second.level + third.level, 1)
        let currentGain = gain.next() * volume.next()
        return Float(normalized * currentGain)
    }

    /// 切り替え前後の波形をクロスフェードした値（-1...1）
    private func waveformValue(at phase: Double, mix: Double) -> Double {
        previousWaveform.value(at: phase) * (1 - mix) + waveform.value(at: phase) * mix
    }
}
