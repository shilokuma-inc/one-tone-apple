# LEARNINGS — one-tone-apple 固有の知見

このリポジトリだけに当てはまる、ツールや環境の癖と回避策を溜める。全リポジトリ共通の知見は `~/.agents/LEARNINGS.md` に書く。

- 1 項目 = 1 つの箇条書き。日付（YYYY-MM-DD）を添える
- PC 固有の値（ローカルパス・Simulator の UDID）と秘密情報は書かない

## macOS のスクリーンショット撮影（Tools/capture_mac_screenshots.sh）

- GitHub の macOS ランナーは Aqua セッションだがディスプレイが無い（`system_profiler SPDisplaysDataType` が空）。SwiftUI の `WindowGroup` はウィンドウを 1 つも作らず、`CGWindowListCopyWindowInfo` にも何も出ないので、`screencapture -l` や XCUITest のようなウィンドウ前提の撮影は使えない。アプリ内で `NSHostingView` を画面外の `NSWindow` に載せ `cacheDisplay(in:to:)` で描くとディスプレイ無しでも描ける（2026-10-05）
- `ImageRenderer` は macOS の `ScrollView` / `Slider` / `TextField`（AppKit 製の部品）を描けず、背景だけの画像になる。`NSHostingView.cacheDisplay` なら全部描ける。2 倍で描くには `NSBitmapImageRep` を 2 倍のピクセル数で作り `size` を pt の大きさにしてから渡す（2026-10-05）
- `NSHostingView` の描画はウィンドウに載せて RunLoop を 1 秒ほど回してから。載せずに描くと SwiftUI がレイアウトを進めず空になる（2026-10-05）
- App Sandbox 付きのビルドは指定した保存先に PNG を書けない。撮影用のビルドだけ `CODE_SIGN_ENTITLEMENTS= ENABLE_APP_SANDBOX=NO` で外す（配布ビルドには影響しない）（2026-10-05）
- 参考（ウィンドウを撮る方式を試したときの癖）: App Sandbox 付きの実行ファイルを直接起動するとウィンドウが出ない（`open -n -a` なら出る）。`-ApplePersistenceIgnoreState YES` を付けると `WindowGroup` がウィンドウを出さない。`open` で起動したプロセスのパスは `/private/var/…` に解決される。起動直後のウィンドウ番号は数秒で無効になることがある。起動時に最初の `TextField` へフォーカスが当たり数字が選択表示になる（2026-10-05）
- 他のビルドと並走して Mac が重いと、1 枚を描き終えるまでの既定の待ち時間（`RENDER_TIMEOUT=60` 秒）を超えて止まることがある。そのときは `RENDER_TIMEOUT=240` などを付け、`Tools/capture_tutorial_screenshots.sh mac <失敗した言語>` のように言語を絞って撮り直す（2026-10-07）

## iOS のスクリーンショット撮影（Tools/capture_screenshots.sh）

- `simctl terminate` の直後に `simctl launch` すると、アプリが出る前のホーム画面を「連続 2 枚が一致した」として撮ってしまうことがある。終了と起動の間に数秒空ける（`RELAUNCH_INTERVAL`）（2026-10-05）

## ローカルビルド

