//
//  TitleView.swift
//  OneTone
//

import CoreText
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// メイン画面の上の大きいロゴ（アイコンのマーク＋「One Tone」。`LogoLockup`）。再生中だけ動き、停止中は静か（マークはアイコンと同じ形）。
/// 再生中は、マークの 5 本のバーが鳴っている音に合わせて伸び縮みし（`LogoMarkMotion`）、文字の色相が選んだ色の周りで
/// ±`Theme.titleHueSwingAmplitude` 度だけ揺れ、発光する。Reduce Motion がオンのとき、またはスクリーンショットの撮影モードのときは動かさない。
/// 大きさは `Theme.Logo.largeTextSizes` から、幅に収まる最大のものを選ぶ
struct TitleView: View {
    let isPlaying: Bool
    /// 鳴っている音。バーの動きの速さ・深さ・形を決める
    var sound: LogoSound = .default
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.freezesAnimations) private var freezesAnimations
    /// 動いていた時間だけを数える時計。止めている間の時間を含めず、再開したとき色やバーが飛ばないようにする
    @State private var clock = PausableClock()
    /// バーの動きの位相。周波数を変えて速さが変わっても、長さが飛ばないように積み上げる
    @State private var phase = PhaseAccumulator()

    /// 動かすか。再生中かつ Reduce Motion がオフで、撮影モードでもないときだけ動かす
    private var isAnimating: Bool {
        isPlaying && !reduceMotion && !freezesAnimations
    }

    var body: some View {
        // 幅に収まる大きさを選ぶ処理は時刻に依らないので、TimelineView の外に置く（毎フレーム候補を組み直さない）
        ViewThatFits(in: .horizontal) {
            ForEach(Theme.Logo.largeTextSizes, id: \.self) { size in
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isAnimating)) { context in
                    let elapsed = clock.elapsed(at: context.date)
                    LogoLockup(
                        textSize: size,
                        barScales: LogoMarkMotion.barScales(
                            phase: phase.phase(at: elapsed),
                            sound: sound,
                            isAnimating: isAnimating
                        ),
                        hueDegrees: Self.hueDegrees(at: elapsed)
                    )
                }
            }
        }
        .neonGlow(Theme.accentSecondary, isActive: isPlaying)
        // 表示時と、動かす／止めるが切り替わるたびに時計を動かす・止める
        // （2 引数の onChange は macOS 14 からなので、表示時にも呼ばれる task(id:) を使う）
        .task(id: isAnimating) {
            if isAnimating {
                clock.start(at: Date())
            } else {
                clock.stop(at: Date())
            }
        }
        // 周波数が変わったら、その時点の位相から新しい速さで進める
        .task(id: LogoMarkMotion.baseRate(for: sound.frequencies)) {
            phase.setRate(LogoMarkMotion.baseRate(for: sound.frequencies), at: clock.elapsed(at: Date()))
        }
        // マークは読み上げから外してあるので、読まれるのは文字の「One Tone」だけ。それを見出しにする
        .accessibilityAddTraits(.isHeader)
    }

    /// 揺れていた時間（秒）に対する色相のずらし角（-振幅...+振幅）。
    /// 0 秒では 0°（選んだ色のまま）から始まり、正弦波で `Theme.titleHueSwingPeriod` 秒ごとに 1 往復する。
    /// 端で速度が 0 になるので、折り返しでカクつかない
    static func hueDegrees(at time: TimeInterval) -> Double {
        Theme.titleHueSwingAmplitude * sin(2 * .pi * time / Theme.titleHueSwingPeriod)
    }
}

/// ロゴ（アイコンのマーク＋「One Tone」の文字）。マークが左、文字が右の横組みで、大きさは文字の大きさ `textSize` で決まる。
/// メイン画面の大きいロゴ（`TitleView`）と、バーに出す小さいロゴで共有する。動きは持たない（演出は使う側で掛ける）。
/// 文字は選んだテーマの `titleGradient`、マークは既定のアプリアイコンと同じく白い線に中央のバーだけテーマの差し色（判断ログ #265）。
/// 読み上げは文字の「One Tone」の 1 回だけ（マークは `accessibilityHidden`）
struct LogoLockup: View {
    /// 文字の大きさ（pt）
    let textSize: CGFloat
    /// 5 本のバーのアイコンに対する長さの比（左から）。既定はアイコンの形
    var barScales: [CGFloat] = LogoMarkMotion.restingScales
    /// 色相のずらし角（度）。ロゴ全体（文字とマークの中央のバー。白い線は変わらない）に掛かる
    var hueDegrees: Double = 0
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        HStack(spacing: textSize * Theme.Logo.spacingRatio) {
            LogoMark(
                height: textSize * Theme.Logo.markHeightRatio,
                line: Theme.textPrimary,
                accent: themeColor.accent,
                barScales: barScales
            )
            Text(verbatim: "One Tone")
                .font(LogoFont.font(size: textSize))
                .foregroundStyle(
                    LinearGradient(colors: themeColor.titleGradient, startPoint: .leading, endPoint: .trailing)
                )
                .lineLimit(1)
                .fixedSize()
        }
        .hueRotation(Angle(degrees: hueDegrees))
    }
}

