//
//  SettingsView.swift
//  OneTone
//

import SwiftUI

/// 設定画面の中身。macOS は設定ウィンドウ（`Settings` シーン）、iOS はメイン画面から開くシートで同じ View を使う。
/// 選んだ値はその場で `@AppStorage` に保存され、メイン画面にもすぐ反映される
struct SettingsView: View {
    @AppStorage(ThemeColor.storageKey) private var themeColor: ThemeColor = .default

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DeckPanel(title: "THEME COLOR") {
                    ThemeColorPicker(selection: $themeColor)
                }
                #if os(iOS)
                // アイコンはテーマとは別に選ぶ（テーマを変えても連動しない）。macOS のアイコンは変えない
                DeckPanel(title: "APP ICON") {
                    AppIconPicker()
                }
                #endif
                // RESET は常に最後に置く（Discussion #169）。設定項目を足すときもこれより上に足す
                DeckPanel(title: "RESET") {
                    ToneSettingsResetButton()
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        #if os(macOS)
        .frame(width: 420, height: 440)
        #endif
        .themedScreen()
        // 設定画面自体も選んだテーマの差し色で表示する
        .environment(\.themeColor, themeColor)
    }
}

/// 周波数・音量・波形を既定値（440Hz / 50% / Sine）に戻すボタン。取り消せないので確認してから戻す。
/// 開いているメイン画面へは `ToneSettingsStore.didResetNotification` で伝える（設定画面からはメイン画面の状態に直接届かないため）。
/// 他の設定と区別するため、テーマ色を使わずグレーで表示する（押せるまま。無効化ではない）
struct ToneSettingsResetButton: View {
    var store = ToneSettingsStore()
    @State private var isConfirming = false

    var body: some View {
        Button {
            isConfirming = true
        } label: {
            Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                .font(.system(.callout, design: .rounded).weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ResetButtonStyle())
        .padding(4)
        .alert(Text(ToneSettingsResetConfirmation.title), isPresented: $isConfirming) {
            Button("Reset", role: .destructive) { store.reset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ToneSettingsResetConfirmation.message)
        }
    }
}

/// RESET のボタンの見た目。`WaveformButtonStyle` と同じ形・押し込みで、差し色の代わりにグレーを使う。
/// `WaveformButtonStyle` は他の選択ボタンと共有しているので変えずに、RESET だけこちらを使う
private struct ResetButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius)
        configuration.label
            .background(
                ZStack {
                    shape.fill(Theme.surfaceRaised)
                    shape.fill(Theme.textSecondary.opacity(configuration.isPressed ? 0.15 : 0))
                }
            )
            .overlay(shape.strokeBorder(Theme.textDisabled.opacity(0.5), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .contentShape(shape)
    }
}

/// テーマカラーの選択。色見本と名前を並べ、選択中は差し色の枠とチェックで示す（色だけに頼らない）
struct ThemeColorPicker: View {
    @Binding var selection: ThemeColor

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(ThemeColor.allCases) { theme in
                let isSelected = theme == selection
                Button {
                    selection = theme
                } label: {
                    SwatchLabel(color: theme.accent, checkColor: theme.onAccent, name: theme.displayName, isSelected: isSelected)
                }
                .buttonStyle(WaveformButtonStyle(isSelected: isSelected))
                .accessibilityLabel(Text(theme.displayName))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
    }
}

/// 色見本の丸と名前。選択中は丸の上にチェックを載せ、名前を太字にする
private struct SwatchLabel: View {
    let color: Color
    let checkColor: Color
    let name: LocalizedStringResource
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
                .overlay(Circle().strokeBorder(Theme.textDisabled, lineWidth: 1))
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(checkColor)
                    }
                }
            Text(name)
                .font(.system(.caption, design: .rounded).weight(isSelected ? .bold : .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }
}

#if os(iOS)
/// アプリのアイコンの選択（iOS だけ）。既定のアイコン（暗い背景に白い線、中央のバーだけシアン）と、
/// テーマ色ごとの代替アイコン（線をすべてテーマ色にしたもの）から選ぶ。見本の色はアイコンの線の色（既定は白）。
/// 切り替えると OS が確認のダイアログを出す。失敗したら理由を表示する
struct AppIconPicker: View {
    /// 今のアイコン。nil は既定のアイコン
    @State private var current: ThemeColor? = ThemeColor(alternateIconName: UIApplication.shared.alternateIconName)
    @State private var errorMessage: String?
    /// 切り替えの途中か。UIKit は重なった切り替えの順序を保証しないので、終わるまで次の選択を受け付けない
    @State private var isChanging = false

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 8)]
    private let isSupported = UIApplication.shared.supportsAlternateIcons

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: columns, spacing: 8) {
                option(nil, color: Theme.textPrimary, checkColor: Theme.background, name: "Default")
                ForEach(ThemeColor.allCases) { theme in
                    option(theme, color: theme.accent, checkColor: theme.onAccent, name: theme.displayName)
                }
            }
            .disabled(!isSupported || isChanging)
            if !isSupported {
                Text("This device can’t change the app icon.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(4)
        .alert("Couldn’t Change the App Icon", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func option(_ icon: ThemeColor?, color: Color, checkColor: Color, name: LocalizedStringResource) -> some View {
        let isSelected = icon == current
        return Button {
            select(icon)
        } label: {
            SwatchLabel(color: color, checkColor: checkColor, name: name, isSelected: isSelected)
        }
        .buttonStyle(WaveformButtonStyle(isSelected: isSelected))
        .accessibilityLabel("App Icon: \(String(localized: name))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ icon: ThemeColor?) {
        guard icon != current, !isChanging else { return }
        isChanging = true
        Task { @MainActor in
            do {
                try await UIApplication.shared.setAlternateIconName(icon?.alternateIconName)
            } catch {
                errorMessage = error.localizedDescription
            }
            // 成功・失敗どちらでも、実際のアイコンに表示を合わせる
            current = ThemeColor(alternateIconName: UIApplication.shared.alternateIconName)
            isChanging = false
        }
    }
}
#endif

#Preview {
    SettingsView()
}

#Preview("RESET の見た目") {
    DeckPanel(title: "RESET") {
        ToneSettingsResetButton()
    }
    .padding()
    .frame(width: 400)
    .themedScreen()
    .environment(\.themeColor, .pink)
}

#Preview("選択の見た目") {
    ThemeColorPicker(selection: .constant(.pink))
        .padding()
        .frame(width: 400)
        .themedScreen()
        .environment(\.themeColor, .pink)
}
