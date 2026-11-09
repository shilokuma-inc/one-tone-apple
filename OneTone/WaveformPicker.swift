//
//  WaveformPicker.swift
//  OneTone
//

import SwiftUI

/// 波形の切替。波形の形のアイコンと名前を並べたセレクタで、選ばれた波形を `onChange` で親に渡す。
/// 選択中は色だけでなく、枠の太さとラベルの太さでも区別する
struct WaveformPicker: View {
    let waveform: Waveform
    let onChange: (Waveform) -> Void
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Waveform.allCases) { candidate in
                let isSelected = candidate == waveform
                Button {
                    onChange(candidate)
                } label: {
                    VStack(spacing: 6) {
                        WaveformIcon(waveform: candidate)
                            .stroke(
                                isSelected ? themeColor.accent : Theme.textSecondary,
                                style: StrokeStyle(lineWidth: isSelected ? 2.5 : 1.5, lineCap: .round, lineJoin: .round)
                            )
                            .frame(width: 36, height: 18)
                        Text(candidate.displayName)
                            .font(.system(.caption, design: .rounded).weight(isSelected ? .bold : .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(WaveformButtonStyle(isSelected: isSelected))
                .accessibilityLabel(candidate.displayName)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: 440)
        .padding()
    }
}

/// 波形セレクタの 1 つ分の枠。選択中は差し色の太い枠と面の差し色、押している間は少し沈む
struct WaveformButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.themeColor) private var themeColor

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius)
        configuration.label
            .background(
                ZStack {
                    shape.fill(Theme.surfaceRaised)
                    shape.fill(themeColor.accent.opacity((isSelected ? 0.15 : 0) + (configuration.isPressed ? 0.15 : 0)))
                }
            )
            .overlay(
                shape.strokeBorder(
                    isSelected ? themeColor.accent : Theme.textDisabled.opacity(0.5),
                    lineWidth: isSelected ? 2 : 1
                )
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .contentShape(shape)
    }
}

/// 波形 1 周期分の形。音の定義（`Waveform.value(at:)`）から描くので、鳴る音と見た目がずれない
struct WaveformIcon: Shape {
    let waveform: Waveform

    /// 1 周期を何点で描くか。矩形波・ノコギリ波の段差がほぼ垂直に見える細かさにしている
    static let sampleCount = 120

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = Self.points(for: waveform, in: rect)
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }

    /// 1 周期（位相 0...1）を `rect` に収めた点の列。値 1 が上端、-1 が下端になる
    static func points(for waveform: Waveform, in rect: CGRect) -> [CGPoint] {
        (0...sampleCount).map { index in
            let phase = Double(index) / Double(sampleCount)
            // 位相 1 は次の周期の 0 と同じなので、1 周期の終わりとして 0 直前の値を使う
            let value = waveform.value(at: index == sampleCount ? 1 - 1e-9 : phase)
            return CGPoint(
                x: rect.minX + rect.width * phase,
                y: rect.midY - rect.height / 2 * value
            )
        }
    }
}

#Preview {
    VStack {
        WaveformPicker(waveform: .sine, onChange: { _ in })
        WaveformPicker(waveform: .sawtooth, onChange: { _ in })
    }
    .themedScreen()
}
