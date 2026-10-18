//
//  ContentView.swift
//  OneTone
//
//  Created by 村石 拓海 on 2024/05/28.
//

import SwiftUI

struct ContentView: View {
    /// 縦スクロールで送り先にできる部品
    enum Section: Hashable {
        case frequency
    }

    @StateObject private var audioManager: AudioManager
    @State private var frequency: Double
    @State private var frequencyText: String
    @State private var volume: Double
    @State private var waveform: Waveform
    /// 和音モードで鳴らすコード。保存はまだしない（起動時は `ChordInput.defaultChord`）
    @State private var chord = ChordInput.defaultChord
    /// 選んだテーマ。保存値が無い・読めないときは既定のテーマ
    @AppStorage(ThemeColor.storageKey) private var storedThemeColor: ThemeColor = .default
    /// 設定画面で選んだ FREQUENCY パネルの表示モード。保存値が無い・読めないときは Hz
    @AppStorage(FrequencyMode.storageKey) private var storedFrequencyMode: FrequencyMode = .default
    private let isScreenshotDemo: Bool
    /// 周波数・音量・波形の保存先。撮影モードでは読み書きしないので nil
    private let settingsStore: ToneSettingsStore?
    #if os(iOS)
    @State private var isShowingSettings = false
    #endif
    /// チュートリアルを閉じたことがあるか。Skip / 完了 / 閉じる のどれでも立てる
    @AppStorage(Tutorial.hasSeenKey) private var hasSeenTutorial = false
    @State private var isShowingTutorial = false
    /// 起動時に保存された音量を上限まで下げたので、まだ知らせていない。チュートリアルと重なるときは閉じてから出す
    @State private var hasPendingVolumeCapNotice: Bool
    @State private var isShowingVolumeCapNotice = false
    /// 撮影モードで、開いた直後に見える位置まで送る部品
    private let initialScrollTarget: Section?

    /// - Parameter screenshotScene: スクリーンショットの撮影モードで撮る画面。渡すと、その周波数・波形・音量を初期値にし、
    ///   音を出さずに再生中の表示にする。画面を出さずに描く経路でも使えるよう、`.task` ではなく初期値で状態を作る
    /// - Parameter defaults: 周波数・音量・波形の保存先。撮影モード以外では、ここに保存した値を初期値にする
    init(screenshotScene: ScreenshotDemo.Scene? = ScreenshotDemo.scene, defaults: UserDefaults = .standard) {
        let store = ToneSettingsStore.forLaunch(screenshotScene: screenshotScene, defaults: defaults)
        let restoration = ToneSettings.initial(screenshotScene: screenshotScene, store: store)
        var initial = restoration.settings
        let launchMode = FrequencyMode.displayed(stored: FrequencyMode.stored(in: defaults), isScreenshotDemo: screenshotScene != nil)
        // 音名モードで起動するときは、保存された周波数を最寄りの半音にそろえてから鳴らす
        if launchMode == .note {
            initial.frequency = NoteInput.snapped(initial.frequency)
        }
        let manager = AudioManager.forLaunch(screenshotScene: screenshotScene, settings: initial)
        // 和音モードで起動するときは、コードの構成音を鳴らす準備をしておく
        if launchMode == .chord {
            manager.updateFrequencies(ChordInput.frequencies(of: ChordInput.defaultChord))
        }
        _audioManager = StateObject(wrappedValue: manager)
        _frequency = State(initialValue: initial.frequency)
        _frequencyText = State(initialValue: FrequencyInput.format(initial.frequency))
        _volume = State(initialValue: initial.volume)
        _waveform = State(initialValue: initial.waveform)
        settingsStore = store
        _hasPendingVolumeCapNotice = State(initialValue: restoration.volumeWasCapped)
        isScreenshotDemo = screenshotScene != nil
        initialScrollTarget = screenshotScene?.scrollTarget
    }
    
