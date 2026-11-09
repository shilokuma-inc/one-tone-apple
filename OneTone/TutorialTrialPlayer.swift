//
//  TutorialTrialPlayer.swift
//  OneTone
//

import Foundation

/// チュートリアルの中で音を試す。メイン画面とは別の `AudioManager` で鳴らすので、
/// メイン画面の周波数・音量・波形と再生状態は変わらない。
///
/// 耳やスピーカーを傷めないよう低めの音量（`volume`）で鳴らし、`duration` 秒たつと自動で止める。
/// 別の音を試すと前の音は止まり、鳴っている音をもう一度押すと止まる
final class TutorialTrialPlayer: ObservableObject {
    /// 試聴の 1 つ分。周波数と波形の組み合わせ
    struct Sound: Hashable {
        let frequency: Double
        let waveform: Waveform
    }

    /// 試聴の音量（0...1）。メイン画面の既定（50%）よりはっきり低くする
    static let volume: Double = 0.2
    /// 試聴を鳴らす秒数
    static let duration: TimeInterval = 3

    /// 今鳴っている音。鳴っていなければ nil
    @Published private(set) var playing: Sound?

    private let duration: TimeInterval
    private let makeAudioManager: () -> AudioManager
    /// 試聴を押すまで AVAudioEngine を作らない（チュートリアルを開いただけでは音の準備をしない）
    private lazy var audioManager = makeAudioManager()
    private var scheduledStop: DispatchWorkItem?

    /// - Parameters:
    ///   - duration: 自動で止めるまでの秒数。テストで短くする
    ///   - makeAudioManager: 鳴らすのに使う `AudioManager` を作る。テストでは音を出さない `init(startsEngine: false)` を渡す
    init(duration: TimeInterval = TutorialTrialPlayer.duration, makeAudioManager: @escaping () -> AudioManager = { AudioManager() }) {
        self.duration = duration
        self.makeAudioManager = makeAudioManager
    }

    deinit {
        scheduledStop?.cancel()
    }

    /// 鳴っている音なら止め、そうでなければ（前の音を止めてから）鳴らす
    func toggle(_ sound: Sound) {
        if playing == sound {
            stop()
        } else {
            play(sound)
        }
    }

    func play(_ sound: Sound) {
        stop()
        audioManager.updateVolume(Self.volume)
        audioManager.updateWaveform(sound.waveform)
        audioManager.playTone(frequency: sound.frequency)
        playing = sound

        let stopWork = DispatchWorkItem { [weak self] in
            self?.stop()
        }
        scheduledStop = stopWork
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: stopWork)
    }

    /// 鳴っていなければ何もしない
    func stop() {
        scheduledStop?.cancel()
        scheduledStop = nil
        guard playing != nil else { return }
        audioManager.stopTone()
        playing = nil
    }

    /// 試聴を鳴らしている `AudioManager` の状態（テスト用）
    var isAudioPlaying: Bool { playing != nil && audioManager.isPlaying }
}

extension TutorialTrial {
    /// このページで試せる音。周波数ページは 1 つ、波形ページは波形ごとに 1 つ
    var sounds: [TutorialTrialPlayer.Sound] {
        switch self {
        case .tone(let frequency):
            return [TutorialTrialPlayer.Sound(frequency: frequency, waveform: .sine)]
        case .waveforms(let frequency):
            return Waveform.allCases.map { TutorialTrialPlayer.Sound(frequency: frequency, waveform: $0) }
        }
    }
}
