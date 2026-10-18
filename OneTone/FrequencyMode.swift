//
//  FrequencyMode.swift
//  OneTone
//

import Foundation

/// メイン画面の FREQUENCY パネルで音を指定する方法。設定画面で選ぶと、パネルは選んだモードの操作だけに切り替わる（Discussion #219 Q3）。
/// rawValue は保存値になるので、一度入れたら変えない
enum FrequencyMode: String, CaseIterable, Identifiable {
    /// 周波数（Hz）で指定する。今までの操作
    case hertz
    /// 音名（`A4` / `C#5`）で 1 音を指定する
    case note
    /// 和音（`C` / `Am`）で構成音を同時に鳴らす
    case chord

    var id: Self { self }

    /// 選んだモードを保存する UserDefaults のキー（`@AppStorage`）。端末ごとに保存し、iCloud では同期しない。
    /// 保存値になるので、リリース後に変えると既存ユーザーの選択が失われる
    static let storageKey = "frequencyMode"
    /// 保存値が無いときのモード。既存ユーザーの見た目を変えないよう Hz にする
    static let `default`: FrequencyMode = .hertz

    /// 保存されたモード。保存値が無い・読めないときは既定（Hz）。`@AppStorage` を使えない起動時の初期化で読む
    static func stored(in defaults: UserDefaults) -> FrequencyMode {
        defaults.string(forKey: storageKey).flatMap(FrequencyMode.init(rawValue:)) ?? .default
    }

    /// 画面に使うモード。スクリーンショットの撮影モードでは、保存値に関わらず既定（Hz）で撮る
    static func displayed(stored: FrequencyMode, isScreenshotDemo: Bool) -> FrequencyMode {
        isScreenshotDemo ? .default : stored
    }

    /// 設定画面のボタンの名前。大文字のラベルとして全言語で英語のまま出す（`Hz` は単位、`NOTE` / `CHORD` は `PLAY` などと同じ扱い）ので `String` のままにしている
    var label: String {
        switch self {
        case .hertz: return "Hz"
        case .note: return "NOTE"
        case .chord: return "CHORD"
        }
    }

    /// 設定画面でボタンの下に出す説明（訳す）
    var summary: LocalizedStringResource {
        switch self {
        case .hertz: return "Set the tone by its frequency in hertz."
        case .note: return "Pick a single note such as A4. The knob and slider move in semitones."
        case .chord: return "Play a major or minor chord such as C or Am."
        }
    }
}
