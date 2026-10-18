//
//  VolumeControl.swift
//  OneTone
//

import SwiftUI

/// DJ ミキサーのような縦フェーダーと % 表示。変更は `onChange` で親に渡し、親が音量を反映する
struct VolumeControl: View {
    let volume: Double
    let onChange: (Double) -> Void

    /// ドラッグを始めた時点の音量。つまみを掴んだ位置へ値が飛ばないよう、始点からの移動量で動かす。
    /// `@GestureState` なので、ドラッグがキャンセルされても nil に戻る
    @GestureState private var dragStartVolume: Double?

    private let trackHeight: CGFloat = FaderMapping.trackHeight
    private let capSize = CGSize(width: 44, height: 18)

    var body: some View {
        VStack(spacing: 8) {
            Text("VOLUME")
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textSecondary)
            fader
            Text("\(FaderMapping.percent(for: volume))%")
                .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
        .padding()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(FaderMapping.percent(for: volume))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onChange(FaderMapping.clamped(volume + FaderMapping.accessibilityStep))
            case .decrement:
                onChange(FaderMapping.clamped(volume - FaderMapping.accessibilityStep))
            @unknown default:
                break
            }
        }
    }

    private var fader: some View {
        let clampedVolume = FaderMapping.clamped(volume)
        return ZStack(alignment: .bottom) {
            // 溝
            Capsule()
                .fill(Theme.surfaceRaised)
                .frame(width: 8, height: trackHeight)
            // 今の音量までの差し色
            Capsule()
                .fill(Theme.accent)
                .frame(width: 8, height: trackHeight * clampedVolume)
            // つまみ。中央の線で位置を読み取りやすくする
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.surfaceRaised)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.textDisabled, lineWidth: 1))
                .overlay(Rectangle().fill(Theme.textPrimary).frame(height: 2))
                .frame(width: capSize.width, height: capSize.height)
                .offset(y: capSize.height / 2 - trackHeight * clampedVolume)
        }
        // つまみが溝の端からはみ出す分も含めて、触れる範囲にする
        .frame(width: capSize.width, height: trackHeight)
        .padding(.vertical, capSize.height / 2)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($dragStartVolume) { value, start, _ in
                    if start == nil {
                        start = clampedVolume
                    }
                    onChange(FaderMapping.volume(from: start ?? clampedVolume, dragHeight: value.translation.height))
                }
        )
    }
}

/// フェーダーのドラッグ量と音量（0...1）の対応。UI から切り離してテストできるようにしている
enum FaderMapping {
    /// 溝の長さ（pt）。この長さのドラッグで 0〜100% を動かす
    static let trackHeight: CGFloat = 160
    /// VoiceOver の 1 回の調整で動かす量
    static let accessibilityStep: Double = 0.05

    static func clamped(_ volume: Double) -> Double {
        min(max(volume, 0), 1)
    }

    /// ドラッグを始めた時点の音量と縦の移動量（下向きが正）から、新しい音量を求める。上へ動かすと上がる
    static func volume(from start: Double, dragHeight: Double) -> Double {
        clamped(start - dragHeight / Double(trackHeight))
    }

    /// 表示用の % 表記（四捨五入）
    static func percent(for volume: Double) -> Int {
        Int((clamped(volume) * 100).rounded())
    }
}

#Preview("50%") {
    VolumeControl(volume: 0.5, onChange: { _ in })
        .themedScreen()
}

#Preview("0% と 100%") {
    HStack {
        VolumeControl(volume: 0, onChange: { _ in })
        VolumeControl(volume: 1, onChange: { _ in })
    }
    .themedScreen()
}
