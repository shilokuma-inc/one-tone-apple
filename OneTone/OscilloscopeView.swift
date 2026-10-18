//
//  OscilloscopeView.swift
//  OneTone
//

import SwiftUI

/// 実際に出力している音の波形を、オシロスコープのように表示する。
///
/// 出力履歴は描画のたびに `readSamples` で取りに行く（サンプルごとに `@Published` を更新するとメインスレッドが追いつかないため）。
/// 再生中だけ動き、停止中はフラットな線で静止する。Reduce Motion がオンのときは更新を 0.5 秒ごとに落とし、
/// 流れるような動きを出さない（トリガーで位置をそろえているので、更新しても波形は大きく動かない）
struct OscilloscopeView: View {
    let isPlaying: Bool
    /// 直近の出力サンプルを古い順に返す（`AudioManager.latestOutputSamples`）
    let readSamples: (Int) -> [Float]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.freezesAnimations) private var freezesAnimations

    var body: some View {
        // 停止中（と撮影モード）は描画の更新も止める
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.5 : 1.0 / 30, paused: !isPlaying || freezesAnimations)) { _ in
            let samples = isPlaying
                ? Oscilloscope.triggeredWindow(readSamples(Oscilloscope.readLength), length: Oscilloscope.windowLength)
                : []
            Canvas { context, size in
                drawGrid(in: &context, size: size)
                context.stroke(
                    Oscilloscope.path(for: samples, in: CGRect(origin: .zero, size: size)),
                    with: .color(isPlaying ? Theme.accent : Theme.textDisabled),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
            }
            .neonGlow(Theme.accent, isActive: isPlaying)
        }
        .frame(maxWidth: 440)
        .frame(height: 120)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.surfaceRaised, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .padding(.horizontal)
        .accessibilityElement()
        .accessibilityLabel("Oscilloscope")
        .accessibilityValue(isPlaying ? "Showing output waveform" : "Silent")
    }

    /// 機材の画面らしい目盛り（中央の横線と縦の区切り）
    private func drawGrid(in context: inout GraphicsContext, size: CGSize) {
        var grid = Path()
        for index in 1..<8 {
            let x = size.width * CGFloat(index) / 8
            grid.move(to: CGPoint(x: x, y: 0))
            grid.addLine(to: CGPoint(x: x, y: size.height))
        }
        for index in 1..<4 {
            let y = size.height * CGFloat(index) / 4
            grid.move(to: CGPoint(x: 0, y: y))
            grid.addLine(to: CGPoint(x: size.width, y: y))
        }
        context.stroke(grid, with: .color(Theme.surfaceRaised), lineWidth: 1)
    }
}

/// オシロスコープの表示範囲の切り出しと描画用の点。UI から切り離してテストできるようにしている
enum Oscilloscope {
    /// 表示するサンプル数。48kHz で約 21ms（440Hz なら約 9 周期）
    static let windowLength = 1024
    /// 描画のたびに読む出力履歴の数。表示範囲の手前でゼロクロスを探す範囲に、最低周波数 20Hz の 1 周期
    /// （48kHz で 2400、96kHz でも 4800 サンプル）が収まるよう、履歴を全部読む。
    /// 探す範囲が 1 周期より短いと、トリガーできる回とできない回が入れ替わって波形の位置が跳ぶ
    static let readLength = AudioManager.outputHistoryCapacity
    /// 振幅 1 のときに上下の端から残す余白の割合
    static let verticalMargin: CGFloat = 0.1

    /// 波形の位置が描画のたびにずれて流れて見えないよう、負から 0 以上へ上がる点（ゼロクロス）から `length` 個を切り出す。
    /// 表示が実際の出力から遅れないよう、後ろに `length` 個残るゼロクロスのうち最も新しいものを選ぶ。
    /// ゼロクロスが見つからない（無音など）ときは末尾の `length` 個を返す
    static func triggeredWindow(_ samples: [Float], length: Int) -> [Float] {
        guard length > 0, samples.count > length else { return samples }
        // 切り出した後ろに `length` 個残る範囲でだけ探す
        let searchEnd = samples.count - length
        for index in stride(from: searchEnd, through: 1, by: -1) where samples[index - 1] < 0 && samples[index] >= 0 {
            return Array(samples[index..<(index + length)])
        }
        return Array(samples.suffix(length))
    }

    /// サンプルを `rect` いっぱいに横へ並べた線。空なら中央のフラットな線
    static func path(for samples: [Float], in rect: CGRect) -> Path {
        var path = Path()
        guard samples.count > 1 else {
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return path
        }
        let amplitude = rect.height / 2 * (1 - verticalMargin)
        for (index, sample) in samples.enumerated() {
            let point = CGPoint(
                x: rect.minX + rect.width * CGFloat(index) / CGFloat(samples.count - 1),
                y: rect.midY - amplitude * CGFloat(min(max(sample, -1), 1))
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

/// プレビュー用の 440Hz 相当のサイン波
private func previewSamples(_ count: Int) -> [Float] {
    (0..<count).map { Float(0.5 * sin(2 * Double.pi * 440 * Double($0) / 48000 + 1)) }
}

#Preview("再生中") {
    OscilloscopeView(isPlaying: true, readSamples: previewSamples)
        .padding()
        .themedScreen()
}

#Preview("停止中") {
    OscilloscopeView(isPlaying: false, readSamples: previewSamples)
        .padding()
        .themedScreen()
}