- 手元に「Mac Development」の署名証明書が無いと、macOS 向けの `xcodebuild build` / `test` が署名で失敗する（iOS Simulator は通る）。CI と同じく build は `CODE_SIGNING_ALLOWED=NO`、macOS の `test` は `CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=` のアドホック署名で通る。`platform=macOS` だけだと arm64 / x86_64 の 2 つに一致するので `arch=arm64` も付ける（2026-10-06）
- `xcodebuild` でビルドしても `.xcstrings` にはキーが足されない（Xcode.app でのビルド時だけ自動で足される）。コマンドラインでは `python3 Tools/sync_string_catalogs.py` でビルド成果物の `.stringsdata` を `xcstringstool sync` に渡して取り込む。`#if os(...)` の片方にしか無い文言が stale にされないよう、macOS と iOS の両方の `.stringsdata` をまとめて渡す（2026-10-07）
- SwiftLint はビルドツールプラグイン（SwiftLintPlugins）で入れているので、コマンドラインの `xcodebuild` は、Xcode.app でプラグインを一度信頼していないと信頼確認で止まる。`-skipPackagePluginValidation` で飛ばせるが、未確認の PR をチェックアウトしたときに付けるとそのプラグインを確認なしで動かすことになるので、手元のスクリプト（`capture_*.sh` / `sync_string_catalogs.py`）は `SKIP_PACKAGE_PLUGIN_VALIDATION=1` を付けたときだけ付ける。CI は `defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES`。DerivedData の `SourcePackages/artifacts` にある `swiftlint` を単体で動かすときは `DEVELOPER_DIR` を Xcode.app に向けないと sourcekitdInProc が読めずに落ちる（2026-10-07）
- asset catalog の画像セットは、`locale` の無い画像（既定）と `"locale" : "ja"` などを付けた画像を同じ Contents.json に並べ、`"properties" : { "localizable" : true }` を付けると言語ごとに出し分けられる（macOS / iOS とも actool が受け付け、`assetutil --info` で Localization ごとの rendition になる）。対応外の言語の端末では既定の画像が出る（2026-10-07）

## ローカライズ

- `xcstringstool sync` は、引数が 2 つ以上の文言（`Page %lld of %lld` など）を取り込むと、en に位置指定つきの値（`Page %1$lld of %2$lld`）を `state: new` で書く。訳を入れたら en の state も `translated` にする（2026-10-07）
- `LocalizedStringResource` にした文言をテストで比べるときは、`String(localized:)` ではなく `.key`（英語の原文）で比べると、テストを動かす Mac の言語に左右されない（2026-10-07）

## GitHub Actions

- `workflow_dispatch` だけのワークフローは、既定ブランチに無いと `gh workflow run` / REST API から起動できない（404）。一度でも実行されれば登録されて `--ref <ブランチ>` で起動できるので、新規に足すときは一時的に PR ブランチへの `push` トリガーを付けて 1 回動かし、登録後に外す（2026-10-05）
- ランナーの bash 3.2 では、`set -u` の unbound variable で止まったときに EXIT トラップへ終了コード 0 が渡り、`trap cleanup EXIT` があるとステップが成功扱いになる。`$VAR` の直後に全角文字を置かない（`${VAR}` にする）のに加え、スクリプトの最後で立てる FINISHED フラグをトラップで見て、立っていなければ 1 で終える（2026-10-05）

## App Store Connect

- iOS と macOS を 1 ターゲット・同じ Bundle ID で配信していても、App Store Connect の `appStoreVersions` は `platform`（`IOS` / `MAC_OS`）ごとに別で、説明文・スクリーンショットの置き場（`appStoreVersionLocalizations`）も別。`filter[platform]` を省くと iOS しか見えない（2026-10-05）

## アプリアイコン（Tools/draw_app_icon.swift）

- `Theme.textPrimary` のように SwiftUI の `Color` しか無い色も、`swiftc` で動かす CLI のスクリプトで `Color.resolve(in: EnvironmentValues()).cgColor` を使えば sRGB の値を取り出せる（`Theme.swift` に 16 進の定数を足さなくてよい。書き出した画素が #F2F2F7 そのままになることを確認）（2026-10-12）
- Core Graphics で、画素の境目に乗らない同じ直線で接する 2 つの面を別々に塗ると、境目の 1 行にアンチエイリアスの重ね塗りで下地の色が透けて濁る（デザイン案を 3 案出したとき、黒の下地に白の上半分と水平線から下のシアンの半円を塗った案で、境目に暗い線が出た）。下になる面を境目の向こうまで広げて塗り（半円なら円のまま）、上の面を最後に重ねる（2026-10-12）
- 半円の線を端から端へ 1 本の円弧で描くと、16px 前後に小さく書き出したときに左右でアンチエイリアスがずれる（左右の差が最大 42/255）。下端から両端へ 2 本の円弧に分け、1 つのパスにまとめて 1 回で線を引くと、どのサイズでも左右の差が 1/255 に収まる（2026-10-12）