    var body: some View {
        // 幅で並べ方だけを変え、狭い画面では縦にスクロールして部品が切れないようにする
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 16) {
                        TitleView(isPlaying: audioManager.isPlaying)
                            .padding(.top)
                    
                        OscilloscopeView(isPlaying: audioManager.isPlaying, readSamples: audioManager.latestOutputSamples)
                            .frame(maxWidth: DeckLayout.panelMaxWidth * 2)
                    
                        if DeckLayout.isSideBySide(width: proxy.size.width) {
                            HStack(alignment: .top, spacing: 16) {
                                frequencyPanel
                                outputPanel
                            }
                        } else {
                            VStack(spacing: 16) {
                                outputPanel
                                frequencyPanel
                                    .id(Section.frequency)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                }
                #if os(iOS)
                // 数値入力のキーボードをスクロールで閉じられるようにする（確定は従来どおり onSubmit）
                .scrollDismissesKeyboard(.interactively)
                #endif
                .onAppear {
                    // チュートリアル用の撮影で、画面の下の方にある部品を写す
                    if let initialScrollTarget {
                        scrollProxy.scrollTo(initialScrollTarget, anchor: .top)
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            TutorialButton(action: openTutorial)
        }
        // 撮影モードではスクリーンショットの見た目を変えないよう、設定ボタンを出さない
        .overlay(alignment: .topTrailing) {
            if !isScreenshotDemo {
                settingsButton
            }
        }
        #if os(macOS)
        .frame(minWidth: DeckLayout.minimumWindowSize.width, minHeight: DeckLayout.minimumWindowSize.height)
        #endif
        .themedScreen()
        .environment(\.themeColor, ThemeColor.displayed(stored: storedThemeColor, isScreenshotDemo: isScreenshotDemo))
        // 設定画面でモードを切り替えたら、パネルと鳴らす音を切り替える（再生は止めない）。
        // 音名モードへは最寄りの半音にそろえ、和音モードへは選んでいるコードを、和音モードから出るときは単音に戻す
        .onValueChange(of: frequencyMode) { mode in
            switch mode {
            case .hertz:
                audioManager.updateFrequency(frequency)
            case .note:
                setFrequency(NoteInput.snapped(frequency))
            case .chord:
                audioManager.updateFrequencies(ChordInput.frequencies(of: chord))
            }
        }
        #if os(iOS)
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("Settings")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingSettings = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        #endif
        // シートを下へスワイプして閉じたときも、閉じる操作として既読にする
        .sheet(isPresented: $isShowingTutorial, onDismiss: {
            finishTutorial(.closed)
            // シートが閉じ切ってから出す（シートを出している間はダイアログを重ねて出せない）
            presentPendingVolumeCapNotice()
        }) {
            TutorialView(onDismiss: finishTutorial)
        }
        .alert(Text(VolumeCapNotice.title), isPresented: $isShowingVolumeCapNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(VolumeCapNotice.message)
        }
        // 設定画面（macOS は別ウィンドウ、iOS はシート）で既定値に戻したら、表示と再生中の音も戻す。再生は止めない
        .onReceive(NotificationCenter.default.publisher(for: ToneSettingsStore.didResetNotification)) { notification in
            guard let settingsStore, notification.object as? UserDefaults === settingsStore.defaults else { return }
            show(.default)
        }
        .onAppear {
            // 初回起動時だけ自動で出す（撮影モードと -skip-tutorial 付きの起動では出さない）
            if Tutorial.shouldPresentAutomatically(hasSeen: hasSeenTutorial) {
                openTutorial()
            } else {
                presentPendingVolumeCapNotice()
            }
        }
    }

    /// 起動時に音量を下げたことを 1 度だけ知らせる
    private func presentPendingVolumeCapNotice() {
        guard hasPendingVolumeCapNotice else { return }
        hasPendingVolumeCapNotice = false
        isShowingVolumeCapNotice = true
    }

    /// チュートリアルを開く。説明を聞いている間に鳴り続けないよう、メイン画面の音は止める
    private func openTutorial() {
        audioManager.stopTone()
        isShowingTutorial = true
    }

    /// チュートリアルを閉じる。閉じ方によらず既読にする（表示しただけでは既読にしない）
    private func finishTutorial(_ dismissal: TutorialDismissal) {
        if dismissal.marksAsSeen {
            hasSeenTutorial = true
        }
        isShowingTutorial = false
    }

    #if os(iOS)
    /// 設定（シート）を開くボタン。タイトルと重ならないよう画面の右上に置く
    private var settingsButton: some View {
        Button {
            isShowingSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Settings")
        .padding(.trailing, 4)
    }
    #elseif os(macOS)
    /// 設定ウィンドウ（⌘, と同じ `Settings` シーン）を開くボタン。左上の「？」と大きさ・余白をそろえて右上に置く。
    /// `SettingsLink` は macOS 14 からなので、macOS 13 では出さない（アプリのメニューの「設定…」（⌘,）から開く）
    @ViewBuilder
    private var settingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Image(systemName: "gearshape")
                    .font(.system(size: TutorialButtonLayout.iconSize, weight: .regular))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: TutorialButtonLayout.hitSize, height: TutorialButtonLayout.hitSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(TutorialButtonLayout.margin)
            .accessibilityLabel("Settings")
            .help("Settings")
        }
    }
    #endif
    
    /// 画面に使う表示モード。撮影モードでは保存値に関わらず Hz で撮る
    private var frequencyMode: FrequencyMode {
        FrequencyMode.displayed(stored: storedFrequencyMode, isScreenshotDemo: isScreenshotDemo)
    }

    /// 周波数を決める部品。選んだモードの操作だけを出す（Discussion #219 Q3）
    @ViewBuilder
    private var frequencyPanel: some View {
        switch frequencyMode {
        case .hertz:
            hertzPanel
        case .note:
            notePanel
        case .chord:
            chordPanel
        }
    }

    /// 和音で決める部品（コード名と構成音の表示・よく使うコードのパッド）。単一の周波数のノブ・スライダー・Hz の操作は出さない
    private var chordPanel: some View {
        DeckPanel(title: "FREQUENCY") {
            ChordDisplay(chord: chord)

            ChordPadButtons(chord: chord, onSelect: setChord)
        }
    }

    /// 音名で決める部品（半音にスナップするノブ・音名の表示・スライダー・音名の選択・プリセット）。Hz の数値入力とプリセットは出さない
    private var notePanel: some View {
        let note = NoteInput.note(for: frequency)
        return DeckPanel(title: "FREQUENCY") {
            FrequencyKnob(frequency: frequency, scale: .semitone, onChange: setFrequency)

            NoteDisplay(note: note)

            NoteSlider(note: note, onChange: setNote)

            NotePicker(note: note, onChange: setNote)

            NotePresetButtons(note: note, onSelect: setNote)
        }
    }

    /// 周波数を決める部品（ノブ・表示・スライダー・数値入力・プリセット）
    private var hertzPanel: some View {
        DeckPanel(title: "FREQUENCY") {
            FrequencyKnob(frequency: frequency, onChange: setFrequency)
            
            FrequencyDisplay(frequency: frequency)
            
            FrequencySlider(frequency: frequency, onChange: setFrequency)
            
            FrequencyTextField(text: $frequencyText, onSubmit: submitFrequencyText)
            
            FrequencyPresetButtons(frequency: frequency, onSelect: setFrequency)
        }
    }
    
    /// 鳴らし方を決める部品（再生／停止・音量とメーター・波形）
    private var outputPanel: some View {
        DeckPanel(title: "OUTPUT") {
            HStack(alignment: .center, spacing: 8) {
                PlaybackControls(
                    isPlaying: audioManager.isPlaying,
                    onPlay: play,
                    onStop: { audioManager.stopTone() }
                )
                .frame(maxWidth: .infinity)
                
                VolumeControl(volume: volume, onChange: setVolume)
            }
            
            LevelMeterView(isPlaying: audioManager.isPlaying, readSamples: audioManager.latestOutputSamples)
            
            WaveformPicker(waveform: waveform, onChange: setWaveform)
        }
    }
    
    /// スライダー・ノブ・数値入力・プリセットのどこから変えても、表示と入力欄と再生中の音をそろえる
    private func setFrequency(_ newFrequency: Double) {
        frequency = newFrequency
        frequencyText = FrequencyInput.format(newFrequency)
        audioManager.updateFrequency(newFrequency)
        settingsStore?.save(frequency: newFrequency)
    }
    
    private func setNote(_ note: MusicalNote) {
        setFrequency(note.frequency)
    }

    /// 再生中なら構成音へ滑らかに移る
    private func setChord(_ newChord: Chord) {
        chord = newChord
        audioManager.updateFrequencies(ChordInput.frequencies(of: newChord))
    }

    /// 和音モードではコードの構成音を、それ以外は今の周波数を鳴らす
    private func play() {
        if frequencyMode == .chord {
            audioManager.playTone(frequencies: ChordInput.frequencies(of: chord))
        } else {
            audioManager.playTone(frequency: frequency)
        }
    }

    private func setVolume(_ newVolume: Double) {
        volume = newVolume
        audioManager.updateVolume(newVolume)
        settingsStore?.save(volume: newVolume)
    }
    
    private func setWaveform(_ newWaveform: Waveform) {
        waveform = newWaveform
        audioManager.updateWaveform(newWaveform)
        settingsStore?.save(waveform: newWaveform)
    }
    
    /// 表示と音に反映する。保存はしない（既定値に戻したときは保存値を消したままにする）
    private func show(_ settings: ToneSettings) {
        frequency = settings.frequency
        frequencyText = FrequencyInput.format(settings.frequency)
        volume = settings.volume
        waveform = settings.waveform
        audioManager.apply(settings)
    }

    /// 範囲外や数値でない入力は反映せず、入力欄を現在の周波数に戻す
    private func submitFrequencyText() {
        if let newFrequency = FrequencyInput.parse(frequencyText) {
            setFrequency(newFrequency)
        } else {
            frequencyText = FrequencyInput.format(frequency)
        }
    }
}

/// 周波数の数値入力とプリセットの定義。UI から切り離してテストできるようにしている
enum FrequencyInput {
    /// 可聴域に合わせた入力可能な範囲（スライダーと同じ）
    static let range: ClosedRange<Double> = 20...20000
    /// 起動直後の周波数。聞き取りやすい基準音（A4）にする
    static let defaultFrequency: Double = 440
    static let presets: [Double] = [100, 440, 1000, 10000]

