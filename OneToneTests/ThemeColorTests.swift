//
//  ThemeColorTests.swift
//  OneToneTests
//

import XCTest
@testable import OneTone

final class ThemeColorTests: XCTestCase {

    func testOffersEightPresets() {
        // Discussion #80 の範囲（6〜8 色）で 8 色を用意している。テーマを誤って消したときに気づけるよう件数を固定する
        XCTAssertEqual(ThemeColor.allCases.count, 8)
    }

    func testDefaultIsCurrentNeonCyan() {
        XCTAssertEqual(ThemeColor.default, .cyan)
        // 既存ユーザーの見た目を変えないため、今の差し色と同じ値にする
        XCTAssertEqual(ThemeColor.default.accentHex, 0x00E5FF)
        XCTAssertEqual(ThemeColor.default.onAccentHex, 0x0A0A0F)
    }

    func testRawValuesAndNamesAreUnique() {
        let rawValues = ThemeColor.allCases.map(\.rawValue)
        XCTAssertEqual(Set(rawValues).count, rawValues.count)
        let names = ThemeColor.allCases.map { String(localized: $0.displayName) }
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertFalse(names.contains(""))
    }

    func testAccentsAreDistinctFromEachOther() {
        let accents = ThemeColor.allCases.map(\.accentHex)
        XCTAssertEqual(Set(accents).count, accents.count)
    }

    func testTextOnAccentIsReadable() {
        for theme in ThemeColor.allCases {
            XCTAssertGreaterThanOrEqual(
                ColorContrast.ratio(theme.onAccentHex, theme.accentHex), 4.5, "\(theme) の差し色の上の文字"
            )
        }
    }

    func testAccentStandsOutFromBackground() {
        for theme in ThemeColor.allCases {
            XCTAssertGreaterThanOrEqual(
                ColorContrast.ratio(theme.accentHex, Theme.backgroundHex), 4.5, "\(theme) の差し色と背景"
            )
        }
    }

    func testTitleGradientCentersOnAccentAndStaysVisible() {
        for theme in ThemeColor.allCases {
            let gradient = theme.titleGradientHex
            XCTAssertEqual(gradient.count, 3, "\(theme)")
            XCTAssertEqual(gradient[1], theme.accentHex, "\(theme) のグラデーションの中心は差し色")
            for hex in gradient {
                // タイトルは大きな文字なので 3:1 を下限にする
                XCTAssertGreaterThanOrEqual(ColorContrast.ratio(hex, Theme.backgroundHex), 3, "\(theme)")
            }
        }
    }

    func testScreenshotDemoAlwaysUsesDefaultTheme() {
        for theme in ThemeColor.allCases {
            XCTAssertEqual(ThemeColor.displayed(stored: theme, isScreenshotDemo: true), .default)
            XCTAssertEqual(ThemeColor.displayed(stored: theme, isScreenshotDemo: false), theme)
        }
    }

    func testStoredValueRoundTripsThroughUserDefaults() throws {
        let suiteName = "ThemeColorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // 保存値が無いときは既定のテーマ（既存ユーザーの見た目を変えない）
        XCTAssertNil(defaults.string(forKey: ThemeColor.storageKey))
        for theme in ThemeColor.allCases {
            defaults.set(theme.rawValue, forKey: ThemeColor.storageKey)
            let stored = defaults.string(forKey: ThemeColor.storageKey).flatMap(ThemeColor.init(rawValue:))
            XCTAssertEqual(stored, theme)
        }
        // 読めない保存値は既定のテーマに戻す（@AppStorage の初期値と同じ扱い）
        XCTAssertNil(ThemeColor(rawValue: "unknown"))
    }

    func testStorageKeyIsStable() {
        // 保存値のキー。リリース後に変えると既存ユーザーの選択が失われる
        XCTAssertEqual(ThemeColor.storageKey, "themeColor")
    }

    func testAlternateIconNamesMatchAssetCatalog() {
        // OneTone/AppIcon-<rawValue>.icon と、ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES の名前
        XCTAssertEqual(ThemeColor.cyan.alternateIconName, "AppIcon-cyan")
        let names = ThemeColor.allCases.map(\.alternateIconName)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertFalse(names.contains("AppIcon"), "既定のアイコンと同じ名前にしない")
    }

    func testThemeIsFoundFromAlternateIconName() {
        for theme in ThemeColor.allCases {
            XCTAssertEqual(ThemeColor(alternateIconName: theme.alternateIconName), theme)
        }
        // 既定のアイコン（nil）と知らない名前はテーマに対応しない
        XCTAssertNil(ThemeColor(alternateIconName: nil))
        XCTAssertNil(ThemeColor(alternateIconName: "AppIcon"))
        XCTAssertNil(ThemeColor(alternateIconName: "cyan"))
    }

    func testContrastRatioMatchesKnownValues() {
        XCTAssertEqual(ColorContrast.ratio(0xFFFFFF, 0x000000), 21, accuracy: 1e-9)
        XCTAssertEqual(ColorContrast.ratio(0x000000, 0xFFFFFF), 21, accuracy: 1e-9)
        XCTAssertEqual(ColorContrast.ratio(0x777777, 0x777777), 1, accuracy: 1e-9)
        // Theme.swift のコメントの値（シアン上の暗色 12.8:1）と一致する
        XCTAssertEqual(ColorContrast.ratio(0x00E5FF, 0x0A0A0F), 12.84, accuracy: 0.01)
    }
}
