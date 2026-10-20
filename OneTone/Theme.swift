//
//  Theme.swift
//  OneTone
//

import SwiftUI

/// 画面全体の配色・角丸・発光の定義。各部品に直接色を書かず、ここから取る。
///
/// ダーク固定（Discussion #36 Q2）なので、ライト／ダークで出し分ける Assets の Color Set ではなく Swift の定数で持つ。
/// 文字色は背景 `background` とのコントラスト比 4.5:1 以上を目安に選んでいる（値は Issue #43 に一覧）。
enum Theme {
    /// 画面の背景（ほぼ黒）
    static let background = Color(hex: backgroundHex)
    /// `background` の 0xRRGGBB。コントラスト比の計算に使う
    static let backgroundHex: UInt32 = 0x0A0A0F
    /// 部品を載せる面（パネル）
    static let surface = Color(hex: 0x16161F)
    /// 一段持ち上げた面（押せる部品）
    static let surfaceRaised = Color(hex: surfaceRaisedHex)
    /// `surfaceRaised` の 0xRRGGBB。レベルメーターの濃淡の計算とコントラスト比の確認に使う
    static let surfaceRaisedHex: UInt32 = 0x22222E

    /// 本文・数値の文字（背景比 17.7:1）
    static let textPrimary = Color(hex: 0xF2F2F7)
    /// ラベル・補足の文字（背景比 8.3:1）
    static let textSecondary = Color(hex: 0xA6A6B8)
    /// 無効時の文字（背景比 4.0:1）
    static let textDisabled = Color(hex: 0x6E6E80)

    /// 既定テーマ（ネオンシアン）の差し色。部品からは使わず、Environment の `themeColor` から取る
    static let accent = ThemeColor.default.accent
    /// 2 つ目の差し色（ネオンマゼンタ）。再生中の強調などに使う
    static let accentSecondary = Color(hex: 0xFF2BD6)
    /// 既定テーマの差し色の上に載せる文字。白ではシアン上で読めないため背景と同じ暗色にする（シアン上で 12.8:1）。
    /// 部品からは使わず、Environment の `themeColor` から取る
    static let onAccent = ThemeColor.default.onAccent

    static let cornerRadius: CGFloat = 12
    /// 再生中の発光の半径。停止中は発光させない
    static let glowRadius: CGFloat = 8
    /// 発光の明るさがゆっくりゆらぐ周期（秒）。点滅に見えないよう、ゆらぎは小さく遅くする
    static let glowPulsePeriod: TimeInterval = 2.4
    /// 発光の明るさのゆらぎの幅（0...1）。明るさは 1 - この値 〜 1 の間を行き来し、消えることはない
    static let glowPulseDepth: Double = 0.25
    /// 再生中にタイトルの色相が選んだ色を中心に 1 往復する秒数。点滅に見えないよう、ゆっくり揺らす
    static let titleHueSwingPeriod: TimeInterval = 8
    /// 再生中にタイトルの色相を揺らす幅（度）。選んだ色の色相から -この値 〜 +この値 の間を行き来する（判断ログ #91）
    static let titleHueSwingAmplitude: Double = 30

    /// ロゴ（アイコンのマーク＋「One Tone」）の寸法。文字の大きさを基準に、マークの高さと間隔を比で決める（判断ログ #265）
    enum Logo {
        /// メイン画面の大きいロゴの文字の大きさ（pt）の候補。大きい順に、幅に収まる最初のものを使う
        /// （iPad・macOS は 56pt、iPhone は 48pt になる。56pt のロゴの幅は約 372pt）
        static let largeTextSizes: [CGFloat] = [56, 48, 40, 32]
        /// 文字の大きさに対するマークの高さ。マークを大文字より少し高くし、アイコンの図柄として見えるようにする
        static let markHeightRatio: CGFloat = 0.95
        /// 文字の大きさに対する、マークと文字の間隔
        static let spacingRatio: CGFloat = 0.25
        /// iOS 26 以上のバーに出す小さいロゴの文字の大きさ（pt）。ロゴの高さは約 26pt（判断ログ #265）
        static let barTextSize: CGFloat = 20
        /// バーの小さいロゴを出す・消すフェードの秒数（Q4: 実装後に触って調整する値）
        static let barFadeDuration: TimeInterval = 0.2
        /// バーの小さいロゴを消す境目のゆとり（pt）。大きいロゴの下端がバーの下端よりこれだけ下へ戻るまで消さず、境目でちらつかないようにする
        static let barLogoHysteresis: CGFloat = 8
    }

    /// 再生中のロゴのマークのバーの動き（判断ログ #265）。バーはアイコンの長さを上限に縮んで戻り、イコライザーのように伸び縮みする
    enum LogoMotion {
        /// 音量 100% のときにバーが縮む深さ（0...1）。バーの長さはアイコンの長さ × (1 - 深さ × 音量) 〜 アイコンの長さの間を行き来する
        static let maxDepth: Double = 0.6
        /// 動きの基本の速さ（往復 / 秒）。鳴っている音（和音は根音）の周波数が 20Hz で `minRate`、20kHz で `maxRate`（対数で比例）
        static let minRate: Double = 0.5
        static let maxRate: Double = 1.2
        /// バーごとの速さの倍率（左から）。そろって動かず、ばらけて見えるようにする
        static let barRateFactors: [Double] = [0.83, 1.17, 1.0, 1.29, 0.71]
        /// 和音のときに構成音が 1 オクターブ上のバーを、根音のバーより何倍速く動かすか（構成音の比を対数で縮める）
        static let chordRateSpread: Double = 0.5
        /// 1 本のバーの往復の速さの上限（往復 / 秒）。点滅に見えないよう 1 秒に 3 回を下回らせる。
        /// 今の値の組み合わせではいちばん速いバーでも約 2.3 往復 / 秒で、これを超える値にしても `LogoMarkMotion.barRates` が抑える
        static let maxBarRate: Double = 2.5
    }
}

extension Color {
    /// 0xRRGGBB 形式の sRGB 色
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// 黒基調の背景・文字色と、選ばれているテーマの差し色をかける
private struct ThemedScreen: ViewModifier {
    @Environment(\.themeColor) private var themeColor

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Theme.textPrimary)
            .tint(themeColor.accent)
            .background(Theme.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
    }
}

extension View {
    /// 黒基調の背景・文字色・差し色をかけ、システムの外観設定に関わらずダークで表示する。
    /// 画面のルートと各部品のプレビューで使う。差し色は Environment の `themeColor` に従う
    func themedScreen() -> some View {
        modifier(ThemedScreen())
    }
}
