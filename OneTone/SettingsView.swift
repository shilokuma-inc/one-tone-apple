//
//  SettingsView.swift
//  OneTone
//

import SwiftUI

/// 設定画面の中身。macOS は設定ウィンドウ（`Settings` シーン）、iOS はメイン画面から開くシートで同じ View を使う。
/// 選んだ値はその場で `@AppStorage` に保存され、メイン画面にもすぐ反映される
struct SettingsView: View {
    @AppStorage(ThemeColor.storageKey) private var themeColor: ThemeColor = .default
    @AppStorage(FrequencyMode.storageKey) private var frequencyMode: FrequencyMode = .default

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                DeckPanel(title: "FREQUENCY MODE") {
                    FrequencyModePicker(selection: $frequencyMode)
                }
                DeckPanel(title: "THEME COLOR") {
                    ThemeColorPicker(selection: $themeColor)
                }
                #if os(iOS)
                // アイコンはテーマとは別に選ぶ（テーマを変えても連動しない）。macOS のアイコンは変えない
                DeckPanel(title: "APP ICON") {
                    AppIconPicker()
                }
                #endif
                // 同梱した書体のライセンス表記（OFL の条件）。名前・著作権表示・全文は訳さない
                DeckPanel(title: "LICENSES") {
                    LogoFontLicenseSection()
                }
                // RESET は常に最後に置く（Discussion #169）。設定項目を足すときもこれより上に足す
                DeckPanel(title: "RESET") {
                    ToneSettingsResetButton()
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        #if os(macOS)
        .frame(width: 420, height: 580)
        #endif
        .themedScreen()
        // 設定画面自体も選んだテーマの差し色で表示する
        .environment(\.themeColor, themeColor)
    }
}

/// FREQUENCY パネルの表示モード（Hz / NOTE / CHORD）の選択。名前は英語のまま並べ、選んだモードの説明を下に出す。
/// 選択中は差し色の枠と太字で示す（色だけに頼らない）。切り替えても再生は止めない
struct FrequencyModePicker: View {
    @Binding var selection: FrequencyMode

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(FrequencyMode.allCases) { mode in
                    let isSelected = mode == selection
                    Button {
                        selection = mode
                    } label: {
                        Text(verbatim: mode.label)
                            .font(.system(.callout, design: .rounded).weight(isSelected ? .bold : .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WaveformButtonStyle(isSelected: isSelected))
                    .accessibilityLabel(Text(verbatim: mode.label))
                    .accessibilityHint(Text(mode.summary))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            Text(selection.summary)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(4)
    }
}

/// 周波数・音量・波形と表示モードを既定値（440Hz / 50% / Sine / Hz）に戻すボタン。取り消せないので確認してから戻す。
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

/// ロゴの書体のライセンス表記。書体名（その書体で表示）・著作権表示・ライセンス名を並べ、ボタンで全文をシートに出す。
/// macOS の設定ウィンドウは 420×580 の固定なので、全文はパネルに広げずシートにする
struct LogoFontLicenseSection: View {
    @State private var isShowingFullText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(verbatim: LogoFont.familyName)
                .font(LogoFont.font(size: 20))
                .foregroundStyle(Theme.textPrimary)
            Text(verbatim: LogoFont.copyright)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: LogoFont.licenseName)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Button {
                isShowingFullText = true
            } label: {
                Label("View Full License", systemImage: "doc.text")
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(WaveformButtonStyle(isSelected: false))
            .accessibilityIdentifier("viewFullLicenseButton")
        }
        .padding(4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $isShowingFullText) {
            LicenseTextView(title: LogoFont.licenseName, text: LicenseText.reflowed(LogoFont.licenseText ?? ""))
        }
    }
}

