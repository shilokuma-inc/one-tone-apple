//
//  Chord.swift
//  OneTone
//

import Foundation

/// 和音の種類。今はメジャーとマイナーだけ（Discussion #219 Q2）。種類を足すときは case と `intervals` / `suffix` を足す。
/// rawValue は保存に使うので、一度入れたら変えない
enum ChordQuality: String, CaseIterable, Identifiable {
    case major
    case minor

    var id: Self { self }

    /// 根音からの半音の数（基本形。低い順）
    var intervals: [Int] {
        switch self {
        case .major: return [0, 4, 7]
        case .minor: return [0, 3, 7]
        }
    }

    /// コード名で根音の後ろに付ける記号（`C` / `Cm`）。訳さないので `String` のままにしている
    var suffix: String {
        switch self {
        case .major: return ""
        case .minor: return "m"
        }
    }
}

/// 和音（根音と種類）。根音を `rootOctave` に置いた基本形で鳴らす。
/// コード名は全言語で英語のまま出す（`C` / `Am` / `F#m`。Discussion #219 Q6）
struct Chord: Hashable, Identifiable {
    /// 根音を置くオクターブ（C4〜B4）。構成音は C4（262Hz）〜F#5（740Hz）に収まる
    static let rootOctave = 4
    /// 根音 12 個 × 種類の全部（根音の順、同じ根音ではメジャーが先）
    static let all: [Chord] = PitchClass.allCases.flatMap { root in
        ChordQuality.allCases.map { Chord(root: root, quality: $0) }
    }

    var root: PitchClass
    var quality: ChordQuality

    var id: String { name }

    /// コード名（`C` / `C#m`）
    var name: String {
        root.name + quality.suffix
    }

    /// 構成音（低い順。根音は `rootOctave`）
    var notes: [MusicalNote] {
        // 根音の位置は C4〜B4、最も高い構成音でも F#5 なので扱える範囲（E0〜D#10）の外にはならない
        guard let rootNote = MusicalNote(root, octave: Self.rootOctave) else {
            assertionFailure("\(name) の根音が扱える範囲の外")
            return []
        }
        let notes = quality.intervals.compactMap { rootNote.transposed(by: $0) }
        assert(notes.count == quality.intervals.count, "\(name) の構成音が扱える範囲の外")
        return notes
    }

    /// 構成音の周波数（Hz。低い順）
    var frequencies: [Double] {
        notes.map(\.frequency)
    }
}
