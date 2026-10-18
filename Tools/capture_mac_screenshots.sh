#!/bin/bash
set -euo pipefail

# App Store 用のスクリーンショット（macOS、表示サイズ APP_DESKTOP）を全言語・全画面ぶん撮る。
# iOS は Simulator で撮る Tools/capture_screenshots.sh を使う。
#
#   Tools/capture_mac_screenshots.sh [ja]
#
# 撮る画面は AppStore/screenshots.json、言語は AppStore/languages.json で決める（iOS と共通）。
# macOS 向けにビルドした .app を、画面ごとに起動引数「撮影モード」「撮る画面」「保存先」「言語」付きで起動する。
# アプリは画面外ウィンドウの NSHostingView を cacheDisplay で 1280x800 pt（2 倍の 2560x1600 px）の PNG に描いてすぐ終了する
# （OneTone/ScreenshotDemo.swift）。CI のランナーにはディスプレイが無くウィンドウが作られないため、
# ウィンドウを screencapture で撮る方式は使えない。描いた画面は Tools/compose_mac_screenshot.swift で
# App Store が受け付ける 2880x1800 のキャンバスに合成する。
#
# 出力先: $SCREENSHOTS_DIR/APP_DESKTOP/<言語>/01_sine.png …（既定は build/screenshots）

LANGUAGES="${1:-}"
DISPLAY_TYPE="APP_DESKTOP"

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT="OneTone.xcodeproj"
SCHEME="${SCHEME:-OneTone}"
CONFIGURATION="${CONFIGURATION:-Debug}"
SCREENSHOTS_DIR="${SCREENSHOTS_DIR:-$ROOT_DIR/build/screenshots}"
# DerivedData はリポジトリ外に置く（手元の別のビルドと混ざらないようにする）
DERIVED_DATA="${DERIVED_DATA:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/OneToneMacScreenshotDerivedData}"
# キャンバスの大きさ（pt）。アプリが 2 倍で描くので、出力は 2880x1800 px になる
CANVAS="${CANVAS:-1440x900}"
# アプリの描き出す幅（pt）。ScreenshotDemo.renderSize と合わせる
RENDER_WIDTH="${RENDER_WIDTH:-1280}"
# 1 枚を描き終えるまで待つ上限（秒）
RENDER_TIMEOUT="${RENDER_TIMEOUT:-60}"

CONFIG="python3 Tools/app_store_config.py"

# MARK: - ビルド

# 配布ビルド（Upload ワークフロー）と同じ ad-hoc 署名にするが、App Sandbox は外す。
# サンドボックス内からは指定した保存先に PNG を書けないため。撮影用のビルドだけで、配布ビルドには影響しない
echo "$SCHEME を macOS 向けにビルドします（撮影用・サンドボックス無し）"
xcodebuild build \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -quiet \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    PROVISIONING_PROFILE_SPECIFIER= \
    CODE_SIGN_ENTITLEMENTS= \
    ENABLE_APP_SANDBOX=NO

SETTINGS="$(xcodebuild -showBuildSettings \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA")"
BUILT_DIR="$(printf '%s\n' "$SETTINGS" | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')"
APP_NAME="$(printf '%s\n' "$SETTINGS" | awk -F' = ' '/ FULL_PRODUCT_NAME /{print $2; exit}')"
EXECUTABLE_NAME="$(printf '%s\n' "$SETTINGS" | awk -F' = ' '/ EXECUTABLE_NAME /{print $2; exit}')"
EXECUTABLE="$BUILT_DIR/$APP_NAME/Contents/MacOS/$EXECUTABLE_NAME"
[ -x "$EXECUTABLE" ] || { echo "::error::$EXECUTABLE がありません" >&2; exit 1; }

# 補助ツールは swiftc で都度ビルドする（バイナリをリポジトリに置かない）
TOOLS_BIN="$(mktemp -d)"
xcrun swiftc -O Tools/compose_mac_screenshot.swift -o "$TOOLS_BIN/compose_mac_screenshot"
xcrun swiftc -O Tools/remove_alpha.swift -o "$TOOLS_BIN/remove_alpha"

