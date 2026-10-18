//
//  MusicalNote.swift
//  OneTone
//

import Foundation

/// オクターブの中の 12 の音（C〜B）。表記はシャープ（`C#`）で、全言語で英語のまま出す（訳さない。Discussion #219 Q6）
enum PitchClass: Int, CaseIterable, Identifiable {
    case c, cSharp, d, dSharp, e, f, fSharp, g, gSharp, a, aSharp, b

    var id: Self { self }

    /// 音名。訳さないので `String` のままにしている
    var name: String {
        switch self {
        case .c: return "C"
        case .cSharp: return "C#"
        case .d: return "D"
        case .dSharp: return "D#"
        case .e: return "E"
        case .f: return "F"
        case .fSharp: return "F#"
        case .g: return "G"
        case .gSharp: return "G#"
        case .a: return "A"
        case .aSharp: return "A#"
        case .b: return "B"
        }
    }
}

/// 12 平均律の 1 音。基準は A4 = 440Hz で固定（Discussion #219 Q7）、オクターブ番号は科学的表記（中央の C = C4）。
///
/// 音は MIDI のノート番号（C4 = 60、A4 = 69。半音ごとに 1 増える）で持つ。
/// アプリの周波数の範囲（`FrequencyInput.range`、20Hz〜20kHz）に入る E0（20.6Hz）〜D#10（19.9kHz）だけを作れる
struct MusicalNote: Hashable, Comparable, Identifiable {
    /// A4 の周波数
    static let referenceFrequency: Double = 440
    /// A4 のノート番号
    static let referenceNumber = 69
    /// 扱える最も低い音（E0、20.6Hz。1 つ下の D#0 は 19.4Hz で 20Hz を下回る）
    static let lowest = MusicalNote(uncheckedNumber: 16)
    /// 扱える最も高い音（D#10、19.9kHz。1 つ上の E10 は 21.1kHz で 20kHz を超える）
    static let highest = MusicalNote(uncheckedNumber: 135)
    /// 扱えるノート番号の範囲
    static let numberRange: ClosedRange<Int> = lowest.number...highest.number
    /// 扱える全部の音（低い順）
    static let all: [MusicalNote] = numberRange.map { MusicalNote(uncheckedNumber: $0) }

    /// MIDI のノート番号（C4 = 60、A4 = 69）
    let number: Int

    var id: Int { number }

    /// ノート番号から作る。扱える範囲（E0〜D#10）の外なら nil
    init?(number: Int) {
        guard Self.numberRange.contains(number) else { return nil }
        self.number = number
    }

    /// 音名とオクターブから作る（`MusicalNote(.a, octave: 4)` = A4）。扱える範囲の外なら nil
    init?(_ pitchClass: PitchClass, octave: Int) {
        self.init(number: (octave + 1) * 12 + pitchClass.rawValue)
    }

    private init(uncheckedNumber: Int) {
        number = uncheckedNumber
    }

    /// 周波数に最も近い音（半音へ四捨五入する）。
    /// 扱える範囲の外の周波数は、近い方の端の音（E0 / D#10）にする。0 以下・無限大・NaN は nil
    init?(nearestTo frequency: Double) {
        guard frequency.isFinite, frequency > 0 else { return nil }
        let exact = Self.exactNumber(for: frequency)
        let clamped = min(max(exact.rounded(.toNearestOrAwayFromZero), Double(Self.numberRange.lowerBound)),
                          Double(Self.numberRange.upperBound))
        self.number = Int(clamped)
    }

    /// 周波数を、ノート番号の小数（A4 = 69.0。半音で 1 ずれる）で表す
    static func exactNumber(for frequency: Double) -> Double {
        Double(referenceNumber) + 12 * log2(frequency / referenceFrequency)
    }

    /// オクターブの中の音（C〜B）
    var pitchClass: PitchClass {
        // 扱える範囲は正のノート番号だけなので、剰余は負にならない
        PitchClass(rawValue: number % 12)!
    }

    /// 科学的表記のオクターブ番号（C4〜B4 が 4）
    var octave: Int {
        number / 12 - 1
    }

    /// 表記（`A4` / `C#5`）。全言語で英語のまま出す
    var name: String {
        "\(pitchClass.name)\(octave)"
    }

    /// 12 平均律の周波数（Hz）
    var frequency: Double {
        Self.referenceFrequency * pow(2, Double(number - Self.referenceNumber) / 12)
    }

    /// 半音 `semitones` 個ずらした音。扱える範囲の外なら nil
    func transposed(by semitones: Int) -> MusicalNote? {
        MusicalNote(number: number + semitones)
    }

    static func < (lhs: MusicalNote, rhs: MusicalNote) -> Bool {
        lhs.number < rhs.number
    }
}
