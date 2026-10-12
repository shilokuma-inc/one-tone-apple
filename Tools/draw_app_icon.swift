// アプリアイコンを Core Graphics で描き、PNG に書き出す（Discussion #177）。
// 「半円 + 5 本のバー」のモチーフを、白黒を基調にシアンを差し色にして描く（PR #179 で 3 案から選んだ案B「ライン」）。
// 全面をアプリの背景と同じ暗色にし、半円は輪郭だけの線、バーは線で描く。線は白で、中央のバーだけシアン。
// 代替アイコン（iOS だけ）は同じデザインの色違いで、線をすべてテーマ色にする（既定のアイコンとは塗り分けが違うので、代替の Cyan と既定は同じに見えない）。
// 角丸・影・余白は描かない（iOS と macOS 26 は OS がマスクする。iOS 18 / macOS 13〜15 向けの画像は、.icon から Xcode がビルド時に書き出す）。
// 正方形の全面を塗り、左右対称に描く。
// 色は ThemeColor.swift / Theme.swift の値をそのまま使う（一緒にコンパイルする）。
//
//   swiftc -O -parse-as-library Tools/draw_app_icon.swift OneTone/ThemeColor.swift OneTone/Theme.swift -o "$TMPDIR/draw_app_icon"
//   "$TMPDIR/draw_app_icon" --all OneTone
//   "$TMPDIR/draw_app_icon" <出力 .icon | 出力 PNG> [--theme <ThemeColor の rawValue>] [--size <px>（PNG だけ）]
//
// --all: 既定のアイコン OneTone/AppIcon.icon と、テーマ色ごとの代替アイコン OneTone/AppIcon-<rawValue>.icon をすべて作り直す（Icon Composer の形式。
// レイヤーは SVG）。テーマ色を足したら実行し直し、project.pbxproj に .icon を足して ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES にも名前を足す。
// .icon / PNG: 1 つだけ書き出す。--theme を付けるとそのテーマ色の代替アイコン、付けなければ既定のアイコン。
// PNG は見た目の確認用で、--size は一辺のピクセル数（既定 1024）。出力はアルファ無しの RGB。

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

/// 塗りに使う色。既定のアイコンは白い線に中央のバーだけシアン、代替アイコンは線をすべてテーマ色にする
struct Palette {
    /// 背景（Theme.background）
    var background: CGColor
    /// 半円と両側のバーの線。既定のアイコンは白（Theme.textPrimary）、代替アイコンはテーマ色
    var line: CGColor
    /// 中央のバー（テーマ色。既定のアイコンはシアン）
    var accent: CGColor

    /// theme が nil なら既定のアイコン、テーマ色を渡すとその色の代替アイコンの色
    init(theme: ThemeColor?) {
        background = Self.cgColor(Theme.background)
        accent = Self.cgColor((theme ?? .default).accent)
        line = theme == nil ? Self.cgColor(Theme.textPrimary) : accent
    }

    static func cgColor(_ color: Color) -> CGColor {
        color.resolve(in: EnvironmentValues()).cgColor
    }
}

