//
//  TutorialView.swift
//  OneTone
//

import SwiftUI

/// チュートリアルの画面。`Tutorial.pages` を 1 ページずつ表示する。
///
/// iOS はスワイプでページを送り（`TabView` の page スタイル）、macOS は Back / Next ボタンとページインジケーターで送る。
/// Skip・最後のページの完了・閉じるボタンのどれで閉じても、`onDismiss` で閉じ方を呼び出し元に伝える（どれも既読にする）。
/// シートを下へスワイプするなど、この画面の外で閉じられた場合は呼び出し元が `.closed` として扱う
struct TutorialView: View {
    let pages: [TutorialPage]
    let onDismiss: (TutorialDismissal) -> Void

    @State private var pager: TutorialPager
    @Environment(\.themeColor) private var themeColor
    /// 周波数・波形ページの試聴。メイン画面とは別の音で鳴らす
    @StateObject private var trialPlayer: TutorialTrialPlayer

    init(
        pages: [TutorialPage] = Tutorial.pages,
        trialPlayer: @autoclosure @escaping () -> TutorialTrialPlayer = TutorialTrialPlayer(),
        onDismiss: @escaping (TutorialDismissal) -> Void
    ) {
        self.pages = pages
        self.onDismiss = onDismiss
        _pager = State(initialValue: TutorialPager(pageCount: pages.count))
        _trialPlayer = StateObject(wrappedValue: trialPlayer())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            pageContent
            footer
        }
        #if os(macOS)
        .frame(width: TutorialLayout.macSize.width, height: TutorialLayout.macSize.height)
        #endif
        .themedScreen()
        // 閉じたら試聴中の音を止める（ページを移ったときは showPage で止める）
        .onDisappear {
            trialPlayer.stop()
        }
    }

    // MARK: - 上部（閉じる・Skip）

    private var header: some View {
        HStack {
            Button {
                onDismiss(.closed)
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .accessibilityLabel("Close Tutorial")
            // macOS は Esc、iOS はハードウェアキーボードの Esc で閉じられる
            .keyboardShortcut(.cancelAction)

            Spacer()

            // 最後のページでは完了ボタンと役割が重なるので出さない（位置がずれないよう透明にして残す）
            Button("Skip") {
                onDismiss(.skipped)
            }
            .buttonStyle(.plain)
            .font(.body.weight(.semibold))
            .foregroundStyle(themeColor.accent)
            .opacity(pager.isLastPage ? 0 : 1)
            .disabled(pager.isLastPage)
            .accessibilityHidden(pager.isLastPage)
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }

    // MARK: - ページ

    @ViewBuilder
    private var pageContent: some View {
        #if os(iOS)
        TabView(selection: pageSelection) {
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                TutorialPageView(page: page, trialPlayer: trialPlayer)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        #else
        TutorialPageView(page: pages[pager.index], trialPlayer: trialPlayer)
            .id(pager.index)
            .transition(.opacity)
        #endif
    }

    /// `TabView` の選択とページ送りの状態をつなぐ
    private var pageSelection: Binding<Int> {
        Binding(get: { pager.index }, set: { showPage($0) })
    }

    /// ページを移る。前のページで試聴中の音は止める
    private func showPage(_ index: Int) {
        guard index != pager.index else { return }
        trialPlayer.stop()
        withAnimation { pager.show(index) }
    }

    // MARK: - 下部（ページ送り・完了）

    private var footer: some View {
        HStack(spacing: 16) {
            #if os(macOS)
            Button("Back") {
                showPage(pager.index - 1)
            }
            .buttonStyle(TutorialSecondaryButtonStyle())
            .opacity(pager.isFirstPage ? 0 : 1)
            .disabled(pager.isFirstPage)
            .accessibilityHidden(pager.isFirstPage)

            Spacer()

            TutorialPageIndicator(pageCount: pages.count, index: pager.index)

            Spacer()
            #endif

            primaryButton
        }
        .padding()
    }

    /// 最後のページでは完了、それ以外では次のページへ
    private var primaryButton: some View {
        Button {
            if pager.isLastPage {
                onDismiss(.completed)
            } else {
                showPage(pager.index + 1)
            }
        } label: {
            Text(pager.isLastPage ? "Get Started" : "Next")
                #if os(iOS)
                .frame(maxWidth: .infinity)
                #endif
        }
        .buttonStyle(TutorialPrimaryButtonStyle())
        .keyboardShortcut(.defaultAction)
    }
}

/// 1 ページ分の表示（画面のスクリーンショット・タイトル・本文・試聴・注意書き）
struct TutorialPageView: View {
    let page: TutorialPage
    let trialPlayer: TutorialTrialPlayer
    @Environment(\.themeColor) private var themeColor

    /// 注意書きの文字の色（0xRRGGBB）。ほかの部品と同じくテーマの差し色にする（Discussion #289 Q3）。
    /// 面 `Theme.surface` の上に載せるので、どのテーマでも 4.5:1 以上あることをテストで確かめている
    static func cautionHex(for theme: ThemeColor) -> UInt32 {
        theme.accentHex
    }

    /// 画面のスクリーンショット。まだ撮っていないページは、画像の代わりにページの記号を大きく出す
    @ViewBuilder
    private var pageImage: some View {
        if TutorialImage.exists(named: page.imageName) {
            Image(page.imageName)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius).strokeBorder(Theme.surfaceRaised, lineWidth: 1))
        } else {
            Image(systemName: page.placeholderSymbol)
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.surface))
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            pageImage
                .frame(maxHeight: .infinity)
                // 画像は画面の見本で、内容は下の文章で説明する
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(page.title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(page.message)
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let trial = page.trial {
                    TutorialTrialButtons(sounds: trial.sounds, player: trialPlayer)
                }

                if let caution = page.caution {
                    Label {
                        Text(caution)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color(hex: Self.cautionHex(for: themeColor)))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.surface))
                }
            }
            .frame(maxWidth: 480)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        #if os(iOS)
        // ページインジケーターと重ならないよう下に余白をとる
        .padding(.bottom, 48)
        #endif
    }
}

