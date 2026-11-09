//
//  ToneSettings.swift
//  OneTone
//

import Foundation

/// 再起動後も保持する音の設定（周波数・音量・波形・和音モードのコード）。再生状態は持たない（起動時は常に停止状態）。
/// 音名モードで選んだ音は周波数として持つ（音名モードでは周波数を常に半音にそろえている）
struct ToneSettings: Equatable {
    var frequency: Double
    /// 0...1
    var volume: Double
    var waveform: Waveform
    /// 和音モードで選んだコード
    var chord: Chord = ChordInput.defaultChord

    /// 保存値が無い・読めないときの値（440Hz / 50% / Sine / C）
    static let `default` = ToneSettings(frequency: FrequencyInput.defaultFrequency, volume: 0.5, waveform: .sine)
    static let volumeRange: ClosedRange<Double> = 0...1
    /// 起動時に復元する音量の上限。保存値がこれを超えていたら、大音量で鳴らないようここまで下げる（ちょうどの値は下げない）
    static let maximumRestoredVolume = 0.2

    /// 起動時の初期値。撮影モードではシーンの値を使い、保存値は読まない（撮影画像が実行環境の保存値で変わらないように）
    static func initial(screenshotScene: ScreenshotDemo.Scene?, store: ToneSettingsStore?) -> ToneSettingsRestoration {
        if let screenshotScene {
            return ToneSettingsRestoration(settings: screenshotScene.settings, volumeWasCapped: false)
        }
        return store?.restore() ?? ToneSettingsRestoration(settings: .default, volumeWasCapped: false)
    }

    /// 表示モードに合わせて整えた設定。音名モードでは周波数を最寄りの半音にそろえる（起動時・モードを切り替えたとき）。
    /// Hz・和音モードでは周波数をそのまま残す（音名 → Hz では周波数を引き継ぐ）
    func prepared(for mode: FrequencyMode) -> ToneSettings {
        guard mode == .note else { return self }
        var settings = self
        settings.frequency = NoteInput.snapped(frequency)
        return settings
    }

    /// 表示モードで鳴らす周波数。和音モードはコードの構成音、それ以外は周波数の単音
    func frequencies(for mode: FrequencyMode) -> ToneFrequencies {
        switch mode {
        case .hertz, .note:
            return ToneFrequencies(frequency)
        case .chord:
            return ChordInput.frequencies(of: chord)
        }
    }
}

/// 起動時に復元した設定と、音量を上限まで下げたかどうか（下げたらメイン画面がダイアログで知らせる）
struct ToneSettingsRestoration: Equatable {
    let settings: ToneSettings
    let volumeWasCapped: Bool
}

/// 復元時に音量を下げたことを知らせるダイアログの文言
enum VolumeCapNotice {
    static let title: LocalizedStringResource = "Volume Lowered"

    static var message: LocalizedStringResource {
        "To prevent a sudden loud sound, the volume was lowered to \(percent)%."
    }

    static var percent: Int {
        Int((ToneSettings.maximumRestoredVolume * 100).rounded())
    }
}

/// 設定画面で既定値に戻す前の確認ダイアログの文言
enum ToneSettingsResetConfirmation {
    static let title: LocalizedStringResource = "Reset to Defaults?"

    /// 既定値は定数から作る（440Hz / 50% / Sine / Hz）。波形名・モード名は訳さないので `String` のまま埋め込む
    static var message: LocalizedStringResource {
        let settings = ToneSettings.default
        let frequency = FrequencyInput.format(settings.frequency)
        let percent = Int((settings.volume * 100).rounded())
        let waveform = settings.waveform.displayName
        let mode = FrequencyMode.default.label
        return "Frequency, volume, and waveform will return to \(frequency) Hz, \(percent)%, and \(waveform), and the frequency mode to \(mode)."
    }
}

/// 音の設定の読み書き（`UserDefaults` に端末内だけで保存し、iCloud では同期しない）。テストでは専用の suite の `UserDefaults` を渡す
struct ToneSettingsStore {
    static let frequencyKey = "toneFrequency"
    static let volumeKey = "toneVolume"
    static let waveformKey = "toneWaveform"
    /// 和音モードで選んだコードの根音（`PitchClass` の RawValue、0〜11）と種類（`ChordQuality` の RawValue）
    static let chordRootKey = "toneChordRoot"
    static let chordQualityKey = "toneChordQuality"
    /// 設定画面で既定値に戻したときに送る通知。`object` は保存先の `UserDefaults`
    static let didResetNotification = Notification.Name("ToneSettingsStore.didReset")

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 起動時に使うストア。撮影モードでは読み書きしないので nil
    static func forLaunch(screenshotScene: ScreenshotDemo.Scene?, defaults: UserDefaults = .standard) -> ToneSettingsStore? {
        screenshotScene == nil ? ToneSettingsStore(defaults: defaults) : nil
    }

