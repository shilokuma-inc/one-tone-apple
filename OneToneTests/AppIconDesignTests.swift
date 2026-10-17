//
//  AppIconDesignTests.swift
//  OneToneTests
//

import SwiftUI
import XCTest
@testable import OneTone

final class AppIconDesignTests: XCTestCase {

    func testDefaultIconHasWhiteLinesAndCyanCenterBar() {
        // 既定のアイコンは白い線（Theme.textPrimary）で、中央のバーだけシアン。背景は Theme.background
        let palette = AppIconDesign.Palette(theme: nil)
        XCTAssertEqual(palette.background, Theme.background)
        XCTAssertEqual(palette.line, Theme.textPrimary)
        XCTAssertEqual(palette.accent, ThemeColor.cyan.accent)
    }

    func testAlternateIconsUseThemeColorForAllLines() {
        // 代替アイコンは線をすべてテーマ色にする（代替の Cyan が既定と同じに見えないように）
        for theme in ThemeColor.allCases {
            let palette = AppIconDesign.Palette(theme: theme)
            XCTAssertEqual(palette.background, Theme.background, "\(theme)")
            XCTAssertEqual(palette.line, theme.accent, "\(theme)")
            XCTAssertEqual(palette.accent, theme.accent, "\(theme)")
        }
        XCTAssertNotEqual(AppIconDesign.Palette(theme: .cyan), AppIconDesign.Palette(theme: nil))
    }

    func testFiveSymmetricBars() {
        let rects = AppIconDesign.Geometry.barRects
        XCTAssertEqual(rects.count, 5)
        for (left, right) in zip(rects, rects.reversed()) {
            XCTAssertEqual(left.midX + right.midX, 1, accuracy: 1e-9)
            XCTAssertEqual(left.height, right.height, accuracy: 1e-9)
        }
        // 中央のバーがいちばん長く、図柄はアイコンの中に収まる
        XCTAssertEqual(rects.map(\.height).max(), rects[2].height)
        let bowlBottom = AppIconDesign.Geometry.horizon + AppIconDesign.Geometry.bowlRadius + AppIconDesign.Geometry.lineWidth / 2
        XCTAssertGreaterThan(rects[2].minY, 0)
        XCTAssertLessThan(bowlBottom, 1)
    }

    func testPreviewPaintsOnlyCenterBarWithAccent() {
        let palette = AppIconDesign.Palette(theme: nil)
        XCTAssertEqual(
            AppIconPreview.barColors(palette),
            [palette.line, palette.line, palette.accent, palette.line, palette.line]
        )
    }
}
