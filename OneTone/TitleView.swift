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

/// 選んだテーマの差し色を中心にしたグラデーションのタイトル。グラデーションは常に表示し、色相の揺れと発光は再生中だけにする（停止中は静か）。
/// 色相は選んだ色の周りで ±`Theme.titleHueSwingAmplitude` 度だけ揺らし、別の色にはしない。
/// Reduce Motion がオンのとき、またはスクリーンショットの撮影モードのときは揺らさない
struct TitleView: View {
    let isPlaying: Bool
    @Environment(\.themeColor) private var themeColor
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
            title(hue: Self.hueDegrees(at: clock.elapsed(at: context.date)))
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
    }

    private func title(hue: Double) -> some View {
        Text(verbatim: "One Tone")
            .foregroundStyle(Theme.textPrimary)
            .font(.custom("Helvetica Neue", size: 60))
            .fontWeight(.bold)
            // iPhone の幅では 60pt のままだとタイトルが収まらないので縮小を許可する
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: themeColor.titleGradient),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .mask(
                    Text(verbatim: "One Tone")
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                )
                .font(.custom("Helvetica Neue", size: 60))
                .fontWeight(.bold)
                .hueRotation(Angle(degrees: hue))
            )
            .neonGlow(Theme.accentSecondary, isActive: isPlaying)
    }

    /// 揺れていた時間（秒）に対する色相のずらし角（-振幅...+振幅）。
    /// 0 秒では 0°（選んだ色のまま）から始まり、正弦波で `Theme.titleHueSwingPeriod` 秒ごとに 1 往復する。
    /// 端で速度が 0 になるので、折り返しでカクつかない
    static func hueDegrees(at time: TimeInterval) -> Double {
        Theme.titleHueSwingAmplitude * sin(2 * .pi * time / Theme.titleHueSwingPeriod)
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