    /// 入力文字列を周波数に変換する。数値でない・範囲外の場合は nil
    static func parse(_ text: String) -> Double? {
        guard let value = Double(text.trimmingCharacters(in: .whitespaces)),
              range.contains(value) else { return nil }
        return value
    }

    /// 入力欄と表示ラベルで共通に使う表記（1Hz 単位に四捨五入）
    static func format(_ frequency: Double) -> String {
        String(Int(frequency.rounded()))
    }

    /// 今の周波数がプリセットと一致するか。表示と同じ 1Hz 単位の表記で比べるので、
    /// 表示が「440」ならスライダーで 439.7Hz にしていても 440Hz のプリセットが選択中になる
    static func isPresetSelected(_ preset: Double, frequency: Double) -> Bool {
        format(preset) == format(frequency)
    }

    /// プリセットボタンの表記。1kHz 以上は kHz で表す。単位の付け方は言語ごとの書式（catalog）に任せる
    static func presetLabel(_ frequency: Double) -> String {
        if frequency >= 1000 {
            return String(localized: "\(format(frequency / 1000)) kHz")
        }
        return String(localized: "\(format(frequency)) Hz")
    }
}

extension View {
    /// 値が変わったときに呼ぶ。`onChange(of:)` は iOS 17 / macOS 14 で引数が変わったので、macOS 13 と両方で警告なく使えるよう分ける
    @ViewBuilder
    func onValueChange<Value: Equatable>(of value: Value, perform action: @escaping (Value) -> Void) -> some View {
        if #available(iOS 17.0, macOS 14.0, *) {
            onChange(of: value) { _, newValue in action(newValue) }
        } else {
            onChange(of: value, perform: action)
        }
    }
}

#Preview("iPhone の幅") {
    ContentView()
        .frame(width: 390, height: 844)
}

#Preview("広い画面") {
    ContentView()
        .frame(width: 1024, height: 768)
}