enum IconDrawing {
    /// 一辺 1 の座標（y は下向き）に描く
    static func draw(palette: Palette, in context: CGContext) {
        context.setFillColor(palette.background)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        context.setStrokeColor(palette.line)
        context.setLineWidth(Geometry.lineWidth)
        context.setLineCap(.round)
        context.addPath(Geometry.bowlArc)
        context.strokePath()
        for (index, rect) in Geometry.barRects.enumerated() {
            context.setFillColor(index == 2 ? palette.accent : palette.line)
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

/// Icon Composer の `.icon`（`icon.json` と、`Assets/` に置くレイヤーの SVG）。
/// 奥から半円・両側のバー・中央のバーの 3 つのグループに分け、Liquid Glass で奥行きが付くようにする
enum IconComposerFile {
    /// SVG のキャンバスの一辺。Icon Composer の正方形のアイコンは 1024pt
    static let canvas: CGFloat = 1024

    /// レイヤー（名前と SVG）。前面から順に並べる（`icon.json` の `groups` は先頭が最前面）
    static func layers(palette: Palette) -> [(name: String, svg: String)] {
        let rects = Geometry.barRects
        let sideBars = rects.indices.filter { $0 != 2 }.map { rect(rects[$0], color: palette.line) }
        return [
            ("bar-center", svg([rect(rects[2], color: palette.accent)])),
            ("bars", svg(sideBars)),
            ("bowl", svg([bowl(color: palette.line)])),
        ]
    }

    static func write(to url: URL, palette: Palette) throws {
        let assets = url.appendingPathComponent("Assets")
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        let layers = layers(palette: palette)
        for layer in layers {
            try Data(layer.svg.utf8).write(to: assets.appendingPathComponent("\(layer.name).svg"))
        }
        let groups: [[String: Any]] = layers.map { layer in
            ["layers": [["image-name": "\(layer.name).svg", "name": layer.name]]]
        }
        let background = ["solid": srgb(palette.background)]
        let json: [String: Any] = [
            // ダークでも背景はライトと同じ暗色にする（指定しないと、システムがライトより明るい灰色のグラデーションに置き換える）
            "fill-specializations": [["value": background], ["appearance": "dark", "value": background]],
            "groups": groups,
            "supported-platforms": ["squares": "shared"],
        ]
        var data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(Data("\n".utf8))
        try data.write(to: url.appendingPathComponent("icon.json"))
    }

    static func svg(_ elements: [String]) -> String {
        let size = number(canvas)
        return """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(size)" height="\(size)" viewBox="0 0 \(size) \(size)">
        \(elements.map { "  \($0)" }.joined(separator: "\n"))
        </svg>

        """
    }

    static func rect(_ rect: CGRect, color: CGColor) -> String {
        "<rect x=\"\(number(rect.minX * canvas))\" y=\"\(number(rect.minY * canvas))\" width=\"\(number(rect.width * canvas))\" "
            + "height=\"\(number(rect.height * canvas))\" rx=\"\(number(Geometry.lineWidth / 2 * canvas))\" fill=\"\(hex(color))\"/>"
    }

    /// 半円の輪郭。線（stroke）で書くと Liquid Glass の描画で円弧の両端と下端を結ぶ斜めの線が見えるので、
    /// 外側の円弧・右端の丸・内側の円弧・左端の丸をつないだ塗りの形で書く。
    /// 円弧は 90° ずつに分けて左右対称の点だけを通す（SVG の y は下向きで、sweep 1 が画面上の時計回り）
    static func bowl(color: CGColor) -> String {
        let center = 0.5 * canvas
        let horizon = Geometry.horizon * canvas
        let radius = Geometry.bowlRadius * canvas
        let cap = Geometry.lineWidth / 2 * canvas
        let outer = radius + cap
        let inner = radius - cap
        func arc(_ arcRadius: CGFloat, sweep: Int, to x: CGFloat, _ y: CGFloat) -> String {
            "A\(number(arcRadius)) \(number(arcRadius)) 0 0 \(sweep) \(number(x)) \(number(y))"
        }
        let path = [
            "M\(number(center - outer)) \(number(horizon))",
            arc(outer, sweep: 0, to: center, horizon + outer),
            arc(outer, sweep: 0, to: center + outer, horizon),
            arc(cap, sweep: 0, to: center + radius, horizon - cap),
            arc(cap, sweep: 0, to: center + inner, horizon),
            arc(inner, sweep: 1, to: center, horizon + inner),
            arc(inner, sweep: 1, to: center - inner, horizon),
            arc(cap, sweep: 0, to: center - radius, horizon - cap),
            arc(cap, sweep: 0, to: center - outer, horizon),
            "Z",
        ].joined(separator: " ")
        return "<path d=\"\(path)\" fill=\"\(hex(color))\"/>"
    }

    /// 小数 2 桁までの数（末尾の 0 は省く）
    static func number(_ value: CGFloat) -> String {
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// sRGB の色の 8bit ずつの値
    static func components(_ color: CGColor) -> [Int] {
        let srgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil) ?? color
        return (srgb.components ?? []).prefix(3).map { Int(($0 * 255).rounded()) }
    }

    /// SVG の色（#RRGGBB）
    static func hex(_ color: CGColor) -> String {
        "#" + components(color).map { String(format: "%02X", $0) }.joined()
    }

    /// `icon.json` の色（Icon Composer と同じ srgb:r,g,b,a の形）
    static func srgb(_ color: CGColor) -> String {
        "srgb:" + (components(color).map { String(format: "%.5f", Double($0) / 255) } + ["1.00000"]).joined(separator: ",")
    }
}

@main
struct DrawAppIcon {
    static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())
        let usage = "使い方: draw_app_icon --all <OneTone のディレクトリ>\n"
            + "       draw_app_icon <出力 .icon | 出力 PNG> [--theme <\(ThemeColor.allCases.map(\.rawValue).joined(separator: "|"))>] "
            + "[--size <px>（PNG だけ）]"
        var size: Int?
        var theme: ThemeColor?
        var allDirectory: URL?
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
            case "--all":
                allDirectory = URL(fileURLWithPath: value)
            default:
                fail(usage)
            }
            arguments.removeSubrange(index...(index + 1))
        }

        if let allDirectory {
            guard arguments.isEmpty, size == nil, theme == nil else { fail(usage) }
            // 既定のアイコンの名前は ASSETCATALOG_COMPILER_APPICON_NAME、代替アイコンの名前は ThemeColor.alternateIconName と同じにする
            let icons: [(name: String, theme: ThemeColor?)] = [("AppIcon", nil)] + ThemeColor.allCases.map { ($0.alternateIconName, $0) }
            for icon in icons {
                writeIcon(to: allDirectory.appendingPathComponent("\(icon.name).icon"), theme: icon.theme)
            }
            return
        }
        guard arguments.count == 1 else { fail(usage) }
        let output = URL(fileURLWithPath: arguments[0])

        if output.pathExtension == "icon" {
            guard size == nil else { fail("--size は PNG の書き出しにだけ使えます\n\(usage)") }
            writeIcon(to: output, theme: theme)
            return
        }
        guard let image = IconDrawing.image(palette: Palette(theme: theme), size: size ?? 1024),
              let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fail("\(output.path) に書き出せませんでした")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { fail("\(output.path) に書き出せませんでした") }
        print(output.path)
    }

    static func writeIcon(to url: URL, theme: ThemeColor?) {
        do {
            try IconComposerFile.write(to: url, palette: Palette(theme: theme))
        } catch {
            fail("\(url.path) に書き出せませんでした: \(error)")
        }
        print(url.path)
    }

    static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(1)
    }
}
