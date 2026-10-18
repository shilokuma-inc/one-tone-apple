//
//  SampleRingBuffer.swift
//  OneTone
//

import Foundation

/// レンダースレッドで生成した出力サンプルを、波形表示やレベルメーターのためにメインスレッドへ渡すリングバッファ。
///
/// 書き込みはレンダースレッド 1 本、読み出しはメインスレッド 1 本だけを想定する。
/// レンダーブロックではロックもメモリ確保もできないため、領域は init で確保し、`write` は既存の領域に値を置くだけにしている。
/// `Synchronization.Atomic` は macOS 15 以降でしか使えず外部パッケージも足さないので、`AudioManager` と同じく
/// `UnsafeMutablePointer` に置いた書き込み位置を公開する。読み出し中に上書きされて少しずれたサンプルが混ざることはあるが、
/// 表示にしか使わないので許容する。
///
/// 値型にしているのは、レンダーブロックがクラスの参照を持つと呼び出しのたびに参照カウントの操作が入るため。
/// コピーしても同じ領域を指すので、所有者が 1 回だけ `deallocate()` を呼ぶ（レンダーブロックが止まってから）。
struct SampleRingBuffer {
    let capacity: Int
    private let storage: UnsafeMutablePointer<Float>
    /// これまでに書き込んだサンプルの総数。書き込み位置は `totalWritten % capacity` になる
    private let writtenCount: UnsafeMutablePointer<Int>

    init(capacity: Int) {
        precondition(capacity > 0, "capacity は 1 以上にする")
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
        storage.initialize(repeating: 0, count: capacity)
        writtenCount = .allocate(capacity: 1)
        writtenCount.initialize(to: 0)
    }

    /// 所有者が 1 回だけ呼ぶ。以後このバッファ（とそのコピー）は使えない
    func deallocate() {
        storage.deallocate()
        writtenCount.deallocate()
    }

    /// これまでに書き込んだサンプルの総数
    var totalWritten: Int {
        writtenCount.pointee
    }

    /// レンダースレッドから呼ぶ。ロックもメモリ確保もしない
    func write(_ sample: Float) {
        let count = writtenCount.pointee
        storage[count % capacity] = sample
        // サンプルを置いてから位置を進め、読み出し側が書きかけの位置を最新として読まないようにする
        writtenCount.pointee = count &+ 1
    }

    /// 直近 `count` 個のサンプルを古い順に返す。書き込み済みの数・容量を超える分は返さない。
    /// メインスレッドから呼ぶ（配列を確保するので、レンダースレッドからは呼ばない）
    func latest(_ count: Int) -> [Float] {
        let written = writtenCount.pointee
        let available = min(count, written, capacity)
        guard available > 0 else { return [] }
        let start = written - available
        return (0..<available).map { storage[(start + $0) % capacity] }
    }
}
