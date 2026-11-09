//
//  ChordControls.swift
//  OneTone
//

import SwiftUI

/// 和音モードの操作で使う定義。UI から切り離してテストできるようにしている
enum ChordInput {
    /// パッドに並べるよく使うコード。ポップスの定番の進行（C - G - Am - F など）で使うものを、4 個ずつ 2 段に並べる
    static let pads: [Chord] = [
        Chord(root: .c, quality: .major),
        Chord(root: .g, quality: .major),
        Chord(root: .a, quality: .minor),
        Chord(root: .f, quality: .major),
        Chord(root: .d, quality: .major),
        Chord(root: .e, quality: .minor),
        Chord(root: .e, quality: .major),
        Chord(root: .d, quality: .minor),
    ]
    /// パッドの 1 段に並べる数
    static let padsPerRow = 4
    /// 和音モードを初めて開いたときのコード
    static let defaultChord = Chord(root: .c, quality: .major)

    /// 鳴らす周波数（構成音を低い順に、最大 `ToneFrequencies.maxCount` 個）
    static func frequencies(of chord: Chord) -> ToneFrequencies {
        ToneFrequencies(Array(chord.frequencies.prefix(ToneFrequencies.maxCount)))
    }

    /// 根音を選び直したコード（種類はそのまま）
    static func chord(_ chord: Chord, withRoot root: PitchClass) -> Chord {
        Chord(root: root, quality: chord.quality)
    }

    /// 種類を選び直したコード（根音はそのまま）
    static func chord(_ chord: Chord, withQuality quality: ChordQuality) -> Chord {
        Chord(root: chord.root, quality: quality)
    }

    /// 根音のボタンの 1 段に並べる数（12 個を 2 段に）
    static let rootsPerRow = 6

    /// 構成音の表記（`C4 · E4 · G4`）。音名は訳さない
    static func notesLabel(of chord: Chord) -> String {
        chord.notes.map(\.name).joined(separator: " · ")
    }
}

/// 今のコード名を大きく出し、構成音を下に小さく出す。コード名・音名は訳さない
struct ChordDisplay: View {
    let chord: Chord

    var body: some View {
        VStack(spacing: 4) {
            Text(verbatim: chord.name)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(verbatim: ChordInput.notesLabel(of: chord))
                .font(.system(.callout, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .padding()
    }
}

/// よく使うコードを周波数のプリセットと同じパッド風に、4 個ずつ 2 段に並べる。選ばれたコードを `onSelect` で親に渡す
struct ChordPadButtons: View {
    let chord: Chord
    let onSelect: (Chord) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: ChordInput.padsPerRow)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(ChordInput.pads) { pad in
                let isSelected = pad == chord
                Button {
                    onSelect(pad)
                } label: {
                    Text(verbatim: pad.name)
                }
                .buttonStyle(PadButtonStyle(isSelected: isSelected))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: 440)
        .padding()
    }
}

/// 根音（C〜B の 12 個）と種類（メジャー / マイナー）を組み合わせてコードを選ぶ。パッドに無いコードもここから選べる。
/// 根音は 6 個ずつ 2 段に並べる。選択中は差し色の枠と太字・`.isSelected` で示す（色だけに頼らない）
struct ChordBuilder: View {
    let chord: Chord
    let onSelect: (Chord) -> Void

    private let rootColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: ChordInput.rootsPerRow)

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: rootColumns, spacing: 6) {
                ForEach(PitchClass.allCases) { root in
                    let isSelected = root == chord.root
                    Button {
                        onSelect(ChordInput.chord(chord, withRoot: root))
                    } label: {
                        Text(verbatim: root.name)
                            .font(.system(.callout, design: .rounded).weight(isSelected ? .bold : .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WaveformButtonStyle(isSelected: isSelected))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            HStack(spacing: 8) {
                ForEach(ChordQuality.allCases) { quality in
                    let isSelected = quality == chord.quality
                    Button {
                        onSelect(ChordInput.chord(chord, withQuality: quality))
                    } label: {
                        Text(quality.label)
                            .font(.system(.callout, design: .rounded).weight(isSelected ? .bold : .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WaveformButtonStyle(isSelected: isSelected))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
        }
        .frame(maxWidth: 440)
        .padding(.horizontal)
        .padding(.bottom)
    }
}

#Preview("C を選択中") {
    VStack {
        ChordDisplay(chord: ChordInput.defaultChord)
        ChordPadButtons(chord: ChordInput.defaultChord, onSelect: { _ in })
        ChordBuilder(chord: ChordInput.defaultChord, onSelect: { _ in })
    }
    .padding()
    .themedScreen()
}
