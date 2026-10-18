//
//  ScreenshotDemo.swift
//  OneTone
//

import SwiftUI
#if os(macOS)
import AppKit
import ImageIO
import UniformTypeIdentifiers
#endif

/// App Store 用スクリーンショットの撮影モード。
///
/// 起動引数 `-screenshot-demo` で有効になり、`-screenshot-scene <名前>` で撮る画面（周波数と波形の組み合わせ）を選ぶ。
/// 撮影は `Tools/capture_screenshots.sh`（iOS Simulator）と `Tools/capture_mac_screenshots.sh`（macOS）が、
/// 画面ごとにアプリを起動し直して行う。撮る画面の並び順と出力ファイル名は `AppStore/screenshots.json` で決める。
///
/// 撮影モードでは音を出さず、表示だけを「再生中」にする（`AudioManager.presentAsPlaying`）。
/// また、撮影スクリプトは「連続で撮った 2 枚が一致するまで待つ」ので、タイトルの色相の回転や発光のゆらぎのような
/// 止まらないアニメーションは `\.freezesAnimations` で止める。
///
/// macOS では `-screenshot-output <PNG のパス>` も渡すと、画面に出さないウィンドウで画面を描いて PNG に保存し、すぐ終了する。
/// CI のランナーにはディスプレイが無くウィンドウが作られないため、ウィンドウの撮影（screencapture）は使えない
enum ScreenshotDemo {
    /// 撮る画面。`rawValue` が `-screenshot-scene` に渡す名前。
    /// App Store 用は `AppStore/screenshots.json` の scene と、チュートリアル用は `Tools/capture_tutorial_screenshots.sh` の一覧と一致させる
    enum Scene: String, CaseIterable {
        /// 440 Hz（A4）のサイン波を再生中
        case sine
        /// 1 kHz の矩形波を再生中
        case square
        /// 100 Hz のノコギリ波を再生中
        case sawtooth
        /// 音名モードで C5 の三角波を再生中（C5 のプリセットが選択中に見える）
        case note
        /// 和音モードで Am（A4 / C5 / E5）のサイン波を再生中
        case chord
        /// チュートリアルの Welcome。440 Hz のサイン波を再生中の画面全体
        case tutorialWelcome = "tutorial-welcome"
        /// チュートリアルの Play / Stop。1 kHz の矩形波を再生中（オシロスコープとレベルメーターが動いて見える）
        case tutorialPlayback = "tutorial-playback"
        /// チュートリアルの Frequency。Welcome と違う見た目になるよう、プリセットの 1 kHz を選んだ状態で、周波数のパネルが見える位置まで送る
        case tutorialFrequency = "tutorial-frequency"
        /// チュートリアルの Volume。音量を下げた状態
        case tutorialVolume = "tutorial-volume"
        /// チュートリアルの Waveform。App Store 用の Hz モードの画面で使っていない三角波
        case tutorialWaveform = "tutorial-waveform"

        /// App Store 用の画面（`AppStore/screenshots.json` に載せるもの）
        static let appStoreScenes: [Scene] = [.sine, .square, .sawtooth, .note, .chord]

        var frequency: Double {
            switch self {
            case .sine, .chord, .tutorialWelcome, .tutorialVolume: return 440
            case .square, .tutorialPlayback, .tutorialFrequency: return 1000
            case .sawtooth: return 100
            case .note: return NoteInput.note(.c, octave: 5).frequency
            case .tutorialWaveform: return 220
            }
        }

        var waveform: Waveform {
            switch self {
            case .sine, .chord, .tutorialWelcome, .tutorialFrequency, .tutorialVolume: return .sine
            case .square, .tutorialPlayback: return .square
            case .sawtooth: return .sawtooth
            case .note, .tutorialWaveform: return .triangle
            }
        }

        /// FREQUENCY パネルの表示モード。撮影モードでは保存値ではなくこれを使う
        var frequencyMode: FrequencyMode {
            switch self {
            case .note: return .note
            case .chord: return .chord
            default: return .hertz
            }
        }

        /// 和音モードで鳴らすコード。和音モード以外のシーンでは既定（C）のまま
        var chord: Chord {
            switch self {
            case .chord: return Chord(root: .a, quality: .minor)
            default: return ChordInput.defaultChord
            }
        }

        /// 撮る画面の音の設定
        var settings: ToneSettings {
            ToneSettings(frequency: frequency, volume: volume, waveform: waveform, chord: chord)
        }

        /// 音量。レベルメーターが上の方まで点いて見えるよう、既定の 50% より高くする。
        /// 音量のページだけは「下げた」状態に見えるよう低くする
        var volume: Double {
            switch self {
            case .tutorialVolume: return 0.3
            default: return 0.8
            }
        }

        /// 縦積みの画面（iPhone）で、開いた直後に見える位置まで送る部品。nil なら先頭のまま。
        /// 縦積みでは FREQUENCY パネルが OUTPUT パネルの下にあるので、音名・和音モードの画面はそこまで送らないとパネルが写らない
        var scrollTarget: ContentView.Section? {
            switch self {
            case .tutorialFrequency, .note, .chord: return .frequency
            default: return nil
            }
        }
    }