/// アプリアイコンの図柄（半円＋5 本のバー）だけを、背景の四角を除いて描くマーク。寸法は `AppIconDesign.Geometry` のまま使い、ロゴ用の数値を持たない
struct LogoMark: View {
    /// マークの高さ（pt）。幅は図柄の縦横比から決まる
    let height: CGFloat
    /// 半円と両側のバーの色
    let line: Color
    /// 中央のバーの色
    let accent: Color
    /// 5 本のバーのアイコンに対する長さの比（左から）。バーは水平線を中心に伸び縮みする。既定はアイコンの形
    var barScales: [CGFloat] = LogoMarkMotion.restingScales

    /// 図柄の幅 / 高さ
    static let aspectRatio = AppIconDesign.Geometry.markBounds.width / AppIconDesign.Geometry.markBounds.height

    var body: some View {
        Canvas { context, size in
            let bounds = AppIconDesign.Geometry.markBounds
            // アイコンの座標（一辺 1・y が下向き）の図柄の外接矩形を、Canvas いっぱいに広げる
            context.scaleBy(x: size.width / bounds.width, y: size.height / bounds.height)
            context.translateBy(x: -bounds.minX, y: -bounds.minY)
            context.stroke(
                Path(AppIconDesign.Geometry.bowlArc),
                with: .color(line),
                style: StrokeStyle(lineWidth: AppIconDesign.Geometry.lineWidth, lineCap: .round)
            )
            for (index, rect) in AppIconDesign.Geometry.barRects.enumerated() {
                let scale = barScales.indices.contains(index) ? barScales[index] : 1
                let scaled = rect.insetBy(dx: 0, dy: rect.height * (1 - scale) / 2)
                context.fill(Path(AppIconDesign.Geometry.bar(scaled)), with: .color(index == 2 ? accent : line))
            }
        }
        .frame(width: height * Self.aspectRatio, height: height)
        .accessibilityHidden(true)
    }
}

/// ロゴのマークを動かす音の値。`ContentView` が持っている周波数（和音は構成音）・音量・波形から作る
struct LogoSound: Equatable {
    var frequencies: ToneFrequencies
    /// 0...1
    var volume: Double
    var waveform: Waveform

    static let `default` = LogoSound(
        frequencies: ToneFrequencies(ToneSettings.default.frequency),
        volume: ToneSettings.default.volume,
        waveform: ToneSettings.default.waveform
    )
}

/// 再生中のロゴのマークのバーの長さ（判断ログ #265）。時刻（位相）と音の値から求める純粋な関数で、描画の状態を持たない。
///
/// - 音量 → 縮む深さ（音量 0 なら動かない）
/// - 周波数 → 動きの速さ（低い音はゆっくり、高い音は速く。対数で `Theme.LogoMotion.minRate`〜`maxRate`）
/// - 波形 → 動きの形（Sine はなめらか、Square は伸び縮みの端で止まる、Triangle は一定の速さ、Sawtooth はゆっくり縮んで速く戻る）
/// - 和音 → 構成音ごとにバーを割り当て、構成音の高さの比で速さを変える（中央のバーが根音）
///
/// バーの長さはアイコンの長さを上限に縮むだけで、図柄からはみ出さない。位相 0 ではアイコンの形なので、動き始めに飛ばない
enum LogoMarkMotion {
    /// 止まっているときの長さの比（アイコンの形）
    static let restingScales: [CGFloat] = Array(repeating: 1, count: AppIconDesign.Geometry.barRects.count)

    /// 和音のときに、バー（左から）に割り当てる構成音の番号。中央が根音、左右対称に第 3 音・第 5 音
    static let chordToneForBar = [1, 2, 0, 2, 1]