/// 試聴のボタン。周波数ページは 1 つ（440 Hz）、波形ページは波形ごとに並べる。
/// 鳴っているボタンは差し色の枠とスピーカーのアイコンで示し、もう一度押すと止まる
struct TutorialTrialButtons: View {
    let sounds: [TutorialTrialPlayer.Sound]
    @ObservedObject var player: TutorialTrialPlayer
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        // 波形ごとのボタンは 2 列に並べる。狭い iPhone で 4 つを 1 行に置くと「Sawtooth」などが読めなくなる
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: min(sounds.count, 2)), spacing: 8) {
            ForEach(sounds, id: \.self) { sound in
                let isPlaying = player.playing == sound
                Button {
                    player.toggle(sound)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.fill")
                            .frame(width: 20)
                        Text(label(for: sound))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .font(.system(.callout, design: .rounded).weight(isPlaying ? .bold : .medium))
                    .foregroundStyle(isPlaying ? themeColor.accent : Theme.textPrimary)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(WaveformButtonStyle(isSelected: isPlaying))
                .accessibilityLabel(isPlaying ? "Stop \(label(for: sound))" : "Play \(label(for: sound))")
            }
        }
        .frame(maxWidth: sounds.count == 1 ? 200 : 360)
        .padding(.top, 4)
    }

    /// 1 つだけなら周波数、波形ごとなら波形の名前を出す
    private func label(for sound: TutorialTrialPlayer.Sound) -> String {
        sounds.count == 1 ? "\(FrequencyInput.presetLabel(sound.frequency))" : sound.waveform.displayName
    }
}

/// macOS のページインジケーター。今のページだけ差し色で塗り、幅も広げて色以外でも分かるようにする
struct TutorialPageIndicator: View {
    let pageCount: Int
    let index: Int
    @Environment(\.themeColor) private var themeColor

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { page in
                Capsule()
                    .fill(page == index ? themeColor.accent : Theme.textDisabled)
                    .frame(width: page == index ? 20 : 8, height: 8)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(index + 1) of \(pageCount)")
    }
}

/// 次へ・完了のボタン。差し色で塗る
private struct TutorialPrimaryButtonStyle: ButtonStyle {
    @Environment(\.themeColor) private var themeColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(themeColor.onAccent)
            .padding(.vertical, 10)
            .padding(.horizontal, 24)
            .background(Capsule().fill(themeColor.accent.opacity(configuration.isPressed ? 0.7 : 1)))
            .contentShape(Capsule())
    }
}

/// 戻るボタン。面の色で目立たせない
private struct TutorialSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 10)
            .padding(.horizontal, 24)
            .background(Capsule().fill(Theme.surfaceRaised.opacity(configuration.isPressed ? 0.6 : 1)))
            .contentShape(Capsule())
    }
}

/// チュートリアルの画面の大きさ
enum TutorialLayout {
    /// macOS のシートの大きさ（pt）。画像（16:10）と本文が縦に収まる大きさ
    static let macSize = CGSize(width: 640, height: 640)
}

#Preview("Tutorial") {
    TutorialView(onDismiss: { _ in })
}

#Preview("Waveform page") {
    TutorialPageView(page: Tutorial.pages[4], trialPlayer: TutorialTrialPlayer(makeAudioManager: { AudioManager(startsEngine: false) }))
        .themedScreen()
}

/// チュートリアルの画像がアセットにあるか。撮り直す前の新しいページでは画像セットが無い
enum TutorialImage {
    static func exists(named name: String) -> Bool {
        #if os(iOS)
        UIImage(named: name) != nil
        #else
        NSImage(named: name) != nil
        #endif
    }
}
