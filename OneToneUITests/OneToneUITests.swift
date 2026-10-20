//
//  OneToneUITests.swift
//  OneToneUITests
//
//  Created by 村石 拓海 on 2024/05/28.
//

import XCTest

final class OneToneUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        // 初回起動のチュートリアルで画面が隠れないようにする
        app.launchArguments.append("-skip-tutorial")
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    /// メイン画面のロゴ（マーク＋文字）が「One Tone」の 1 つの要素として読まれること（マークは読まない。見出しの trait は UI テストからは見えない）
    func testLogoIsReadOnce() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-skip-tutorial")
        app.launch()

        // 文字は iOS では label、macOS では value に入る
        let logo = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR value == %@", "One Tone", "One Tone"))
        XCTAssertTrue(logo.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(logo.count, 1)
    }

    #if os(iOS)
    /// iOS 26 以上のバー: 大きいロゴが見えている間は小さいロゴを出さず、上へスワイプして大きいロゴがバーの下に隠れたら出し、戻すと消す
    func testBarLogoAppearsWhenScrolledUp() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("iOS 26 未満はバーを出さない") }
        let app = XCUIApplication()
        app.launchArguments.append("-skip-tutorial")
        app.launch()

        // 小さいロゴは隠している間は読み上げから外しているので、要素として見えない
        let barLogo = app.descendants(matching: .any)["barLogo"]
        XCTAssertTrue(app.buttons["questionmark.circle"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(barLogo.exists)

        app.swipeUp()
        XCTAssertTrue(barLogo.waitForExistence(timeout: 3))

        app.swipeDown()
        app.swipeDown()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: barLogo)
        wait(for: [gone], timeout: 3)
    }
    #endif

    /// 設定画面に同梱の書体のライセンス表記（LICENSES）があり、ライセンスの全文を開けること。
    /// PR に載せる画像のため、パネルと全文のスクリーンショットを残す
    func testSettingsShowsFontLicense() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-skip-tutorial")
        app.launch()

        // 右上の歯車（iOS はシート、macOS は設定ウィンドウ）。端末の言語に左右されないよう、ラベルではなく識別子（記号の名前）で探す
        app.buttons["gearshape"].firstMatch.tap()

        let panelTitle = app.staticTexts["LICENSES"].firstMatch
        XCTAssertTrue(panelTitle.waitForExistence(timeout: 5))
        let viewButton = app.buttons["viewFullLicenseButton"].firstMatch
        XCTAssertTrue(viewButton.waitForExistence(timeout: 5))
        #if os(iOS)
        // シートは半分の高さで開くので、ボタンが押せる位置まで送る
        for _ in 0..<6 where !viewButton.isHittable {
            app.swipeUp()
        }
        #endif
        XCTAssertTrue(app.staticTexts["Audiowide"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["SIL Open Font License 1.1"].firstMatch.exists)
        attachScreenshot(of: app, showing: "viewFullLicenseButton", named: "settings-licenses")

        viewButton.tap()
        let fullText = app.staticTexts["licenseFullText"].firstMatch
        XCTAssertTrue(fullText.waitForExistence(timeout: 5))
        // 文字は iOS では label、macOS では value に入る
        let fullTextContent = fullText.label + ((fullText.value as? String) ?? "")
        XCTAssertTrue(fullTextContent.contains("SIL OPEN FONT LICENSE Version 1.1"))
        attachScreenshot(of: app, showing: "licenseFullText", named: "settings-license-full-text")
    }

    /// 画面を撮って残す。macOS の `app.screenshot()` は画面全体（ほかのアプリのウィンドウも）を写すので、
    /// `identifier` の要素があるウィンドウだけを撮る
    private func attachScreenshot(of app: XCUIApplication, showing identifier: String, named name: String) {
        #if os(macOS)
        let screenshot = app.windows.containing(.any, identifier: identifier).firstMatch.screenshot()
        #else
        let screenshot = app.screenshot()
        #endif
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                let app = XCUIApplication()
                app.launchArguments.append("-skip-tutorial")
                app.launch()
            }
        }
    }
}
