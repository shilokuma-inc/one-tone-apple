//
//  LevelMeterView.swift
//  OneTone
//

import SwiftUI

/// 実際に出力している音の大きさを、DJ ミキサーのような LED 風のメーターで表示する。
///
/// 出力履歴は描画のたびに `readSamples` で取りに行く。再生中だけ動き、停止中はすべて消灯して静止する。
/// Reduce Motion がオンのときは更新を 0.5 秒ごとに落とす
struct LevelMeterView: View {
    let isPlaying: Bool
    /// 直近の出力サンプルを古い順に返す（`AudioManager.latestOutputSamples`）
    let readSamples: (Int) -> [Float]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.freezesAnimations) private var freezesAnimations

    var body: some View {
        // 停止中（と撮影モード）は描画の更新も止める
        TimelineView(.animation(minimumInterval: reduceMotion ? 0.5 : 1.0 / 30, paused: !isPlaying || freezesAnimations)) { _ in
            let decibels = isPlaying ? LevelMeter.rmsDecibels(readSamples(LevelMeter.windowLength)) : -.infinity
            let litCount = LevelMeter.litSegmentCount(decibels: decibels)
            VStack(spacing: 6) {
                HStack {
                    Text("LEVEL")
                        .font(.caption.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text(LevelMeter.label(decibels: decibels))
                        .font(.system(.caption, design: .rounded).weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                }
                HStack(spacing: 3) {
                    ForEach(0..<LevelMeter.segmentCount, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index < litCount ? LevelMeter.segmentColor(index) : Theme.surfaceRaised)
                            .frame(height: 12)
                    }
                }
                .neonGlow(Theme.accent, isActive: isPlaying && litCount > 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Level")
            .accessibilityValue(isPlaying ? LevelMeter.label(decibels: decibels) : "Silent")
        }
        .frame(maxWidth: 440)
        .padding(.horizontal)
    }
}

/// レベルメーターの計算。UI から切り離してテストできるようにしている
enum LevelMeter {
    /// レベルを集計するサンプル数。48kHz で約 43ms（20Hz の 1 周期 50ms に近く、低い音でも揺れにくい）
    static let windowLength = 2048
    /// 表示する範囲（dBFS）。これより小さいレベルは消灯
    static let floorDecibels: Double = -60
    static let segmentCount = 20
    /// これ以上のレベルのセグメントは 2 つ目の差し色にして、大きすぎることを知らせる（dBFS）
    static let warningDecibels: Double = -6

    /// RMS（二乗平均平方根）を dBFS で返す。振幅 1 のサイン波で約 -3dB。無音は -inf
    static func rmsDecibels(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return -.infinity }
        let meanSquare = samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)
        guard meanSquare > 0 else { return -.infinity }
        return 10 * log10(meanSquare)
    }

    /// 点灯させるセグメントの数（0...segmentCount）。範囲の下端で 0、0dBFS 以上で全点灯
    static func litSegmentCount(decibels: Double) -> Int {
        guard decibels > floorDecibels else { return 0 }
        let ratio = min((decibels - floorDecibels) / -floorDecibels, 1)
        return Int((ratio * Double(segmentCount)).rounded(.up))
    }

    /// セグメントの位置（0 始まり）に対応する色。`warningDecibels` 以上はマゼンタ、それ以外はシアン
    static func segmentColor(_ index: Int) -> Color {
        let decibels = floorDecibels + (-floorDecibels) * Double(index + 1) / Double(segmentCount)
        return decibels > warningDecibels ? Theme.accentSecondary : Theme.accent
    }

    /// 表示用の dB 表記（1dB 単位）。範囲の下端より小さいときは「-inf dB」
    static func label(decibels: Double) -> String {
        guard decibels > floorDecibels else { return "-inf dB" }
        return "\(Int(decibels.rounded())) dB"
    }
}

/// プレビュー用の音量 50% のサイン波
private func previewSamples(_ count: Int) -> [Float] {
    (0..<count).map { Float(0.5 * sin(2 * Double.pi * 440 * Double($0) / 48000)) }
}

#Preview("再生中") {
    LevelMeterView(isPlaying: true, readSamples: previewSamples)
        .padding()
        .themedScreen()
}

#Preview("停止中") {
    LevelMeterView(isPlaying: false, readSamples: previewSamples)
        .padding()
        .themedScreen()
}
