#!/bin/bash
set -euo pipefail

# App Store のクリエイティブアセット（プロダクトページのヘッダー / 検索結果）を書き出す。
#
#   Tools/render_creative_assets.sh [ja,en,…]
#
# 元は AppStore/creative/src/creative.html。種類・ファイル名・寸法は AppStore/creative_assets.json、
# 言語は AppStore/languages.json（省略すると全言語）。
# 素材は、ロゴの書体（OneTone/Assets.xcassets/LogoFont.dataset。改変せずに使う）・マーク（OneTone/AppIcon.icon のレイヤー）と、
# iPhone 6.9 inch のスクリーンショット（Tools/capture_screenshots.sh APP_IPHONE_67 の出力。既定は build/screenshots/APP_IPHONE_67）。
# Google Chrome をヘッドレスで開いて実寸で撮り、アルファを落として AppStore/creative/<言語>/ に保存する。
# 書き出したら差分を見てコミットし、Creative assets/App Store ワークフローで反映する。

LANGUAGES="${1:-}"

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SCREENSHOTS="${SCREENSHOTS_DIR:-$ROOT_DIR/build/screenshots}/APP_IPHONE_67"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
SOURCE="AppStore/creative/src/creative.html"
OUTPUT_DIR="AppStore/creative"
CONFIG="python3 Tools/app_store_config.py"

if [ ! -x "$CHROME" ]; then
    echo "Google Chrome が見つかりません（CHROME で場所を指定できます）: $CHROME" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$SOURCE" "$WORK/"
cp OneTone/Assets.xcassets/LogoFont.dataset/Audiowide-Regular.ttf "$WORK/"
mkdir -p "$WORK/mark"
cp OneTone/AppIcon.icon/Assets/*.svg "$WORK/mark/"

REMOVE_ALPHA="$WORK/remove_alpha"
xcrun swiftc -O Tools/remove_alpha.swift -o "$REMOVE_ALPHA"

# 書き出す種類: <layout> <ファイル名> <幅> <高さ>
TARGETS="$($CONFIG creative-assets)"

while IFS=$'\t' read -r -u 3 language _ _ _; do
    # creative.html の copy に、その言語の文言が無いと絵だけの画像になる
    if ! grep -Eq "^    (\"${language}\"|${language}): \{" "$SOURCE"; then
        echo "$SOURCE の copy に $language の文言がありません。" >&2
        exit 1
    fi
    if [ ! -d "$SCREENSHOTS/$language" ]; then
        echo "$SCREENSHOTS/$language がありません。先に Tools/capture_screenshots.sh APP_IPHONE_67 で撮ってください。" >&2
        exit 1
    fi
    mkdir -p "$WORK/screens/$language" "$OUTPUT_DIR/$language"
    cp "$SCREENSHOTS/$language"/*.png "$WORK/screens/$language/"

    while IFS=$'\t' read -r layout file width height; do
        output="$OUTPUT_DIR/$language/$file"
        "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
            --allow-file-access-from-files --virtual-time-budget=5000 \
            --window-size="$width,$height" --screenshot="$ROOT_DIR/$output" \
            "file://$WORK/creative.html?type=$layout&lang=$language" >/dev/null 2>&1
        "$REMOVE_ALPHA" "$output"
        actual="$(sips -g pixelWidth -g pixelHeight "$output" | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w "x" h}')"
        if [ "$actual" != "${width}x${height}" ]; then
            echo "${output} の寸法が ${width}x${height} ではありません（${actual}）" >&2
            exit 1
        fi
        echo "${output}（${actual}）"
    done <<< "$TARGETS"
done 3< <($CONFIG languages "$LANGUAGES")

# 寸法と透過を、反映のときと同じ検査で確かめる
python3 Tools/upload_creative_assets.py --check ${LANGUAGES:+--languages "$LANGUAGES"}
