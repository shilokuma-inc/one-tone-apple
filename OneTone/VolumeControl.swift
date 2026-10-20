//
//  VolumeControl.swift
//  OneTone
//

import SwiftUI

/// DJ ミキサーのような縦フェーダーと % 表示。変更は `onChange` で親に渡し、親が音量を反映する
struct VolumeControl: View {
    let volume: Double
    let onChange: (Double) -> Void
    @Environment(\.themeColor) private var themeColor

    /// ドラッグを始めた時点の音量。つまみを掴んだ位置へ値が飛ばないよう、始点からの移動量で動かす。
    /// `@GestureState` なので、ドラッグがキャンセルされても nil に戻る
    @GestureState private var dragStartVolume: Double?

    private let capSize = CGSize(width: 44, height: 18)

    /// 溝の長さと余白。端末の種類で決まるので、毎回 `FaderMetrics.current` から読む
    private var metrics: FaderMetrics { .current }
    private var trackHeight: CGFloat { metrics.trackHeight }

    var body: some View {
        VStack(spacing: metrics.labelSpacing) {
            Text(verbatim: "VOLUME")
                .font(.caption.weight(.semibold))
                .tracking(1.5)
                .foregroundStyle(Theme.textSecondary)
            fader
            Text("\(FaderMapping.percent(for: volume))%")
                .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal)
        .padding(.vertical, metrics.verticalPadding)
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
                .fill(themeColor.accent)
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
                    onChange(FaderMapping.volume(
                        from: start ?? clampedVolume,
                        dragHeight: value.translation.height,
                        trackHeight: trackHeight
                    ))
                }
        )
    }
}

/// フェーダーの寸法。iPhone では OUTPUT パネルの PLAY ボタン（直径 120pt）の上下に空きが出ないよう、
/// 溝を短くしてラベルとの間隔・上下の余白も詰める（Discussion #253 Q1）。iPad と macOS は既定の寸法のまま
struct FaderMetrics: Equatable {
    /// 溝の長さ（pt）。この長さのドラッグで 0〜100% を動かす
    let trackHeight: CGFloat
    /// VOLUME のラベル・溝・% 表示の間隔
    let labelSpacing: CGFloat
    /// 上下の余白。nil はシステムの既定（`.padding()` と同じ）
    let verticalPadding: CGFloat?

    /// iPad と macOS の寸法（Discussion #253 より前と同じ）
    static let standard = FaderMetrics(trackHeight: 160, labelSpacing: 8, verticalPadding: nil)
    /// iPhone の寸法
    static let compactPhone = FaderMetrics(trackHeight: 100, labelSpacing: 4, verticalPadding: 0)

    /// 今の端末の寸法。幅やサイズクラスではなく端末の種類で分ける（iPad の Split View の狭い幅は既定のまま）
    @MainActor
    static var current: FaderMetrics {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone ? .compactPhone : .standard
        #else
        .standard
        #endif
    }
}

/// フェーダーのドラッグ量と音量（0...1）の対応。UI から切り離してテストできるようにしている
enum FaderMapping {
    /// VoiceOver の 1 回の調整で動かす量
    static let accessibilityStep: Double = 0.05

    static func clamped(_ volume: Double) -> Double {
        min(max(volume, 0), 1)
    }

    /// ドラッグを始めた時点の音量と縦の移動量（下向きが正）から、新しい音量を求める。上へ動かすと上がり、
    /// 溝の長さ（`trackHeight`）ぶん動かすと 0〜100% を動く
    static func volume(from start: Double, dragHeight: Double, trackHeight: CGFloat) -> Double {
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
