# LEARNINGS — one-tone-macos 固有の知見

このリポジトリだけに当てはまる、ツールや環境の癖と回避策を溜める。全リポジトリ共通の知見は `~/.agents/LEARNINGS.md` に書く。

- 1 項目 = 1 つの箇条書き。日付（YYYY-MM-DD）を添える
- PC 固有の値（ローカルパス・Simulator の UDID）と秘密情報は書かない

## macOS のスクリーンショット撮影（Tools/capture_mac_screenshots.sh）

- GitHub の macOS ランナーは Aqua セッションだがディスプレイが無い（`system_profiler SPDisplaysDataType` が空）。SwiftUI の `WindowGroup` はウィンドウを 1 つも作らず、`CGWindowListCopyWindowInfo` にも何も出ないので、`screencapture -l` や XCUITest のようなウィンドウ前提の撮影は使えない。アプリ内で `NSHostingView` を画面外の `NSWindow` に載せ `cacheDisplay(in:to:)` で描くとディスプレイ無しでも描ける（2026-10-05）
- `ImageRenderer` は macOS の `ScrollView` / `Slider` / `TextField`（AppKit 製の部品）を描けず、背景だけの画像になる。`NSHostingView.cacheDisplay` なら全部描ける。2 倍で描くには `NSBitmapImageRep` を 2 倍のピクセル数で作り `size` を pt の大きさにしてから渡す（2026-10-05）
- `NSHostingView` の描画はウィンドウに載せて RunLoop を 1 秒ほど回してから。載せずに描くと SwiftUI がレイアウトを進めず空になる（2026-10-05）
- App Sandbox 付きのビルドは指定した保存先に PNG を書けない。撮影用のビルドだけ `CODE_SIGN_ENTITLEMENTS= ENABLE_APP_SANDBOX=NO` で外す（配布ビルドには影響しない）（2026-10-05）
- 参考（ウィンドウを撮る方式を試したときの癖）: App Sandbox 付きの実行ファイルを直接起動するとウィンドウが出ない（`open -n -a` なら出る）。`-ApplePersistenceIgnoreState YES` を付けると `WindowGroup` がウィンドウを出さない。`open` で起動したプロセスのパスは `/private/var/…` に解決される。起動直後のウィンドウ番号は数秒で無効になることがある。起動時に最初の `TextField` へフォーカスが当たり数字が選択表示になる（2026-10-05）

## iOS のスクリーンショット撮影（Tools/capture_screenshots.sh）

- `simctl terminate` の直後に `simctl launch` すると、アプリが出る前のホーム画面を「連続 2 枚が一致した」として撮ってしまうことがある。終了と起動の間に数秒空ける（`RELAUNCH_INTERVAL`）（2026-10-05）

## GitHub Actions

- `workflow_dispatch` だけのワークフローは、既定ブランチに無いと `gh workflow run` / REST API から起動できない（404）。一度でも実行されれば登録されて `--ref <ブランチ>` で起動できるので、新規に足すときは一時的に PR ブランチへの `push` トリガーを付けて 1 回動かし、登録後に外す（2026-10-05）
- ランナーの bash 3.2 では、`set -u` の unbound variable で止まったときに EXIT トラップへ終了コード 0 が渡り、`trap cleanup EXIT` があるとステップが成功扱いになる。`$VAR` の直後に全角文字を置かない（`${VAR}` にする）のに加え、スクリプトの最後で立てる FINISHED フラグをトラップで見て、立っていなければ 1 で終える（2026-10-05）

## App Store Connect

- iOS と macOS を 1 ターゲット・同じ Bundle ID で配信していても、App Store Connect の `appStoreVersions` は `platform`（`IOS` / `MAC_OS`）ごとに別で、説明文・スクリーンショットの置き場（`appStoreVersionLocalizations`）も別。`filter[platform]` を省くと iOS しか見えない（2026-10-05）
