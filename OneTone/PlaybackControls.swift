//
//  PlaybackControls.swift
//  OneTone
//

import SwiftUI

/// 再生と停止を 1 つで切り替える大きなトグルボタン。再生状態は親が持ち、押されたことだけをクロージャで伝える。
/// 状態は発光の有無だけでなく、ラベル（PLAY / STOP）とアイコン（▶ / ■）、枠の太さでも区別する
struct PlaybackControls: View {
    let isPlaying: Bool
    let onPlay: () -> Void
    let onStop: () -> Void

    var body: some View {
        Button(action: isPlaying ? onStop : onPlay) {
            VStack(spacing: 8) {
                // ラベルは次に起きる操作を示す（停止中は PLAY、再生中は STOP）
                Group {
                    if isPlaying {
                        Rectangle()
                    } else {
                        PlayTriangle()
                    }
                }
                .frame(width: 28, height: 28)
                // 大文字のラベルは機材の刻印として英語のまま出す（訳さない）
                Text(verbatim: isPlaying ? "STOP" : "PLAY")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .tracking(2)
            }
        }
        .buttonStyle(ToggleButtonStyle(isOn: isPlaying))
        .accessibilityLabel(isPlaying ? Text("Stop Tone") : Text("Play Tone"))
        .accessibilityValue(isPlaying ? Text("Playing") : Text("Stopped"))
    }
}

/// ▶ の形。画像素材を使わず Path で描く
struct PlayTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // 三角形の重心が中央に来るよう、左の辺を少し右へ寄せる
        let inset = rect.width * 0.1
        path.move(to: CGPoint(x: rect.minX + inset, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 丸い大きなトグル。オンの間は差し色の太い枠で光り、オフの間は細い控えめな枠で静かにしている
struct ToggleButtonStyle: ButtonStyle {
    let isOn: Bool
    @Environment(\.themeColor) private var themeColor
    private let size: CGFloat = 120

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isOn ? themeColor.accent : Theme.textPrimary)
            .frame(width: size, height: size)
            .background(
                Circle().fill(
                    RadialGradient(
                        colors: [Theme.surfaceRaised, Theme.surface],
                        center: .top,
                        startRadius: 0,
                        endRadius: size
                    )
                )
            )
            .overlay(
                Circle().strokeBorder(
                    isOn ? themeColor.accent : Theme.textDisabled.opacity(0.6),
                    lineWidth: isOn ? 4 : 1.5
                )
            )
            .neonGlow(isActive: isOn)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .contentShape(Circle())
    }
}

#Preview("停止中") {
    PlaybackControls(isPlaying: false, onPlay: {}, onStop: {})
        .padding(40)
        .themedScreen()
}

#Preview("再生中") {
    PlaybackControls(isPlaying: true, onPlay: {}, onStop: {})
        .padding(40)
        .themedScreen()
}
