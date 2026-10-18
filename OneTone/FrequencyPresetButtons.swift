//
//  FrequencyPresetButtons.swift
//  OneTone
//

import SwiftUI

/// 周波数のプリセットを DJ 機材のパッド風に並べる。選ばれた値を `onSelect` で親に渡す。
/// 今の周波数と一致するパッドは「選択中」として、色だけでなく枠の太さとインジケーターの点灯でも示す
struct FrequencyPresetButtons: View {
    let frequency: Double
    let onSelect: (Double) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(FrequencyInput.presets, id: \.self) { preset in
                let isSelected = FrequencyInput.isPresetSelected(preset, frequency: frequency)
                Button {
                    onSelect(preset)
                } label: {
                    Text(FrequencyInput.presetLabel(preset))
                }
                .buttonStyle(PadButtonStyle(isSelected: isSelected))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: 440)
        .padding()
    }
}

/// パッド風のボタン。押している間は少し沈んで明るくなり、押したことが手応えとして分かるようにする
struct PadButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius)
        VStack(spacing: 6) {
            // 選択中は点灯した丸、非選択は輪郭だけの丸。色が分からなくても形で区別できる
            Circle()
                .fill(isSelected ? Theme.accent : Color.clear)
                .overlay(Circle().stroke(isSelected ? Theme.accent : Theme.textDisabled, lineWidth: 1.5))
                .frame(width: 8, height: 8)
            configuration.label
                .font(.system(.callout, design: .rounded).weight(isSelected ? .bold : .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(
            ZStack {
                shape.fill(Theme.surfaceRaised)
                // 選択中は差し色をうっすら重ね、押している間はさらに明るくする
                shape.fill(Theme.accent.opacity((isSelected ? 0.15 : 0) + (configuration.isPressed ? 0.15 : 0)))
            }
        )
        .overlay(
            shape.strokeBorder(
                isSelected ? Theme.accent : Theme.textDisabled.opacity(0.5),
                lineWidth: isSelected ? 2 : 1
            )
        )
        .scaleEffect(configuration.isPressed ? 0.96 : 1)
        .contentShape(shape)
    }
}

#Preview("440Hz を選択中") {
    FrequencyPresetButtons(frequency: 440, onSelect: { _ in })
        .themedScreen()
}

#Preview("どれも選択していない") {
    FrequencyPresetButtons(frequency: 523, onSelect: { _ in })
        .themedScreen()
}
