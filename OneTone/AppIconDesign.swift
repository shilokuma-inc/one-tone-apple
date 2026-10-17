//
//  AppIconDesign.swift
//  OneTone
//

import CoreGraphics
import SwiftUI

/// アプリアイコンの図柄（「半円 + 5 本のバー」）の寸法と色（Discussion #177 / #208）。
///
/// アイコンを書き出す `Tools/draw_app_icon.swift`（macOS の CLI）と、設定画面のアイコンのプレビューの両方から使う。
/// 描画スクリプトも一緒にコンパイルするので、`#if os(iOS)` に入れず、UIKit に依存させない。
/// ここを変えると `.icon` の見た目も変わるので、変えたら描画スクリプトの `--all` で `.icon` を作り直す。
enum AppIconDesign {
    /// アイコンの寸法。アイコンの一辺を 1 とした値で、y は上から下へ測る。半円は水平線 `horizon` を直径にして下に開く
    enum Geometry {
        /// 半円の輪郭の半径（線の中心まで）
        static let bowlRadius: CGFloat = 0.33
        /// 線の太さ。バーと半円の輪郭で同じにする（線の両端は半円で丸める）
        static let lineWidth: CGFloat = 0.06
        /// バーどうしの間隔
        static let barGap: CGFloat = 0.05
        /// バーの長さ。外側・内側・中央の 3 つを書き、左右に折り返して 5 本にする（左右対称にするため）
        static let barLengths: (outer: CGFloat, inner: CGFloat, center: CGFloat) = (outer: 0.18, inner: 0.32, center: 0.46)
        /// 半円の直径を置く水平線の高さ。中央のバーの上端（horizon - barLengths.center / 2）から
        /// 半円の輪郭の下端（horizon + bowlRadius + lineWidth / 2）までが、上下の中央に来るように求める
        static let horizon: CGFloat = 0.5 - (bowlRadius + lineWidth / 2 - barLengths.center / 2) / 2

        /// 左から順に 5 本のバーの矩形。縦は水平線を中心にする
        static var barRects: [CGRect] {
            let lengths = [barLengths.outer, barLengths.inner, barLengths.center, barLengths.inner, barLengths.outer]
            return lengths.enumerated().map { index, length in
                let centerX = 0.5 + CGFloat(index - 2) * (lineWidth + barGap)
                return CGRect(x: centerX - lineWidth / 2, y: horizon - length / 2, width: lineWidth, height: length)
            }
        }

        /// 水平線から下の半円の円弧。端から端へ 1 本で描くと小さく書き出したときに左右でアンチエイリアスがずれるので、
        /// 下端から右端と左端へ 2 本に分けて描く（1 つのパスにまとめて 1 回で線を引くので、重なりは二重に塗られない）
        static var bowlArc: CGPath {
            let path = CGMutablePath()
            let center = CGPoint(x: 0.5, y: horizon)
            // y が下向きの座標なので、角度 π/2 が下端。π/2 → 0 で右端へ、π/2 → π で左端へ回る
            path.addArc(center: center, radius: bowlRadius, startAngle: .pi / 2, endAngle: 0, clockwise: true)
            path.move(to: CGPoint(x: 0.5, y: horizon + bowlRadius))
            path.addArc(center: center, radius: bowlRadius, startAngle: .pi / 2, endAngle: .pi, clockwise: false)
            return path
        }

        static func bar(_ rect: CGRect) -> CGPath {
            CGPath(roundedRect: rect, cornerWidth: lineWidth / 2, cornerHeight: lineWidth / 2, transform: nil)
        }
    }

    /// 塗りに使う色。既定のアイコンは白い線に中央のバーだけシアン、代替アイコンは線をすべてテーマ色にする
    struct Palette: Equatable {
        /// 背景（Theme.background）
        var background: Color
        /// 半円と両側のバーの線。既定のアイコンは白（Theme.textPrimary）、代替アイコンはテーマ色
        var line: Color
        /// 中央のバー（テーマ色。既定のアイコンはシアン）
        var accent: Color

        /// theme が nil なら既定のアイコン、テーマ色を渡すとその色の代替アイコンの色
        init(theme: ThemeColor?) {
            background = Theme.background
            accent = (theme ?? .default).accent
            line = theme == nil ? Theme.textPrimary : accent
        }
    }
}
