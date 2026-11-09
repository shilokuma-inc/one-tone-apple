//
//  AppIconPreview.swift
//  OneTone
//

import SwiftUI

/// アプリアイコンの縮小表示（Discussion #208）。`.icon` を書き出す `Tools/draw_app_icon.swift` と同じ寸法・色（`AppIconDesign`）で、
/// 角丸の四角の中に半円と 5 本のバーを描く。Liquid Glass の光沢・影は再現しない（平面で描く）。
///
/// 角丸はここで付ける（アイコン本体の `.icon` には描かない。OS がマスクする）。
/// テーマ色ごとの個別の定義は持たず、`AppIconDesign.Palette(theme:)` から描くので、テーマ色を足せばプレビューもそろう
struct AppIconPreview: View {
    /// nil は既定のアイコン、テーマ色はその色の代替アイコン
    let theme: ThemeColor?
    /// 一辺の大きさ（pt）
    var size: CGFloat = 44

    /// 角丸の半径の一辺に対する比率。iOS のホーム画面のアイコンに近い値（60pt のアイコンで約 13.4pt）
    static let cornerRadiusRatio: CGFloat = 0.2237

    var body: some View {
        let palette = AppIconDesign.Palette(theme: theme)
        Canvas { context, canvasSize in
            // 一辺 1・y が下向きの座標（AppIconDesign.Geometry の座標）にする
            context.scaleBy(x: canvasSize.width, y: canvasSize.height)
            context.fill(Path(CGRect(x: 0, y: 0, width: 1, height: 1)), with: .color(palette.background))
            context.stroke(
                Path(AppIconDesign.Geometry.bowlArc),
                with: .color(palette.line),
                style: StrokeStyle(lineWidth: AppIconDesign.Geometry.lineWidth, lineCap: .round)
            )
            for (rect, color) in zip(AppIconDesign.Geometry.barRects, Self.barColors(palette)) {
                context.fill(Path(AppIconDesign.Geometry.bar(rect)), with: .color(color))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * Self.cornerRadiusRatio, style: .continuous))
        .accessibilityHidden(true)
    }

    /// 左から順に 5 本のバーの色。中央だけ差し色、ほかは線の色（描画スクリプトと同じ塗り分け）
    static func barColors(_ palette: AppIconDesign.Palette) -> [Color] {
        AppIconDesign.Geometry.barRects.indices.map { $0 == 2 ? palette.accent : palette.line }
    }
}

#Preview("アイコンの縮小表示") {
    let icons: [ThemeColor?] = [nil] + ThemeColor.allCases
    VStack(spacing: 16) {
        ForEach([40, 44, 48] as [CGFloat], id: \.self) { size in
            HStack(spacing: 8) {
                ForEach(icons, id: \.self) { theme in
                    AppIconPreview(theme: theme, size: size)
                }
            }
        }
    }
    .padding()
    .themedScreen()
}
