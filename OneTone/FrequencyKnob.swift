//
//  FrequencyKnob.swift
//  OneTone
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// 周波数を DJ 機材のつまみのように回して変えるノブ。変更は `onChange` を通して親の 1 か所に集める。
/// 細かい値はノブでは合わせにくいため、スライダーと数値入力も併せて残している。
/// 音名モードでは `scale: .semitone` にして、半音にスナップした周波数だけを渡す
struct FrequencyKnob: View {
    let frequency: Double
    var scale: KnobScale = .continuous
    let onChange: (Double) -> Void
    @Environment(\.themeColor) private var themeColor

    /// ドラッグ中の状態。`@GestureState` にしているのは、ドラッグがキャンセルされて `onEnded` が呼ばれなくても初期値に戻すため
    @GestureState private var drag = KnobDragState()

    private let size: CGFloat = 140

    var body: some View {
        let position = KnobMapping.position(for: frequency)
        ZStack {
            // 動かせる範囲の溝。Circle の trim は 3 時の位置から時計回りなので、真上基準の開始角から 90 度引いて回す
            Circle()
                .trim(from: 0, to: KnobMapping.sweepFraction)
                .stroke(Theme.surfaceRaised, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(KnobMapping.startAngle - 90))
            // 現在の値までの弧
            Circle()
                .trim(from: 0, to: KnobMapping.sweepFraction * position)
                .stroke(themeColor.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(KnobMapping.startAngle - 90))
            // つまみ本体
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Theme.surfaceRaised, Theme.surface],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size
                    )
                )
                .overlay(Circle().strokeBorder(Theme.textDisabled.opacity(0.5), lineWidth: 1))
                .padding(14)
            // 今の位置を指す目印
            Capsule()
                .fill(Theme.textPrimary)
                .frame(width: 4, height: size * 0.18)
                .offset(y: -size * 0.24)
                .rotationEffect(.degrees(KnobMapping.angle(for: position)))
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(dragGesture)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                onChange(scale.accessibilityAdjusted(frequency, up: true))
            case .decrement:
                onChange(scale.accessibilityAdjusted(frequency, up: false))
            @unknown default:
                break
            }
        }
    }

    private var accessibilityLabel: Text {
        switch scale {
        case .continuous: return Text("Frequency")
        case .semitone: return Text("Note")
        }
    }

    /// 音名は訳さない（`A4` のまま読む）
    private var accessibilityValue: Text {
        switch scale {
        case .continuous: return Text("\(FrequencyInput.format(frequency)) Hz")
        case .semitone: return Text(verbatim: NoteInput.note(for: frequency).name)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($drag) { value, state, _ in
                let delta = KnobMapping.positionDelta(
                    dx: value.translation.width - state.translation.width,
                    dy: value.translation.height - state.translation.height,
                    isFine: Self.isFineAdjustment
                )
                state.translation = value.translation
                guard delta != 0 else { return }
                // 半音にスナップするときも、スナップ前の位置から動かす。スナップ後の値から動かすと、
                // 半音（約 2pt）に満たない動きが毎回丸めで打ち消され、ゆっくり回しても動かない
                let unsnapped = KnobMapping.adjusted(state.unsnappedFrequency ?? frequency, by: delta)
                state.unsnappedFrequency = unsnapped
                let snapped = scale.snapped(unsnapped)
                guard snapped != frequency else { return }
                onChange(snapped)
            }
    }

    /// macOS では Option キーを押しながらドラッグすると細かく調整できる。iOS は数値入力とスライダーで合わせる
    private static var isFineAdjustment: Bool {
        #if os(macOS)
        NSEvent.modifierFlags.contains(.option)
        #else
        false
        #endif
    }
}

/// ノブで選べる値の刻み
enum KnobScale {
    /// 周波数を連続的に動かす（Hz モード）
    case continuous
    /// 半音にスナップする（音名モード）。常にちょうどの音の周波数になる
    case semitone

    /// この刻みに合わせた周波数
    func snapped(_ frequency: Double) -> Double {
        switch self {
        case .continuous: return frequency
        case .semitone: return NoteInput.snapped(frequency)
        }
    }

    /// VoiceOver の 1 回の調整。連続なら全域の 1/60、半音なら 1 半音動かす
    func accessibilityAdjusted(_ frequency: Double, up: Bool) -> Double {
        switch self {
        case .continuous:
            return KnobMapping.adjusted(frequency, by: up ? KnobMapping.accessibilityStep : -KnobMapping.accessibilityStep)
        case .semitone:
            return NoteInput.note(for: frequency).clampedTransposed(by: up ? 1 : -1).frequency
        }
    }
}

/// ノブのドラッグ中に覚えておくもの
struct KnobDragState {
    /// 前回の変化時点までの移動量。修飾キーを途中で押しても値が飛ばないよう、差分ずつ反映する
    var translation: CGSize = .zero
    /// スナップする前の周波数。ドラッグの始めは nil で、今の周波数から動かし始める
    var unsnappedFrequency: Double?
}

/// ノブの位置（0...1）と周波数・角度・ドラッグ量の対応。UI から切り離してテストできるようにしている
enum KnobMapping {
    /// 最小位置の角度（真上を 0 度とした時計回り）。真下を空けた 270 度の範囲を回す
    static let startAngle: Double = -135
    static let sweepAngle: Double = 270
    static var sweepFraction: Double { sweepAngle / 360 }
    /// 全域（20Hz〜20kHz）を動かすのに必要なドラッグ量（pt）
    static let pointsPerFullRange: Double = 240
    /// 細かい調整のときはドラッグ量に対する変化をこの割合にする
    static let fineAdjustmentRatio: Double = 0.1
    /// VoiceOver の 1 回の調整で動かす量。全域の 1/60（約 12% ずつ）
    static let accessibilityStep: Double = 1.0 / 60

    private static let lowerLog = log10(FrequencyInput.range.lowerBound)
    private static let upperLog = log10(FrequencyInput.range.upperBound)

    /// 周波数を対数スケールの位置（0...1）にする。範囲外は端に丸める
    static func position(for frequency: Double) -> Double {
        let clamped = min(max(frequency, FrequencyInput.range.lowerBound), FrequencyInput.range.upperBound)
        return (log10(clamped) - lowerLog) / (upperLog - lowerLog)
    }

    /// 位置（0...1）を周波数にする。範囲外は端に丸める
    static func frequency(for position: Double) -> Double {
        let clamped = min(max(position, 0), 1)
        return pow(10, lowerLog + (upperLog - lowerLog) * clamped)
    }

    /// 位置に対する目印の角度（度）
    static func angle(for position: Double) -> Double {
        startAngle + sweepAngle * min(max(position, 0), 1)
    }

    /// 周波数を位置で `delta` だけ動かした値。範囲の端で止まる
    static func adjusted(_ frequency: Double, by delta: Double) -> Double {
        self.frequency(for: position(for: frequency) + delta)
    }

    /// ドラッグの移動量（pt）を位置の変化にする。上か右へ動かすと上がる
    static func positionDelta(dx: Double, dy: Double, isFine: Bool) -> Double {
        let delta = (dx - dy) / pointsPerFullRange
        return isFine ? delta * fineAdjustmentRatio : delta
    }
}

#Preview("440 Hz") {
    FrequencyKnob(frequency: 440, onChange: { _ in })
        .padding()
        .themedScreen()
}

#Preview("下限と上限") {
    HStack {
        FrequencyKnob(frequency: 20, onChange: { _ in })
        FrequencyKnob(frequency: 20000, onChange: { _ in })
    }
    .padding()
    .themedScreen()
}
