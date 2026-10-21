//
//  ThemeColor.swift
//  OneTone
//

import SwiftUI

/// ユーザーが選べるテーマカラー（Discussion #80）。テーマで変わるのはメインの差し色 `accent` と、それに従属する値だけ。
///
/// 背景・パネル・文字色はどのテーマでも変えない。画面の差し色はテーマの `accent` だけにする（Discussion #289 Q3）。
/// `rawValue` は保存値になるので、リリース後に変えると既存ユーザーの選択が失われる。
/// 色コードとコントラスト比の一覧は Issue #89 に載せている。
enum ThemeColor: String, CaseIterable, Identifiable {
    case cyan
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green

    /// 保存値が無いときのテーマ。今のネオンシアンのまま、既存ユーザーの見た目を変えない
    static let `default`: ThemeColor = .cyan

    var id: String { rawValue }

    /// 設定画面に出す名前（言語ごとに訳す）
    var displayName: LocalizedStringResource {
        switch self {
        case .cyan: "Cyan"
        case .blue: "Blue"
        case .purple: "Purple"
        case .pink: "Pink"
        case .red: "Red"
        case .orange: "Orange"
        case .yellow: "Yellow"
        case .green: "Green"
        }
    }

    /// 操作部品の差し色（0xRRGGBB）。背景比 4.5:1 以上
    var accentHex: UInt32 {
        switch self {
        case .cyan: 0x00E5FF
        case .blue: 0x4D9DFF
        case .purple: 0xB07CFF
        case .pink: 0xFF5C9D
        case .red: 0xFF4D4D
        case .orange: 0xFF9F1A
        case .yellow: 0xFFE01A
        case .green: 0x39FF6A
        }
    }

    /// 差し色の上に載せる文字（0xRRGGBB）。どの差し色も明るいため、白ではなく背景と同じ暗色にする
    var onAccentHex: UInt32 {
        Theme.backgroundHex
    }

    /// タイトルのグラデーション（0xRRGGBB）。差し色を中心に、色相を -30° / +30° ずらした色で挟む（彩度・明度は差し色と同じ）。
    /// 大きな文字に使うので、背景比 3:1 以上を下限にしている
    var titleGradientHex: [UInt32] {
        switch self {
        case .cyan: [0x00FF99, 0x00E5FF, 0x0066FF]
        case .blue: [0x4DF6FF, 0x4D9DFF, 0x564DFF]
        case .purple: [0x7C8AFF, 0xB07CFF, 0xF27CFF]
        case .pink: [0xFF5CEF, 0xFF5C9D, 0xFF6D5C]
        case .red: [0xFF4DA6, 0xFF4D4D, 0xFFA64D]
        case .orange: [0xFF2D1A, 0xFF9F1A, 0xECFF1A]
        case .yellow: [0xFF6E1A, 0xFFE01A, 0xACFF1A]
        case .green: [0x6BFF39, 0x39FF6A, 0x39FFCD]
        }
    }

    /// iOS の代替アイコンの名前（Icon Composer の `OneTone/AppIcon-<rawValue>.icon`）。`Tools/draw_app_icon.swift` で作る
    var alternateIconName: String { "AppIcon-\(rawValue)" }

    /// 代替アイコンの名前に対応するテーマ。既定のアイコン（nil）や知らない名前なら nil
    init?(alternateIconName: String?) {
        guard let match = ThemeColor.allCases.first(where: { $0.alternateIconName == alternateIconName }) else { return nil }
        self = match
    }

    var accent: Color { Color(hex: accentHex) }
    var onAccent: Color { Color(hex: onAccentHex) }
    var titleGradient: [Color] { titleGradientHex.map { Color(hex: $0) } }

    /// 選んだテーマを保存する UserDefaults のキー（`@AppStorage`）。端末ごとに保存し、iCloud では同期しない（Discussion #80 Q5）。
    /// 保存値になるので、リリース後に変えると既存ユーザーの選択が失われる
    static let storageKey = "themeColor"

    /// 画面に使うテーマ。スクリーンショットの撮影モードでは、保存値に関わらず既定のテーマで撮る
    static func displayed(stored: ThemeColor, isScreenshotDemo: Bool) -> ThemeColor {
        isScreenshotDemo ? .default : stored
    }
}

private struct ThemeColorKey: EnvironmentKey {
    static let defaultValue = ThemeColor.default
}

extension EnvironmentValues {
    /// 選ばれているテーマ。`ContentView` のルートで注入し、各部品はここから差し色を取る。注入していないプレビューでは既定のテーマ
    var themeColor: ThemeColor {
        get { self[ThemeColorKey.self] }
        set { self[ThemeColorKey.self] = newValue }
    }
}

/// WCAG 2.x の相対輝度によるコントラスト比の計算。テーマの色がコントラストの目安を満たすかの確認に使う
enum ColorContrast {
    /// 0xRRGGBB の sRGB 色の相対輝度（0...1）
    static func relativeLuminance(_ hex: UInt32) -> Double {
        func linear(_ component: UInt32) -> Double {
            let value = Double(component & 0xFF) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(hex >> 16) + 0.7152 * linear(hex >> 8) + 0.0722 * linear(hex)
    }

    /// 2 色のコントラスト比（1...21）。引数の順序によらない
    static func ratio(_ first: UInt32, _ second: UInt32) -> Double {
        let lighter = max(relativeLuminance(first), relativeLuminance(second))
        let darker = min(relativeLuminance(first), relativeLuminance(second))
        return (lighter + 0.05) / (darker + 0.05)
    }
}