/// ライセンスの全文の表示用の整形
enum LicenseText {
    /// 72 桁前後で折り返してある原文（`OFL.txt`）の、段落の中の改行を空白にする。狭い画面で折り返しが二重になり、行が細切れになるのを防ぐ。
    /// 空行・区切りの線（`---`）・見出し・番号付きの項目（`1)` など）の前後は改行のまま残す。文字は足し引きしない
    static func reflowed(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result = ""
        for index in lines.indices {
            result += lines[index]
            guard index + 1 < lines.count else { break }
            result += joinsWithNext(lines, at: index) ? " " : "\n"
        }
        return result
    }

    private static func joinsWithNext(_ lines: [String], at index: Int) -> Bool {
        let next = lines[index + 1]
        let startsItem = next.range(of: #"^\d+\)"#, options: .regularExpression) != nil
        return !isBreak(lines, at: index) && !isBreak(lines, at: index + 1) && !startsItem
    }

    /// 前後で改行を残す行（空行・区切りの線・見出し）。見出しは空行の直後にある、小文字を含まない行
    /// （DISCLAIMER の本文のように全部大文字の段落は、2 行目からは見出しにしない）
    private static func isBreak(_ lines: [String], at index: Int) -> Bool {
        let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("-") {
            return true
        }
        let startsParagraph = index == 0 || lines[index - 1].trimmingCharacters(in: .whitespaces).isEmpty
        return startsParagraph && !trimmed.contains(where: \.isLowercase)
    }
}

/// ライセンスの全文のシート。原文のまま（訳さない）等幅で出し、選んでコピーできるようにする
private struct LicenseTextView: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(verbatim: title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
                .overlay(Theme.surfaceRaised)
            ScrollView {
                Text(verbatim: text)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .accessibilityIdentifier("licenseFullText")
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 520)
        #endif
        .themedScreen()
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
/// テーマ色ごとの代替アイコン（線をすべてテーマ色にしたもの）から選ぶ。見本はアイコンの縮小表示（`AppIconPreview`）。
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
                option(nil, name: "Default")
                ForEach(ThemeColor.allCases) { theme in
                    option(theme, name: theme.displayName)
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

    private func option(_ icon: ThemeColor?, name: LocalizedStringResource) -> some View {
        let isSelected = icon == current
        return Button {
            select(icon)
        } label: {
            AppIconLabel(icon: icon, name: name, isSelected: isSelected)
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

/// アイコンの縮小表示と名前。選択中はアイコンの右下にチェックを載せ、名前を太字にする（色だけに頼らない）。
/// テーマカラーの選択の `SwatchLabel` とは別にする（テーマカラーの選択の見た目を変えないため）
private struct AppIconLabel: View {
    /// nil は既定のアイコン
    let icon: ThemeColor?
    let name: LocalizedStringResource
    let isSelected: Bool

    @Environment(\.themeColor) private var themeColor

    /// アイコンの一辺（pt）
    static let iconSize: CGFloat = 44

    var body: some View {
        VStack(spacing: 6) {
            AppIconPreview(theme: icon, size: Self.iconSize)
                // アイコンの背景は暗く、同じく暗いボタンの面に埋もれるので、細い縁取りで輪郭を見せる
                .overlay(
                    RoundedRectangle(cornerRadius: Self.iconSize * AppIconPreview.cornerRadiusRatio, style: .continuous)
                        .strokeBorder(Theme.textDisabled.opacity(0.6), lineWidth: 1)
                )
                .overlay(alignment: .bottomTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(themeColor.onAccent)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(themeColor.accent))
                            .overlay(Circle().strokeBorder(Theme.surfaceRaised, lineWidth: 2))
                            .offset(x: 5, y: 5)
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

#Preview("LICENSES") {
    DeckPanel(title: "LICENSES") {
        LogoFontLicenseSection()
    }
    .padding()
    .frame(width: 400)
    .themedScreen()
}

#Preview("選択の見た目") {
    ThemeColorPicker(selection: .constant(.pink))
        .padding()
        .frame(width: 400)
        .themedScreen()
        .environment(\.themeColor, .pink)
}
