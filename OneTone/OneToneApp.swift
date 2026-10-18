//
//  OneToneApp.swift
//  OneTone
//
//  Created by 村石 拓海 on 2024/05/28.
//

import SwiftUI

@main
struct OneToneApp: App {
    init() {
        #if os(macOS)
        // 撮影モードで保存先が指定されていれば、ウィンドウを出さずに画面を PNG に描いて終了する
        ScreenshotDemo.renderIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                // スクリーンショットの撮影モードでは、止まらないアニメーションを止めて画面を静止させる
                .environment(\.freezesAnimations, ScreenshotDemo.isEnabled)
        }
    }
}
