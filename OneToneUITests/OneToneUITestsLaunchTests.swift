//
//  OneToneUITestsLaunchTests.swift
//  OneToneUITests
//
//  Created by 村石 拓海 on 2024/05/28.
//

import XCTest

final class OneToneUITestsLaunchTests: XCTestCase {

    // UI の構成（言語・外観・向き）ごとに流すと 286 回・iOS で 40 分ほどかかり、CI の Build（45 分で打ち切り）に収まらないので、1 回だけ流す
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        // 初回起動のチュートリアルで画面が隠れないようにする
        app.launchArguments.append("-skip-tutorial")
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
