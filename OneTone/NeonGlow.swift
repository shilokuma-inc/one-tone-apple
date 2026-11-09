//
//  NeonGlow.swift
//  OneTone
//

import SwiftUI

/// 再生中だけ差し色で光らせる修飾子。各部品で「再生中だけ光る・動く（停止中は静か）」をそろえるために使う。
///
/// 再生中は明るさをゆっくりゆらがせる（点滅ではなく、消えずに 75〜100% の間を行き来する）。
/// Reduce Motion がオンのとき（とスクリーンショットの撮影モード）はゆらぎを止め、一定の明るさで光らせる。停止中は発光しない
struct NeonGlow: ViewModifier {
    /// 光の色。nil なら選ばれているテーマの差し色
    let color: Color?
    let isActive: Bool
    @Environment(\.themeColor) private var themeColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.freezesAnimations) private var freezesAnimations

    func body(content: Content) -> some View {
        // ゆらがせないとき（停止中・Reduce Motion・撮影モード）は描画の更新も止める
        let isSteady = reduceMotion || freezesAnimations
        let color = color ?? themeColor.accent
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isActive || isSteady)) { context in
            let intensity = Self.intensity(
                at: context.date.timeIntervalSinceReferenceDate,
                isActive: isActive,
                reduceMotion: isSteady
            )
            content
                .shadow(color: color.opacity(0.9 * intensity), radius: Theme.glowRadius * 0.5 * intensity)
                .shadow(color: color.opacity(0.6 * intensity), radius: Theme.glowRadius * intensity)
        }
    }

    /// 発光の明るさ（0...1）。停止中は 0、Reduce Motion なら 1 で一定、それ以外は周期的にゆらぐ
    static func intensity(at time: TimeInterval, isActive: Bool, reduceMotion: Bool) -> Double {
        guard isActive else { return 0 }
        guard !reduceMotion else { return 1 }
        let wave = (1 + sin(2 * Double.pi * time / Theme.glowPulsePeriod)) / 2
        return 1 - Theme.glowPulseDepth * wave
    }
}

extension View {
    /// 再生中だけ光らせる。停止中は何も足さない。色を省くと選ばれているテーマの差し色で光る
    func neonGlow(_ color: Color? = nil, isActive: Bool) -> some View {
        modifier(NeonGlow(color: color, isActive: isActive))
    }
}

#Preview("停止中") {
    RoundedRectangle(cornerRadius: Theme.cornerRadius)
        .stroke(.tint, lineWidth: 2)
        .frame(width: 160, height: 60)
        .neonGlow(isActive: false)
        .padding(40)
        .themedScreen()
}

#Preview("再生中") {
    RoundedRectangle(cornerRadius: Theme.cornerRadius)
        .stroke(.tint, lineWidth: 2)
        .frame(width: 160, height: 60)
        .neonGlow(isActive: true)
        .padding(40)
        .themedScreen()
}
