//
//  TutorialButton.swift
//  OneTone
//

import SwiftUI

/// 画面のコンテンツ左上に重ねる「？」ボタン。いつでもチュートリアルを開き直せる
struct TutorialButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: TutorialButtonLayout.iconSize, weight: .regular))
                .foregroundStyle(Theme.textSecondary)
                // 押せる範囲はアイコンより広くとる（iOS の推奨 44pt）
                .frame(width: TutorialButtonLayout.hitSize, height: TutorialButtonLayout.hitSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(TutorialButtonLayout.margin)
        .accessibilityLabel("Show Tutorial")
        .help("Show Tutorial")
    }
}

/// 「？」ボタンの大きさと余白（pt）
enum TutorialButtonLayout {
    static let iconSize: CGFloat = 22
    static let hitSize: CGFloat = 44
    /// コンテンツの端からの余白。iOS はセーフエリアの内側、macOS はタイトルバーの下から測る
    static let margin: CGFloat = 4
}

#Preview {
    TutorialButton(action: {})
        .themedScreen()
}
