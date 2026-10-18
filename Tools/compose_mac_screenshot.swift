// macOS のアプリ画面の画像を、App Store が受け付ける寸法のキャンバスに合成する。
//
//   swiftc -O Tools/compose_mac_screenshot.swift -o compose_mac_screenshot
//   ./compose_mac_screenshot <画面の PNG> <出力 PNG> <画面の幅 pt> [<キャンバス pt。既定 1440x900>]
//
// アプリが画面外ウィンドウの NSHostingView を cacheDisplay で描き出した画面（1280x800 pt を 2 倍で描いた 2560x1600 px）は、そのままでは
// App Store Connect の Mac の寸法（1280x800 / 1440x900 / 2560x1600 / 2880x1800）に合わない。
// そこで、画像の幅と pt での幅から倍率（1x / 2x）を求め、キャンバス（pt）× 倍率のピクセルの
// 背景（アプリと同じ暗いグラデーション）を敷いて、画面を角丸にして中央に置く。収まらないときは縮めて収める。
// 出力はアルファ無しの RGB（App Store Connect はアルファ付きを受け付けない。角丸の外側の透過もここで消える）。

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 3 || arguments.count == 4 else {
    fail("使い方: compose_mac_screenshot <入力 PNG> <出力 PNG> <ウィンドウの幅 pt> [<キャンバス pt 例: 1440x900>]")
}
let inputPath = arguments[arguments.startIndex]
let outputPath = arguments[arguments.startIndex + 1]
guard let windowWidthPoints = Double(arguments[arguments.startIndex + 2]), windowWidthPoints > 0 else {
    fail("画面の幅（pt）が数値ではありません")
}
let canvasSpec = arguments.count == 4 ? arguments[arguments.startIndex + 3] : "1440x900"
let canvasParts = canvasSpec.lowercased().split(separator: "x").compactMap { Int($0) }
guard canvasParts.count == 2 else {
    fail("キャンバスの寸法は 1440x900 のように書いてください: \(canvasSpec)")
}

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: inputPath) as CFURL, nil),
      let window = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    fail("\(inputPath) を読めませんでした")
}

// 画像の幅 ÷ pt の幅がディスプレイの倍率。Retina なら 2、それ以外は 1
let scale = max(1, Int((Double(window.width) / windowWidthPoints).rounded()))
let canvasWidth = canvasParts[0] * scale
let canvasHeight = canvasParts[1] * scale

guard let context = CGContext(
    data: nil,
    width: canvasWidth,
    height: canvasHeight,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else {
    fail("キャンバスを作れませんでした")
}

// 背景: アプリの配色（Theme.background 0x0A0A0F / surfaceRaised 0x22222E）に寄せた暗いグラデーション。
// ウィンドウの縁が見えるよう、ウィンドウの背景よりわずかに明るくする
let colors = [
    CGColor(srgbRed: 0x30 / 255, green: 0x30 / 255, blue: 0x4A / 255, alpha: 1),
    CGColor(srgbRed: 0x0E / 255, green: 0x0E / 255, blue: 0x16 / 255, alpha: 1),
] as CFArray
guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) else {
    fail("背景を作れませんでした")
}
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: canvasHeight),
    end: CGPoint(x: canvasWidth, y: 0),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)

// ウィンドウを中央に置く。キャンバスからはみ出すときだけ、縦横比を保って縮める
let fit = min(1, Double(canvasWidth) / Double(window.width), Double(canvasHeight) / Double(window.height))
let drawWidth = Double(window.width) * fit
let drawHeight = Double(window.height) * fit
if fit < 1 {
    FileHandle.standardError.write(Data(
        "注意: 画面（\(window.width)x\(window.height)）がキャンバス（\(canvasWidth)x\(canvasHeight)）に収まらないため縮めました\n".utf8
    ))
}
let drawRect = CGRect(
    x: (Double(canvasWidth) - drawWidth) / 2,
    y: (Double(canvasHeight) - drawHeight) / 2,
    width: drawWidth,
    height: drawHeight
)
// macOS のウィンドウらしく角を丸める（アプリの角丸 12pt に合わせる）
let cornerRadius = 12 * Double(scale) * fit
context.saveGState()
context.addPath(CGPath(roundedRect: drawRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
context.clip()
context.interpolationQuality = .high
context.draw(window, in: drawRect)
context.restoreGState()

guard let composed = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          URL(fileURLWithPath: outputPath) as CFURL, UTType.png.identifier as CFString, 1, nil
      ) else {
    fail("\(outputPath) を作れませんでした")
}
CGImageDestinationAddImage(destination, composed, nil)
guard CGImageDestinationFinalize(destination) else {
    fail("\(outputPath) を保存できませんでした")
}
print("\(outputPath)  \(canvasWidth)x\(canvasHeight)（倍率 \(scale)x、画面 \(window.width)x\(window.height)）")