    /// 動きの基本の速さ（往復 / 秒）。和音は根音（1 つ目）で決める
    static func baseRate(for frequencies: ToneFrequencies) -> Double {
        let range = FrequencyInput.range
        let frequency = min(max(frequencies[0], range.lowerBound), range.upperBound)
        let position = log(frequency / range.lowerBound) / log(range.upperBound / range.lowerBound)
        return Theme.LogoMotion.minRate + (Theme.LogoMotion.maxRate - Theme.LogoMotion.minRate) * position
    }

    /// バー（左から）の、基本の速さに対する倍率。バーごとの倍率に、和音なら構成音の高さの比を掛ける
    static func barRateFactors(for frequencies: ToneFrequencies) -> [Double] {
        Theme.LogoMotion.barRateFactors.enumerated().map { index, factor in
            guard frequencies.count > 1 else { return factor }
            let tone = chordToneForBar[index] % frequencies.count
            let octaves = min(max(log2(frequencies[tone] / frequencies[0]), 0), 1)
            return factor * (1 + Theme.LogoMotion.chordRateSpread * octaves)
        }
    }

    /// 縮む深さ（0...maxDepth）
    static func depth(volume: Double) -> Double {
        Theme.LogoMotion.maxDepth * min(max(volume, 0), 1)
    }

    /// 1 往復の中の縮み具合（0...1）。位相の整数部は捨てる。位相 0（と 1）で 0 になり、つなぎ目で途切れない
    static func shape(_ waveform: Waveform, phase: Double) -> Double {
        let unit = phase - floor(phase)
        let sine = (1 - cos(2 * .pi * unit)) / 2
        switch waveform {
        case .sine:
            return sine
        case .square:
            // 端で止まる時間を長くする（なめらかさは残し、急に切り替えない）
            return smoothstep(smoothstep(sine))
        case .triangle:
            return unit < 0.5 ? 2 * unit : 2 - 2 * unit
        case .sawtooth:
            // 4 分の 3 をかけてゆっくり縮み、残りで戻る
            let split = 0.75
            return unit < split ? smoothstep(unit / split) : smoothstep((1 - unit) / (1 - split))
        }
    }

    /// 5 本のバー（左から）の、アイコンに対する長さの比（`1 - 深さ`...1）。`phase` は基本の速さで積み上げた位相（往復の回数）。
    /// 動かさないとき（停止中・Reduce Motion・撮影モード）はアイコンの形
    static func barScales(phase: Double, sound: LogoSound, isAnimating: Bool) -> [CGFloat] {
        guard isAnimating else { return restingScales }
        let depth = depth(volume: sound.volume)
        return barRateFactors(for: sound.frequencies).map { factor in
            CGFloat(1 - depth * shape(sound.waveform, phase: phase * factor))
        }
    }

    private static func smoothstep(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}

/// 速さが途中で変わる動きの位相（往復の回数）。速さを変えた時点の位相から続けて進めるので、速さが変わっても位相が飛ばない
struct PhaseAccumulator {
    /// `since` の時点の位相
    private(set) var accumulated: Double = 0
    /// 今の速さ（往復 / 秒）
    private(set) var rate: Double = 0
    /// 今の速さになった時刻（`PausableClock` の経過時間）
    private(set) var since: TimeInterval = 0

    /// `time`（`PausableClock` の経過時間）の時点の位相
    func phase(at time: TimeInterval) -> Double {
        accumulated + rate * max(0, time - since)
    }

    /// `time` の時点から速さを `newRate` にする
    mutating func setRate(_ newRate: Double, at time: TimeInterval) {
        accumulated = phase(at: time)
        since = max(since, time)
        rate = newRate
    }
}

/// ロゴの書体（Discussion #262 Q2）。アプリに同梱した OFL の書体を、Asset Catalog の Data Set から読んでプロセスに登録して使う。
///
/// `UIAppFonts` / `ATSApplicationFontsPath`（Info.plist）を使わないのは、pbxproj と Info.plist を変えずに iOS と macOS で同じ方法で読むため。
/// 書体を差し替えるときは、Data Set（`dataAssetName` / `licenseAssetName`）の中身と、ここの名前・著作権表示の定数を差し替える
enum LogoFont {
    /// フォントファイルを入れた Data Set の名前
    static let dataAssetName = "LogoFont"
    /// ライセンスの全文（`OFL.txt`）を入れた Data Set の名前
    static let licenseAssetName = "LogoFontLicense"
    /// `Font.custom` に渡す PostScript 名
    static let postScriptName = "Audiowide-Regular"
    /// 設定画面のライセンス表記に出す書体名
    static let familyName = "Audiowide"
    /// 設定画面のライセンス表記に出す著作権表示（`OFL.txt` の 1 行目のまま。Reserved Font Name を含む）
    static let copyright = #"Copyright (c) 2012, Brian J. Bonislawsky DBA Astigmatic (AOETI) (astigma@astigmatic.com), with Reserved Font Names "Audiowide""#
    /// ライセンスの名前
    static let licenseName = "SIL Open Font License 1.1"