    /// 保存値を読む。項目ごとに、保存値が無い・型が違う・範囲外なら既定値にする
    func load() -> ToneSettings {
        let fallback = ToneSettings.default
        return ToneSettings(
            frequency: storedDouble(forKey: Self.frequencyKey, in: FrequencyInput.range) ?? fallback.frequency,
            volume: storedDouble(forKey: Self.volumeKey, in: ToneSettings.volumeRange) ?? fallback.volume,
            waveform: storedWaveform() ?? fallback.waveform,
            chord: storedChord() ?? fallback.chord
        )
    }

    /// 起動時の復元。保存された音量が上限を超えていたら上限まで下げ、下げた値を保存し直す。
    /// 保存値が無い・壊れていて既定値（50%）になったときは、保存された音量ではないので下げない
    func restore() -> ToneSettingsRestoration {
        var settings = load()
        guard let storedVolume = storedDouble(forKey: Self.volumeKey, in: ToneSettings.volumeRange),
              storedVolume > ToneSettings.maximumRestoredVolume else {
            return ToneSettingsRestoration(settings: settings, volumeWasCapped: false)
        }
        settings.volume = ToneSettings.maximumRestoredVolume
        save(volume: settings.volume)
        return ToneSettingsRestoration(settings: settings, volumeWasCapped: true)
    }

    /// 既定値に戻す。表示モード（`FrequencyMode`）も含め、保存値を消して既定値で起動するようにし（既定の 50% は保存された音量ではないので、次の起動で 20% に下げない）、
    /// 開いているメイン画面に表示と再生中の音を戻すよう知らせる
    func reset() {
        // 表示モードは設定画面・メイン画面の `@AppStorage` が見ているので、消すと開いている画面もすぐ Hz に戻る
        for key in [Self.frequencyKey, Self.volumeKey, Self.waveformKey, Self.chordRootKey, Self.chordQualityKey, FrequencyMode.storageKey] {
            defaults.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: Self.didResetNotification, object: defaults)
    }

    func save(frequency: Double) {
        defaults.set(frequency, forKey: Self.frequencyKey)
    }

    func save(volume: Double) {
        defaults.set(volume, forKey: Self.volumeKey)
    }

    /// `Waveform` の RawValue（`UInt8`）をそのまま数値で保存する
    func save(waveform: Waveform) {
        defaults.set(Int(waveform.rawValue), forKey: Self.waveformKey)
    }

    /// 根音と種類を別々に保存する。保存値は変えない約束の RawValue（根音は 0〜11 の数値、種類は `major` / `minor`）
    func save(chord: Chord) {
        defaults.set(chord.root.rawValue, forKey: Self.chordRootKey)
        defaults.set(chord.quality.rawValue, forKey: Self.chordQualityKey)
    }

    /// 根音と種類のどちらかが無い・読めないときは nil（既定のコードにする）
    private func storedChord() -> Chord? {
        guard let number = defaults.object(forKey: Self.chordRootKey) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let rawRoot = Int(exactly: number.doubleValue),
              let root = PitchClass(rawValue: rawRoot),
              let rawQuality = defaults.object(forKey: Self.chordQualityKey) as? String,
              let quality = ChordQuality(rawValue: rawQuality) else { return nil }
        return Chord(root: root, quality: quality)
    }

    /// 文字列などの別の型で入っているものは読まない（`double(forKey:)` は文字列も数値に変換してしまう）
    private func storedDouble(forKey key: String, in range: ClosedRange<Double>) -> Double? {
        guard let number = defaults.object(forKey: key) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        return range.contains(value) ? value : nil
    }

    private func storedWaveform() -> Waveform? {
        guard let number = defaults.object(forKey: Self.waveformKey) as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              let rawValue = UInt8(exactly: number.doubleValue) else { return nil }
        return Waveform(rawValue: rawValue)
    }
}

extension AudioManager {
    /// メイン画面の `AudioManager`。撮影モードは音を出さずに表示だけ再生中にし、それ以外は復元した設定を反映した停止状態で作る
    static func forLaunch(screenshotScene: ScreenshotDemo.Scene?, settings: ToneSettings) -> AudioManager {
        guard screenshotScene == nil else { return forScreenshot(screenshotScene) }
        let manager = AudioManager()
        manager.apply(settings)
        return manager
    }

    /// 周波数・音量・波形をまとめて反映する。再生状態は変えない
    func apply(_ settings: ToneSettings) {
        updateFrequency(settings.frequency)
        updateVolume(settings.volume)
        updateWaveform(settings.waveform)
    }
}