# MARK: - 撮影

APP_PID=""
cleanup() {
    if [ -n "$APP_PID" ]; then
        kill "$APP_PID" 2>/dev/null || true
    fi
    rm -rf "$TOOLS_BIN"
}
# bash 3.2 では unbound variable で止まったとき EXIT トラップに終了コード 0 が渡り、失敗したのにステップが成功扱いになる。
# 最後まで到達した印（FINISHED）が無ければ失敗として返す
FINISHED=0
trap 'status=$?; if [ "$status" -eq 0 ] && [ "$FINISHED" -ne 1 ]; then status=1; fi; cleanup; exit "$status"' EXIT

# アプリを撮影モードで起動し、画面を PNG に描き終えるまで待つ
render_scene() {
    scene="$1"
    apple_language="$2"
    apple_locale="$3"
    output="$4"
    log="$(mktemp)"
    # 実行ファイルを直接動かす。ウィンドウは要らないので open（LaunchServices）を通す必要がない
    "$EXECUTABLE" \
        -screenshot-demo \
        -screenshot-scene "$scene" \
        -screenshot-output "$output" \
        -AppleLanguages "($apple_language)" \
        -AppleLocale "$apple_locale" >"$log" 2>&1 &
    APP_PID=$!

    elapsed=0
    while kill -0 "$APP_PID" 2>/dev/null; do
        if [ "$elapsed" -ge "$RENDER_TIMEOUT" ]; then
            kill "$APP_PID" 2>/dev/null || true
            echo "::error::${RENDER_TIMEOUT} 秒たっても画面を描き終えませんでした（scene: ${scene}）" >&2
            cat "$log" >&2
            rm -f "$log"
            return 1
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    status=0
    wait "$APP_PID" || status=$?
    APP_PID=""
    if [ "$status" -ne 0 ] || [ ! -s "$output" ]; then
        echo "::error::画面を描けませんでした（scene: ${scene}、終了コード ${status}）" >&2
        cat "$log" >&2
        rm -f "$log"
        return 1
    fi
    cat "$log"
    rm -f "$log"
}

# プロセス置換の中で失敗しても set -e では止まらないので、先に取り出しておく
LANGUAGE_LIST="$($CONFIG languages "$LANGUAGES")"
SCENE_LIST="$($CONFIG scenes)"

while IFS=$'\t' read -r -u 3 language apple_language apple_locale store_locale; do
    destination="$SCREENSHOTS_DIR/$DISPLAY_TYPE/$language"
    # 撮り直しのたびに古い画像が混ざらないよう、言語ごとに作り直す
    rm -rf "$destination"
    mkdir -p "$destination"
    echo "::group::$DISPLAY_TYPE / ${language}（${store_locale}）"
    while IFS=$'\t' read -r -u 4 file scene; do
        raw="$(mktemp -d)/screen.png"
        render_scene "$scene" "$apple_language" "$apple_locale" "$raw"
        "$TOOLS_BIN/compose_mac_screenshot" "$raw" "$destination/$file.png" "$RENDER_WIDTH" "$CANVAS"
        rm -rf "$(dirname "$raw")"
    done 4< <(printf '%s\n' "$SCENE_LIST")
    echo "::endgroup::"
done 3< <(printf '%s\n' "$LANGUAGE_LIST")

# MARK: - 検証

# 合成の時点でアルファは無いはずだが、iOS と同じ手順で描き直して確実に RGB にする
find "$SCREENSHOTS_DIR/$DISPLAY_TYPE" -name '*.png' -print0 | xargs -0 "$TOOLS_BIN/remove_alpha"

# App Store Connect は寸法が 1px でも違えば弾く
python3 Tools/verify_screenshots.py \
    --directory "$SCREENSHOTS_DIR/$DISPLAY_TYPE" \
    --sizes "$($CONFIG sizes "$DISPLAY_TYPE" | paste -sd, -)"

FINISHED=1
echo "$SCREENSHOTS_DIR/$DISPLAY_TYPE に保存しました"