    /// 撮影モードにする起動引数
    static let launchArgument = "-screenshot-demo"

    static let isEnabled = ProcessInfo.processInfo.arguments.contains(launchArgument)

    /// 撮る画面。撮影モードでないときは nil
    static let scene: Scene? = isEnabled ? scene(from: ProcessInfo.processInfo.arguments) : nil

    /// 起動引数から撮る画面を読む。指定が無い・知らない名前のときは最初の画面にする
    static func scene(from arguments: [String]) -> Scene {
        argument("-screenshot-scene", in: arguments).flatMap(Scene.init(rawValue:)) ?? Scene.allCases[0]
    }

    /// `-名前 値` の形の起動引数の値。無ければ nil
    static func argument(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    #if os(macOS)
    /// 描き出す画面の大きさ（pt）。2 枚のパネルが横に並ぶ幅（`DeckLayout.sideBySideMinWidth` 以上）で、
    /// 2 倍で描くと 2560x1600 px になり、撮影スクリプトが 2880x1800 のキャンバスに合成する
    static let renderSize = CGSize(width: 1280, height: 800)
    /// Retina 相当の 2 倍で描く。ディスプレイの有無や倍率によらず、手元と CI で同じ寸法になる
    static let renderScale: CGFloat = 2

    /// `-screenshot-output` で指定された保存先。撮影モードでないか、指定が無ければ nil（ふだんどおりウィンドウを出す）
    static let outputURL: URL? = isEnabled
        ? argument("-screenshot-output", in: ProcessInfo.processInfo.arguments).map { URL(fileURLWithPath: $0) }
        : nil

    /// 保存先が指定されていれば、画面を PNG に描き出して終了する。`OneToneApp.init` から呼ぶ。
    ///
    /// `ImageRenderer` は macOS の `ScrollView` / `Slider` / `TextField`（AppKit 製）を描けないので、
    /// `NSHostingView` を画面外のウィンドウに載せて `cacheDisplay(in:to:)` でビットマップに描く。
    /// ウィンドウは画面に出さないため、ディスプレイの無い CI のランナーでも描ける
    @MainActor
    static func renderIfRequested() {
        guard let scene, let outputURL else { return }
        _ = NSApplication.shared
        let content = ContentView(screenshotScene: scene)
            .environment(\.freezesAnimations, true)
            .frame(width: renderSize.width, height: renderSize.height)
        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(origin: .zero, size: renderSize)
        // 画面外に置いたウィンドウに載せる。ウィンドウが無いと SwiftUI がレイアウト・描画を進めない
        let window = NSWindow(
            contentRect: NSRect(x: -100_000, y: -100_000, width: renderSize.width, height: renderSize.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        hostingView.layoutSubtreeIfNeeded()
        // 初回のレイアウトと描画（TimelineView の最初のフレームなど）が済むまで少し回す
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
        hostingView.layoutSubtreeIfNeeded()

        let pixelWidth = Int(renderSize.width * renderScale)
        let pixelHeight = Int(renderSize.height * renderScale)
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            FileHandle.standardError.write(Data("ビットマップを作れませんでした\n".utf8))
            exit(1)
        }
        // ビットマップのピクセル数と pt の大きさを分けて、2 倍で描かせる
        bitmap.size = renderSize
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let image = bitmap.cgImage else {
            FileHandle.standardError.write(Data("画面を描けませんでした\n".utf8))
            exit(1)
        }
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            FileHandle.standardError.write(Data("\(outputURL.path) を作れませんでした\n".utf8))
            exit(1)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            FileHandle.standardError.write(Data("\(outputURL.path) を保存できませんでした\n".utf8))
            exit(1)
        }
        print("\(outputURL.path)  \(image.width)x\(image.height)")
        exit(0)
    }
    #endif
}

extension AudioManager {
    /// 撮影モードなら、音を出さずに再生中の表示にした `AudioManager` を返す。そうでなければふだんどおり
    static func forScreenshot(_ scene: ScreenshotDemo.Scene?) -> AudioManager {
        guard let scene else { return AudioManager() }
        // 音を出さないので AVAudioEngine は動かさない（動いていると presentAsPlaying の波形が無音で上書きされる）
        let manager = AudioManager(startsEngine: false)
        // 和音モードのシーンはコードの構成音を、それ以外は周波数の単音を鳴らしている表示にする
        manager.presentAsPlaying(frequencies: scene.settings.frequencies(for: scene.frequencyMode), volume: scene.volume, waveform: scene.waveform)
        return manager
    }
}

private struct FreezesAnimationsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 止まらないアニメーション（色相の回転・発光のゆらぎ・波形やメーターの更新）を止めて、画面を静止させる。
    /// スクリーンショットの撮影モードで `OneToneApp` が立てる。各部品では Reduce Motion と同じように扱う
    var freezesAnimations: Bool {
        get { self[FreezesAnimationsKey.self] }
        set { self[FreezesAnimationsKey.self] = newValue }
    }
}
