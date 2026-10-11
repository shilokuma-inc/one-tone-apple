// アプリアイコンを Core Graphics で描き、PNG に書き出す（Discussion #177）。
// 「半円 + 5 本のバー」のモチーフを、白黒を基調にシアンを差し色にして描く（PR #179 で 3 案から選んだ案B「ライン」）。
// 全面をアプリの背景と同じ暗色にし、半円は輪郭だけの線、バーは線で描く。線は白で、中央のバーだけシアン。
// 角丸・影・余白は描かない（iOS と macOS 26 は OS がマスクする。macOS 14 / 15 向けの角丸の画像は、.icon から Xcode が書き出す想定）。
// 正方形の全面を塗り、左右対称に描く。
// 色は ThemeColor.swift / Theme.swift の値をそのまま使う（一緒にコンパイルする）。
//
//   swiftc -O -parse-as-library Tools/draw_app_icon.swift OneTone/ThemeColor.swift OneTone/Theme.swift -o "$TMPDIR/draw_app_icon"
//   "$TMPDIR/draw_app_icon" <出力 PNG> [--size <px>] [--theme <ThemeColor の rawValue>]
//
// --size は一辺のピクセル数（既定 1024）。--theme を付けると、そのテーマ色の代替アイコンの塗り方で描く（付けなければ既定のアイコン）。
// 出力はアルファ無しの RGB（App Store Connect はアルファ付きのアイコンを受け付けない）。

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

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

/// 塗りに使う色。既定のアイコンは白黒にシアン、代替アイコンはテーマ色を差し色にする
struct Palette {
    /// 白（Theme.textPrimary）
    var light: CGColor
    /// 黒（Theme.background）
    var dark: CGColor
    /// 差し色（テーマ色）
    var accent: CGColor
    /// 代替アイコンの塗り方にするか
    var isAlternate: Bool

    init(theme: ThemeColor?) {
        light = Self.cgColor(Theme.textPrimary)
        dark = Self.cgColor(Theme.background)
        accent = Self.cgColor((theme ?? .default).accent)
        isAlternate = theme != nil
    }

    static func cgColor(_ color: Color) -> CGColor {
        color.resolve(in: EnvironmentValues()).cgColor
    }
}

enum IconDrawing {
    /// 一辺 1 の座標（y は下向き）に描く。既定のアイコンは白い線に中央のバーだけ差し色、代替アイコンは線をすべて差し色にする
    static func draw(palette: Palette, in context: CGContext) {
        let line = palette.isAlternate ? palette.accent : palette.light
        context.setFillColor(palette.dark)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.setStrokeColor(line)
        context.setLineWidth(Geometry.lineWidth)
        context.setLineCap(.round)
        context.addPath(Geometry.bowlArc)
        context.strokePath()
        for (index, rect) in Geometry.barRects.enumerated() {
            context.setFillColor(index == 2 ? palette.accent : line)
            context.addPath(Geometry.bar(rect))
            context.fillPath()
        }
    }

    static func image(palette: Palette, size: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        // 一辺 1・y が下向きの座標にする
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: CGFloat(size), y: -CGFloat(size))
        draw(palette: palette, in: context)
        return context.makeImage()
    }
}

@main
struct DrawAppIcon {
    static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        let usage = "使い方: draw_app_icon <出力 PNG> [--size <px>] "
            + "[--theme <\(ThemeColor.allCases.map(\.rawValue).joined(separator: "|"))>]"
        var size = 1024
        var theme: ThemeColor?
        while let index = arguments.firstIndex(where: { $0.hasPrefix("--") }) {
            guard index + 1 < arguments.count else { fail(usage) }
            let value = arguments[index + 1]
            switch arguments[index] {
            case "--size":
                guard let parsed = Int(value), parsed > 0 else { fail("--size は正の整数で指定してください: \(value)") }
                size = parsed
            case "--theme":
                guard let parsed = ThemeColor(rawValue: value) else { fail("知らないテーマ色です: \(value)\n\(usage)") }
                theme = parsed
            default:
                fail(usage)
            }
            arguments.removeSubrange(index...(index + 1))
        }
        guard arguments.count == 1 else { fail(usage) }
        let output = URL(fileURLWithPath: arguments[0])

        guard let image = IconDrawing.image(palette: Palette(theme: theme), size: size),
              let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fail("\(output.path) に書き出せませんでした")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fail("\(output.path) に書き出せませんでした") }
        print(output.path)
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(1)
    }
}
