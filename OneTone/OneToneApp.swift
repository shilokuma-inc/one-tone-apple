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
        #if os(macOS)
        // アプリのメニューの「設定…」（⌘,）と、メイン画面の右上の歯車（macOS 14 以降）で開く設定ウィンドウ。iOS は歯車からシートで開く
        Settings {
            SettingsView()
        }
        #endif
    }
}
