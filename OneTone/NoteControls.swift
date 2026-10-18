//
//  NoteControls.swift
//  OneTone
//

import SwiftUI

/// 音名モードの操作で使う換算とプリセット。UI から切り離してテストできるようにしている。
/// 音名モードでは周波数を常に半音（12 平均律・A4 = 440Hz）の値にそろえる（Discussion #219 Q4）
enum NoteInput {
    /// 音名のプリセット（低い順）
    static let presets: [MusicalNote] = [
        note(.a, octave: 3),
        note(.c, octave: 4),
        note(.a, octave: 4),
        note(.c, octave: 5),
    ]
    /// オクターブの選択肢（E0〜D#10 のどれかの音を含むオクターブ）
    static let octaves: ClosedRange<Int> = MusicalNote.lowest.octave...MusicalNote.highest.octave

    /// 周波数に最も近い音。範囲外の周波数は端の音（E0 / D#10）、不正な値（0 以下・NaN など）は A4 にする
    static func note(for frequency: Double) -> MusicalNote {
        MusicalNote(nearestTo: frequency) ?? note(.a, octave: 4)
    }

    /// 最寄りの半音の周波数。Hz モードから切り替えたとき・ノブやスライダーを動かしたときに使う
    static func snapped(_ frequency: Double) -> Double {
        note(for: frequency).frequency
    }

    /// 音名とオクターブを選んだときの音。範囲外の組み合わせ（C0 / E10 など）は近い方の端の音にする
    static func note(_ pitchClass: PitchClass, octave: Int) -> MusicalNote {
        if let note = MusicalNote(pitchClass, octave: octave) {
            return note
        }
        return octave <= MusicalNote.lowest.octave ? MusicalNote.lowest : MusicalNote.highest
    }
}

extension MusicalNote {
    /// 半音 `semitones` 個ずらした音。範囲の端で止まる
    func clampedTransposed(by semitones: Int) -> MusicalNote {
        let number = min(max(self.number + semitones, MusicalNote.numberRange.lowerBound), MusicalNote.numberRange.upperBound)
        return MusicalNote(number: number) ?? self
    }
}

/// 今の音名を大きく出し、鳴っている周波数を補足として小さく出す。音名は訳さない
struct NoteDisplay: View {
    let note: MusicalNote

    var body: some View {
        VStack(spacing: 4) {
            Text(verbatim: note.name)
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text("Frequency: \(FrequencyInput.format(note.frequency)) Hz")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .padding()
    }
}

/// 半音ずつ動くスライダー。E0〜D#10 の 120 音を等間隔に並べる
struct NoteSlider: View {
    let note: MusicalNote
    let onChange: (MusicalNote) -> Void

    var body: some View {
        Slider(value: Binding<Double>(
            get: {
                Double(note.number)
            },
            set: { newValue in
                let number = Int(newValue.rounded())
                if let newNote = MusicalNote(number: number), newNote != note {
                    onChange(newNote)
                }
            }
        ), in: Double(MusicalNote.lowest.number)...Double(MusicalNote.highest.number), step: 1) {
            Text("Note")
        }
        .accessibilityValue(Text(verbatim: note.name))
        .padding()
    }
}

/// 音名（C〜B）とオクターブを選ぶメニュー。範囲外の組み合わせは端の音にする
struct NotePicker: View {
    let note: MusicalNote
    let onChange: (MusicalNote) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Picker(selection: Binding(
                get: { note.pitchClass },
                set: { onChange(NoteInput.note($0, octave: note.octave)) }
            )) {
                ForEach(PitchClass.allCases) { pitchClass in
                    Text(verbatim: pitchClass.name).tag(pitchClass)
                }
            } label: {
                Text("Note")
            }
            Picker(selection: Binding(
                get: { note.octave },
                set: { onChange(NoteInput.note(note.pitchClass, octave: $0)) }
            )) {
                ForEach(Array(NoteInput.octaves), id: \.self) { octave in
                    Text(verbatim: String(octave)).tag(octave)
                }
            } label: {
                Text("Octave")
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
    }
}

/// 音名のプリセットを周波数のプリセットと同じパッド風に並べる
struct NotePresetButtons: View {
    let note: MusicalNote
    let onSelect: (MusicalNote) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(NoteInput.presets) { preset in
                let isSelected = preset == note
                Button {
                    onSelect(preset)
                } label: {
                    Text(verbatim: preset.name)
                }
                .buttonStyle(PadButtonStyle(isSelected: isSelected))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(maxWidth: 440)
        .padding()
    }
}

#Preview("A4") {
    VStack {
        FrequencyKnob(frequency: 440, scale: .semitone, onChange: { _ in })
        NoteDisplay(note: NoteInput.note(for: 440))
        NoteSlider(note: NoteInput.note(for: 440), onChange: { _ in })
        NotePicker(note: NoteInput.note(for: 440), onChange: { _ in })
        NotePresetButtons(note: NoteInput.note(for: 440), onSelect: { _ in })
    }
    .padding()
    .themedScreen()
}
