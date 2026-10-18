//
//  TitleView.swift
//  OneTone
//

import SwiftUI

/// 虹色のタイトル。グラデーションは常に表示し、色相の回転と発光は再生中だけにする（停止中は静か）。
/// Reduce Motion がオンのとき、またはスクリーンショットの撮影モードのときは回転させない
struct TitleView: View {
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.freezesAnimations) private var freezesAnimations
    /// 回っていた時間だけを数える時計。止めている間の時間を角度に含めず、再開したとき色が飛ばないようにする
    @State private var clock = PausableClock()

    /// 色相を回すか。再生中かつ Reduce Motion がオフで、撮影モードでもないときだけ回す
    private var isAnimating: Bool {
        isPlaying && !reduceMotion && !freezesAnimations
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isAnimating)) { context in
            title(hue: Self.hueDegrees(at: clock.elapsed(at: context.date)))
        }
        // 表示時と、回す／止めるが切り替わるたびに時計を動かす・止める
        // （2 引数の onChange は macOS 14 からなので、表示時にも呼ばれる task(id:) を使う）
        .task(id: isAnimating) {
            if isAnimating {
                clock.start(at: Date())
            } else {
                clock.stop(at: Date())
            }
        }
    }

    private func title(hue: Double) -> some View {
        Text("One Tone")
            .foregroundStyle(Theme.textPrimary)
            .font(.custom("Helvetica Neue", size: 60))
            .fontWeight(.bold)
            // iPhone の幅では 60pt のままだとタイトルが収まらないので縮小を許可する
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: Theme.rainbow),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .mask(
                    Text("One Tone")
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                )
                .font(.custom("Helvetica Neue", size: 60))
                .fontWeight(.bold)
                .hueRotation(Angle(degrees: hue))
            )
            .neonGlow(Theme.accentSecondary, isActive: isPlaying)
    }

    /// 回っていた時間（秒）に対する色相の回転角（0..<360）。`Theme.titleHueCyclePeriod` 秒で 1 周する
    static func hueDegrees(at time: TimeInterval) -> Double {
        let progress = time / Theme.titleHueCyclePeriod
        return (progress - floor(progress)) * 360
    }
}

/// 動いていた時間だけを積み上げる時計。止めている間は進まない
struct PausableClock {
    /// 直前に止めるまでに動いていた時間の合計
    private(set) var accumulated: TimeInterval = 0
    /// 動いている間は動き始めた時刻、止まっている間は nil
    private(set) var startedAt: Date?

    mutating func start(at date: Date) {
        guard startedAt == nil else { return }
        startedAt = date
    }

    mutating func stop(at date: Date) {
        guard let startedAt else { return }
        accumulated += max(0, date.timeIntervalSince(startedAt))
        self.startedAt = nil
    }

    /// `date` の時点までに動いていた時間の合計
    func elapsed(at date: Date) -> TimeInterval {
        guard let startedAt else { return accumulated }
        return accumulated + max(0, date.timeIntervalSince(startedAt))
    }
}

#Preview("停止中") {
    TitleView(isPlaying: false)
        .padding()
        .themedScreen()
}

#Preview("再生中") {
    TitleView(isPlaying: true)
        .padding()
        .themedScreen()
}
