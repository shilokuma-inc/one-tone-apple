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
    static let background = Color(hex: 0x0A0A0F)
    /// 部品を載せる面（パネル）
    static let surface = Color(hex: 0x16161F)
    /// 一段持ち上げた面（押せる部品）
    static let surfaceRaised = Color(hex: 0x22222E)

    /// 本文・数値の文字（背景比 17.7:1）
    static let textPrimary = Color(hex: 0xF2F2F7)
    /// ラベル・補足の文字（背景比 8.3:1）
    static let textSecondary = Color(hex: 0xA6A6B8)
    /// 無効時の文字（背景比 4.0:1）
    static let textDisabled = Color(hex: 0x6E6E80)

    /// 操作部品の差し色（ネオンシアン）
    static let accent = Color(hex: 0x00E5FF)
    /// 2 つ目の差し色（ネオンマゼンタ）。再生中の強調などに使う
    static let accentSecondary = Color(hex: 0xFF2BD6)
    /// 差し色の上に載せる文字。白ではシアン上で読めないため背景と同じ暗色にする（シアン上で 12.8:1）
    static let onAccent = Color(hex: 0x0A0A0F)

    /// タイトルと装飾だけに使う虹色。読む文字や数値には使わない
    static let rainbow: [Color] = [.red, .orange, .yellow, .green, .blue, .purple, .red]

    static let cornerRadius: CGFloat = 12
    /// 再生中の発光の半径。停止中は発光させない
    static let glowRadius: CGFloat = 8
    /// 発光の明るさがゆっくりゆらぐ周期（秒）。点滅に見えないよう、ゆらぎは小さく遅くする
    static let glowPulsePeriod: TimeInterval = 2.4
    /// 発光の明るさのゆらぎの幅（0...1）。明るさは 1 - この値 〜 1 の間を行き来し、消えることはない
    static let glowPulseDepth: Double = 0.25
    /// 再生中にタイトルの色相が 1 周する秒数。以前の 1 秒周期は速すぎるため、ゆっくり回す
    static let titleHueCyclePeriod: TimeInterval = 8
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

extension View {
    /// 黒基調の背景・文字色・差し色をかけ、システムの外観設定に関わらずダークで表示する。
    /// 画面のルートと各部品のプレビューで使う
    func themedScreen() -> some View {
        self
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
            .background(Theme.background.ignoresSafeArea())
            .preferredColorScheme(.dark)
    }
}
