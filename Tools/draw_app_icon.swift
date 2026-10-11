// アプリアイコンを Core Graphics で描き、PNG に書き出す（Discussion #177）。
// 「半円 + 5 本のバー」のモチーフを、白黒を基調にシアンを差し色にして描く。デザインは案（a / b / c）を引数で切り替える。
// 角丸・影・余白は描かない（OS がマスクする）。正方形の全面を塗り、左右対称に描く。
// 色は ThemeColor.swift / Theme.swift の値をそのまま使う（一緒にコンパイルする）。
//
//   swiftc -O -parse-as-library Tools/draw_app_icon.swift OneTone/ThemeColor.swift OneTone/Theme.swift -o "$TMPDIR/draw_app_icon"
//   "$TMPDIR/draw_app_icon" <案 a|b|c> <出力 PNG> [--size <px>] [--theme <ThemeColor の rawValue>]
//
// --size は一辺のピクセル数（既定 1024）。--theme を付けると、そのテーマ色の代替アイコンの塗り方で描く（付けなければ既定のアイコン）。
// 出力はアルファ無しの RGB（App Store Connect はアルファ付きのアイコンを受け付けない）。

import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// デザイン案
enum Variant: String, CaseIterable {
    /// 案A: 今の上下の塗り分けを残す。上が白・下が黒で、水平線から下にシアンの半円、バーは黒
    case a
    /// 案B: 全面をアプリの背景と同じ暗色にし、半円を輪郭だけにする。バーは白い線で、中央の 1 本だけシアン
    case b
    /// 案C: 全面を白にし、半円を黒で塗る。バーは水平線の上では黒、半円の中ではシアン（光って見える）
    case c

    /// 寸法。アイコンの一辺を 1 とした値で、y は上から下へ測る
    var geometry: Geometry {
        switch self {
        case .a:
            Geometry(horizon: 0.475, bowlRadius: 0.31, barWidth: 0.064, barGap: 0.05,
                     barLengths: (outer: 0.2, inner: 0.36, center: 0.52), barCenterOffset: 0)
        case .b:
            Geometry(horizon: 0.435, bowlRadius: 0.33, barWidth: 0.06, barGap: 0.05,
                     barLengths: (outer: 0.18, inner: 0.32, center: 0.46), barCenterOffset: 0)
        case .c:
            Geometry(horizon: 0.475, bowlRadius: 0.32, barWidth: 0.07, barGap: 0.05,
                     barLengths: (outer: 0.22, inner: 0.38, center: 0.54), barCenterOffset: 0)
        }
    }
}

/// アイコンの寸法。半円は水平線 `horizon` を直径にして下に開く
struct Geometry {
    /// 半円の直径を置く水平線の高さ
    var horizon: CGFloat
    /// 半円の半径（輪郭だけの案では線の中心までの半径。線の太さはバーと同じ）
    var bowlRadius: CGFloat
    /// バーの太さ（両端は半円で丸める）
    var barWidth: CGFloat
    /// バーどうしの間隔
    var barGap: CGFloat
    /// バーの長さ。外側・内側・中央の 3 つを書き、左右に折り返して 5 本にする（左右対称にするため）
    var barLengths: (outer: CGFloat, inner: CGFloat, center: CGFloat)
    /// バーの縦の中心を水平線からずらす量（下が正）
    var barCenterOffset: CGFloat

    /// 左から順に 5 本のバーの矩形
    var barRects: [CGRect] {
        let lengths = [barLengths.outer, barLengths.inner, barLengths.center, barLengths.inner, barLengths.outer]
        return lengths.enumerated().map { index, length in
            let centerX = 0.5 + CGFloat(index - 2) * (barWidth + barGap)
            return CGRect(x: centerX - barWidth / 2, y: horizon + barCenterOffset - length / 2, width: barWidth, height: length)
        }
    }

    /// 水平線から下の半円の円弧（左端から右端へ）
    var bowlArc: CGPath {
        let path = CGMutablePath()
        // y が下向きの座標なので、角度 0 → π は右端から下を通って左端へ回る
        path.addArc(center: CGPoint(x: 0.5, y: horizon), radius: bowlRadius, startAngle: 0, endAngle: .pi, clockwise: false)
        return path
    }

    /// 水平線から下の半円の面
    var bowl: CGPath {
        let path = CGMutablePath()
        path.addPath(bowlArc)
        path.closeSubpath()
        return path
    }

    func bar(_ rect: CGRect) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)
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
    /// 一辺 1 の座標（y は下向き）に描く
    static func draw(_ variant: Variant, palette: Palette, in context: CGContext) {
        let geometry = variant.geometry
        switch variant {
        case .a:
            // 上半分は白（代替アイコンでは差し色）、下半分は黒
            context.setFillColor(palette.isAlternate ? palette.accent : palette.light)
            context.fill(CGRect(x: 0, y: 0, width: 1, height: geometry.horizon))
            context.setFillColor(palette.dark)
            context.fill(CGRect(x: 0, y: geometry.horizon, width: 1, height: 1 - geometry.horizon))
            context.setFillColor(palette.accent)
            context.addPath(geometry.bowl)
            context.fillPath()
            context.setFillColor(palette.dark)
            for rect in geometry.barRects {
                context.addPath(geometry.bar(rect))
            }
            context.fillPath()
        case .b:
            // 既定のアイコンは白い線に中央のバーだけ差し色、代替アイコンは線をすべて差し色にする
            let line = palette.isAlternate ? palette.accent : palette.light
            context.setFillColor(palette.dark)
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            context.setStrokeColor(line)
            context.setLineWidth(geometry.barWidth)
            context.setLineCap(.round)
            context.addPath(geometry.bowlArc)
            context.strokePath()
            for (index, rect) in geometry.barRects.enumerated() {
                context.setFillColor(index == 2 ? palette.accent : line)
                context.addPath(geometry.bar(rect))
                context.fillPath()
            }
        case .c:
            // 背景は白（代替アイコンでは差し色）。バーは水平線の上では黒、半円の中では差し色
            context.setFillColor(palette.isAlternate ? palette.accent : palette.light)
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            context.setFillColor(palette.dark)
            context.addPath(geometry.bowl)
            context.fillPath()
            for rect in geometry.barRects {
                context.addPath(geometry.bar(rect))
            }
            context.fillPath()
            context.saveGState()
            context.addPath(geometry.bowl)
            context.clip()
            context.setFillColor(palette.accent)
            for rect in geometry.barRects {
                context.addPath(geometry.bar(rect))
            }
            context.fillPath()
            context.restoreGState()
        }
    }

    static func image(_ variant: Variant, palette: Palette, size: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        // 一辺 1・y が下向きの座標にする
        context.translateBy(x: 0, y: CGFloat(size))
        context.scaleBy(x: CGFloat(size), y: -CGFloat(size))
        draw(variant, palette: palette, in: context)
        return context.makeImage()
    }
}

@main
struct DrawAppIcon {
    static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        let usage = "使い方: draw_app_icon <案 \(Variant.allCases.map(\.rawValue).joined(separator: "|"))> <出力 PNG> "
            + "[--size <px>] [--theme <\(ThemeColor.allCases.map(\.rawValue).joined(separator: "|"))>]"
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
        guard arguments.count == 2, let variant = Variant(rawValue: arguments[0]) else { fail(usage) }
        let output = URL(fileURLWithPath: arguments[1])

        guard let image = IconDrawing.image(variant, palette: Palette(theme: theme), size: size),
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
