//
//  FrequencyControls.swift
//  OneTone
//

import SwiftUI

/// 周波数を対数スケールで操作するスライダー。変更は `onChange` を通して親の 1 か所に集める
struct FrequencySlider: View {
    let frequency: Double
    let onChange: (Double) -> Void

    var body: some View {
        Slider(value: Binding<Double>(
            get: {
                log10(frequency)
            },
            set: { newValue in
                onChange(pow(10, newValue))
            }
        ), in: log10(20)...log10(20000), step: 0.02) {
            Text("Frequency")
        }
        .padding()
    }
}

/// 現在の周波数の表示
struct FrequencyDisplay: View {
    let frequency: Double

    var body: some View {
        Text("Frequency: \(FrequencyInput.format(frequency)) Hz")
            .padding()
    }
}

/// 周波数の数値入力欄。確定時の検証と反映は親が `onSubmit` で行う
struct FrequencyTextField: View {
    @Binding var text: String
    let onSubmit: () -> Void

    var body: some View {
        HStack {
            TextField("Frequency", text: $text)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                #if os(iOS)
                // decimalPad には確定キーが無く onSubmit が呼べないため、確定キーのある数字キーボードにする
                .keyboardType(.numbersAndPunctuation)
                #endif
                .submitLabel(.done)
                .onSubmit(onSubmit)
            Text("Hz")
        }
        .textFieldStyle(.roundedBorder)
    }
}

#Preview {
    VStack {
        FrequencySlider(frequency: 440, onChange: { _ in })
        FrequencyDisplay(frequency: 440)
        FrequencyTextField(text: .constant("440"), onSubmit: {})
    }
    .padding()
    .themedScreen()
}
