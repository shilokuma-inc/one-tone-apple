//
//  Tutorial.swift
//  OneTone
//

import Foundation

/// チュートリアルの 1 ページ。文言・画像・試聴の有無をデータとして持ち、表示（`TutorialView`）から切り離してテストできるようにしている。
/// 文言は表示するときに端末の言語へ訳す（`LocalizedStringResource`）。テストは訳ではなくキー（英語の原文）で比べる
struct TutorialPage: Identifiable, Equatable {
    enum ID: String, CaseIterable {
        case welcome
        case playback
        case frequency
        case volume
        case waveform
        case note
        case chord
    }

    let id: ID
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    /// 本文の下に目立たせて出す注意書き。無ければ nil
    let caution: LocalizedStringResource?
    /// ページで試せる音。無ければ nil
    let trial: TutorialTrial?

    /// ページの画像（実際の画面のスクリーンショット）のアセット名。macOS / iOS の出し分けは画像セットの側で行う
    var imageName: String { "Tutorial-\(id.rawValue)" }

    /// 画像をまだ撮っていない（画像セットが無い）ページで、代わりに出す SF Symbols の名前。
    /// `Tools/capture_tutorial_screenshots.sh` で撮ると画像セットができ、コードを変えずに画像へ替わる
    var placeholderSymbol: String {
        switch id {
        case .note: return "music.note"
        case .chord: return "pianokeys"
        case .welcome, .playback, .frequency, .volume, .waveform: return "waveform"
        }
    }
}

/// チュートリアルの中で試せる音
enum TutorialTrial: Equatable {
    /// 指定した周波数のサイン波
    case tone(frequency: Double)
    /// 波形ごとに同じ周波数で鳴らし比べる
    case waveforms(frequency: Double)
}

enum Tutorial {
    /// 既読フラグの `UserDefaults` のキー。`@AppStorage` でも同じキーを使う
    static let hasSeenKey = "hasSeenTutorial"
    /// UI テストなどでチュートリアルを自動表示させないための起動引数
    static let skipArgument = "-skip-tutorial"

    static let pages: [TutorialPage] = [
        TutorialPage(
            id: .welcome,
            title: "Welcome to One Tone",
            message: "One Tone plays a single tone at the exact frequency you choose. Use it to test speakers and headphones, tune instruments, or explore how sound works.",
            caution: nil,
            trial: nil
        ),
        TutorialPage(
            id: .playback,
            title: "Play and Stop",
            message: "Press Play to start the tone and Stop to end it. While it plays, the oscilloscope and the level meter show the sound that is actually being output.",
            caution: nil,
            trial: nil
        ),
        TutorialPage(
            id: .frequency,
            title: "Choose a Frequency",
            message: "Set any frequency from 20 Hz to 20 kHz. Turn the knob, drag the slider, type a number, or tap a preset: 100 Hz, 440 Hz, 1 kHz, or 10 kHz.",
            caution: nil,
            trial: .tone(frequency: 440)
        ),
        TutorialPage(
            id: .volume,
            title: "Adjust the Volume",
            message: "Use the volume control to set how loud the tone is. Start low and turn it up gradually.",
            caution: "Loud sounds and high frequencies can damage your hearing and your speakers.",
            trial: nil
        ),
        TutorialPage(
            id: .waveform,
            title: "Pick a Waveform",
            message: "Sine is a pure, smooth tone. Square sounds hollow and buzzy, Triangle is soft and mellow, and Sawtooth is bright and sharp.",
            caution: nil,
            trial: .waveforms(frequency: 440)
        ),
        TutorialPage(
            id: .note,
            title: "Play by Note Name",
            message: "In Settings, set FREQUENCY MODE to NOTE to choose a note such as A4 or C#5 instead of a frequency. The knob and slider move in semitones, so you always hear the exact pitch.",
            caution: nil,
            trial: nil
        ),
        TutorialPage(
            id: .chord,
            title: "Play a Chord",
            message: "Set FREQUENCY MODE to CHORD to play three notes at once. Tap a pad such as C, G, or Am, or combine a root from C to B with Major or Minor.",
            caution: nil,
            trial: nil
        ),
    ]

    /// 起動時にチュートリアルを自動で出すか。初回（未読）のときだけ出し、撮影モードと `-skip-tutorial` 付きの起動では出さない
    static func shouldPresentAutomatically(hasSeen: Bool, arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        guard !hasSeen else { return false }
        // App Store 用スクリーンショットに写り込まないようにする
        if arguments.contains(ScreenshotDemo.launchArgument) { return false }
        if arguments.contains(skipArgument) { return false }
        return true
    }
}

/// チュートリアルの閉じ方。どの閉じ方でも既読にする
enum TutorialDismissal: Equatable {
    /// Skip を押した
    case skipped
    /// 最後のページで完了を押した
    case completed
    /// 閉じる操作（閉じるボタン・Esc・下へのスワイプなど）
    case closed

    var marksAsSeen: Bool { true }
}

/// 既読フラグの読み書き。テストでは専用の suite の `UserDefaults` を渡す
struct TutorialSeenStore {
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasSeen: Bool { defaults.bool(forKey: Tutorial.hasSeenKey) }

    func record(_ dismissal: TutorialDismissal) {
        guard dismissal.marksAsSeen else { return }
        defaults.set(true, forKey: Tutorial.hasSeenKey)
    }
}

/// ページ送り。macOS の Back / Next ボタンとページインジケーターで使う
struct TutorialPager: Equatable {
    let pageCount: Int
    private(set) var index = 0

    init(pageCount: Int = Tutorial.pages.count) {
        precondition(pageCount > 0, "ページが 1 つも無い")
        self.pageCount = pageCount
    }

    var isFirstPage: Bool { index == 0 }
    var isLastPage: Bool { index == pageCount - 1 }

    /// 範囲外の値は端に寄せる（iOS のスワイプで直接ページが変わる場合にも使う）
    mutating func show(_ newIndex: Int) {
        index = min(max(newIndex, 0), pageCount - 1)
    }

    mutating func next() { show(index + 1) }
    mutating func back() { show(index - 1) }
}
