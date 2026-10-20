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

/// メイン画面の上の大きいロゴ（アイコンのマーク＋「One Tone」。`LogoLockup`）。色は常に表示し、色相の揺れと発光は再生中だけにする（停止中は静か）。
/// 色相は選んだ色の周りで ±`Theme.titleHueSwingAmplitude` 度だけ揺らし、別の色にはしない。
/// Reduce Motion がオンのとき、またはスクリーンショットの撮影モードのときは揺らさない。
/// 大きさは `Theme.Logo.largeTextSizes` から、幅に収まる最大のものを選ぶ
struct TitleView: View {
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.freezesAnimations) private var freezesAnimations
    /// 揺れていた時間だけを数える時計。止めている間の時間を角度に含めず、再開したとき色が飛ばないようにする
    @State private var clock = PausableClock()

    /// 色相を揺らすか。再生中かつ Reduce Motion がオフで、撮影モードでもないときだけ揺らす
    private var isAnimating: Bool {
        isPlaying && !reduceMotion && !freezesAnimations
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isAnimating)) { context in
            ViewThatFits(in: .horizontal) {
                ForEach(Theme.Logo.largeTextSizes, id: \.self) { size in
                    LogoLockup(textSize: size)
                }
            }
            .hueRotation(Angle(degrees: Self.hueDegrees(at: clock.elapsed(at: context.date))))
            .neonGlow(Theme.accentSecondary, isActive: isPlaying)
        }
        // 表示時と、揺らす／止めるが切り替わるたびに時計を動かす・止める
        // （2 引数の onChange は macOS 14 からなので、表示時にも呼ばれる task(id:) を使う）
        .task(id: isAnimating) {
            if isAnimating {
                clock.start(at: Date())
            } else {
                clock.stop(at: Date())
            }
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
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        HStack(spacing: textSize * Theme.Logo.spacingRatio) {
            LogoMark(height: textSize * Theme.Logo.markHeightRatio, line: Theme.textPrimary, accent: themeColor.accent)
            Text(verbatim: "One Tone")
                .font(LogoFont.font(size: textSize))
                .foregroundStyle(
                    LinearGradient(colors: themeColor.titleGradient, startPoint: .leading, endPoint: .trailing)
                )
                .lineLimit(1)
                .fixedSize()
        }
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
                context.fill(Path(AppIconDesign.Geometry.bar(rect)), with: .color(index == 2 ? accent : line))
            }
        }
        .frame(width: height * Self.aspectRatio, height: height)
        .accessibilityHidden(true)
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
