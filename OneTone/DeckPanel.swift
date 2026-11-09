//
//  DeckPanel.swift
//  OneTone
//

import SwiftUI

/// DJ 機材の操作パネルのように、関連する部品を 1 枚の面にまとめる
struct DeckPanel<Content: View>: View {
    /// 見出し（FREQUENCY / OUTPUT）。機材の刻印として英語のまま出すので、`String` で受けて訳さない
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .tracking(2)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            content
        }
        .padding(12)
        .frame(maxWidth: DeckLayout.panelMaxWidth)
        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius + 4).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius + 4).strokeBorder(Theme.surfaceRaised, lineWidth: 1))
    }
}

/// 画面幅に応じた並べ方。macOS・iPhone・iPad で同じデザインを使い、並びだけを変える
enum DeckLayout {
    /// この幅以上なら 2 枚のパネルを横に並べる（iPad の縦向き 768pt や広げた macOS のウィンドウ）
    static let sideBySideMinWidth: CGFloat = 760
    /// パネル 1 枚の最大幅。広い画面で部品が間延びしないようにする
    static let panelMaxWidth: CGFloat = 480
    /// macOS のウィンドウをこれより小さくできないようにする（iPhone の幅と同程度。部品が切れない最小）
    static let minimumWindowSize = CGSize(width: 380, height: 560)

    static func isSideBySide(width: CGFloat) -> Bool {
        width >= sideBySideMinWidth
    }
}

#Preview {
    DeckPanel(title: "FREQUENCY") {
        FrequencyKnob(frequency: 440, onChange: { _ in })
        FrequencyPresetButtons(frequency: 440, onSelect: { _ in })
    }
    .padding()
    .themedScreen()
}