    /// 書体をプロセスに登録できたか。`static let` なので最初に読まれたときに 1 回だけ登録する
    static let isRegistered: Bool = register()

    /// 書体を登録する（2 回目以降は何もしない）。登録できて PostScript 名で使えるなら true
    @discardableResult
    static func registerIfNeeded() -> Bool {
        isRegistered
    }

    /// ロゴの書体の `size` pt。登録できなかったとき（データが無い・壊れている）はシステムの太字にする
    static func font(size: CGFloat) -> Font {
        registerIfNeeded() ? .custom(postScriptName, fixedSize: size) : .system(size: size, weight: .bold)
    }

    /// ライセンスの全文。Data Set が無いときは nil
    static var licenseText: String? {
        NSDataAsset(name: licenseAssetName, bundle: .main).flatMap { String(data: $0.data, encoding: .utf8) }
    }

    /// `name` の PostScript 名の書体が、代わりの書体ではなくそのまま作れるか
    static func isAvailable(postScriptName name: String) -> Bool {
        let font = CTFontCreateWithName(name as CFString, 12, nil)
        return CTFontCopyPostScriptName(font) as String == name
    }

    private static func register() -> Bool {
        // ほかの経路（Preview の再読み込みなど）で登録済みなら、重ねて登録しない
        if isAvailable(postScriptName: postScriptName) {
            return true
        }
        guard let asset = NSDataAsset(name: dataAssetName, bundle: .main),
              let url = writeFontFile(asset.data) else {
            return false
        }
        // データから作った descriptor（`CTFontManagerCreateFontDescriptorsFromData`）は URL を持たないので
        // `CTFontManagerRegisterFontDescriptors` では登録できない（code 303）。キャッシュに書き出したファイルを URL で登録する
        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        error?.release()
        return registered && isAvailable(postScriptName: postScriptName)
    }

    /// フォントのデータをキャッシュのディレクトリに書き出す。同じ中身のファイルがあれば書き直さない。
    /// App Sandbox を外した撮影用ビルドではユーザー共通の `~/Library/Caches` になるので、バンドル ID の下に置く
    private static func writeFontFile(_ data: Data) -> URL? {
        let fileManager = FileManager.default
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let directory = caches
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "OneTone", isDirectory: true)
            .appendingPathComponent(dataAssetName, isDirectory: true)
        let url = directory.appendingPathComponent("\(postScriptName).ttf")
        if fileManager.contents(atPath: url.path) == data {
            return url
        }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

/// 動いていた時間だけを積み上げる時計。止めている間は進まない
struct PausableClock {
    /// 直前に止めるまでに動いていた時間の合計
    private(set) var accumulated: TimeInterval = 0
    /// 動いている間は動き始めた時刻、止まっている間は nil
    private(set) var startedAt: Date?

    mutating func start(at date: Date) {
        guard startedAt == nil else { return }
        startedAt = date
    }

    mutating func stop(at date: Date) {
        guard let startedAt else { return }
        accumulated += max(0, date.timeIntervalSince(startedAt))
        self.startedAt = nil
    }

    /// `date` の時点までに動いていた時間の合計
    func elapsed(at date: Date) -> TimeInterval {
        guard let startedAt else { return accumulated }
        return accumulated + max(0, date.timeIntervalSince(startedAt))
    }
}

#Preview("停止中") {
    TitleView(isPlaying: false)
        .padding()
        .themedScreen()
}

#Preview("再生中") {
    TitleView(isPlaying: true)
        .padding()
        .themedScreen()
}

#Preview("ピンクのテーマで再生中") {
    TitleView(isPlaying: true)
        .padding()
        .themedScreen()
        .environment(\.themeColor, .pink)
}

#Preview("iPhone の幅（375pt）") {
    TitleView(isPlaying: false)
        .padding()
        .frame(width: 375)
        .themedScreen()
}

#Preview("小さいロゴ（バー）") {
    LogoLockup(textSize: 18)
        .padding()
        .themedScreen()
}
