#!/bin/bash
set -euo pipefail

# チュートリアルの各ページに載せる画面を、アプリの対応言語ごとに macOS / iOS それぞれ撮り、OneTone/Assets.xcassets/Tutorial に置く。
# UI を変えたら撮り直す。
#
#   Tools/capture_tutorial_screenshots.sh                # 全言語、macOS と iOS の両方
#   Tools/capture_tutorial_screenshots.sh mac            # 全言語、macOS だけ
#   Tools/capture_tutorial_screenshots.sh ios ja,de      # ja と de だけ、iOS だけ
#   PAGES="welcome playback" Tools/capture_tutorial_screenshots.sh ios   # 2 ページだけ、iOS だけ
#
# 言語は Localization/supported-languages.json の languages（撮影時の言語・地域は appStore の testLanguage / testRegion）。
# 撮影は App Store 用と同じ撮影モード（OneTone/ScreenshotDemo.swift）と撮影スクリプト
# （Tools/capture_mac_screenshots.sh / Tools/capture_screenshots.sh）で行い、撮る画面だけを環境変数 SCENES で差し替える。
# AppStore/screenshots.json（App Store 用の画面）は使わないし変えない。
#
# 画像セットは Tutorial-<ページ名>.imageset で、言語ごとに macOS 用（idiom: mac）と iOS 用（idiom: universal。iPhone で撮ったもの）の 2 枚を持つ。
# ソース言語（en）は ios.png / mac.png で locale を付けない（対応外の言語の端末でも出る既定の画像）。
# それ以外の言語は ios-<言語>.png / mac-<言語>.png に locale を付けて置き、端末の言語で出し分ける（画像セットのローカライズ）。
# ページ名は TutorialPage.ID、撮影の場面は ScreenshotDemo.Scene の tutorial-<ページ名> と一致させる。
# アプリの容量を抑えるため、macOS は幅 MAC_WIDTH px、iOS は高さ IOS_HEIGHT px に縮める。

TARGETS="${1:-all}"
LANGUAGES="${2:-}"

ROOT_DIR="$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

# 撮るページ。一部のページだけ撮り直すときは環境変数 PAGES で上書きする（例: PAGES="playback volume"）
PAGES="${PAGES:-welcome playback frequency volume waveform note chord}"
ASSETS_DIR="OneTone/Assets.xcassets/Tutorial"
# 撮った画面を一時的に置く場所（リポジトリの外）
WORK_DIR="${WORK_DIR:-${TMPDIR:-/tmp}/OneToneTutorialScreenshots}"
# 撮影スクリプトの言語の一覧を、App Store の言語ではなくアプリの対応言語から取る
export LANGUAGES_COMMAND=app-languages
SOURCE_LANGUAGE="$(python3 -c 'import json; print(json.load(open("Localization/supported-languages.json"))["sourceLanguage"])')"
# プロセス置換の中で失敗しても set -e では止まらないので、先に取り出して言語の指定を確かめておく
LANGUAGE_CODES="$(python3 Tools/app_store_config.py app-languages "$LANGUAGES" | cut -f1)"
MAC_WIDTH="${MAC_WIDTH:-1280}"
IOS_HEIGHT="${IOS_HEIGHT:-1400}"

SCENES=""
for page in $PAGES; do
    SCENES="${SCENES}${page}"$'\t'"tutorial-${page}"$'\n'
done
SCENES="${SCENES%$'\n'}"
export SCENES

# 言語ごとの画像のファイル名。ソース言語は locale の無い既定の画像にする
image_file() {
    platform="$1"
    language="$2"
    if [ "$language" = "$SOURCE_LANGUAGE" ]; then
        echo "${platform}.png"
    else
        echo "${platform}-${language}.png"
    fi
}

# 撮った PNG を縮めて画像セットに置く
place() {
    source_root="$1"
    platform="$2"
    shift 2
    for language in $LANGUAGE_CODES; do
        for page in $PAGES; do
            imageset="$ASSETS_DIR/Tutorial-${page}.imageset"
            file="$imageset/$(image_file "$platform" "$language")"
            mkdir -p "$imageset"
            cp "$source_root/$language/${page}.png" "$file"
            sips "$@" "$file" >/dev/null
        done
    done
}

case "$TARGETS" in
    all | mac | ios) ;;
    *) echo "使い方: $0 [all|mac|ios]" >&2; exit 1 ;;
esac

if [ "$TARGETS" = all ] || [ "$TARGETS" = mac ]; then
    # キャンバスを描き出す大きさ（ScreenshotDemo.renderSize）と同じにして、余白を付けない
    SCREENSHOTS_DIR="$WORK_DIR/mac" CANVAS=1280x800 Tools/capture_mac_screenshots.sh "$LANGUAGES"
    place "$WORK_DIR/mac/APP_DESKTOP" mac --resampleWidth "$MAC_WIDTH"
fi

if [ "$TARGETS" = all ] || [ "$TARGETS" = ios ]; then
    SCREENSHOTS_DIR="$WORK_DIR/ios" Tools/capture_screenshots.sh APP_IPHONE_67 "$LANGUAGES"
    place "$WORK_DIR/ios/APP_IPHONE_67" ios --resampleHeight "$IOS_HEIGHT"
fi

# 画像セットの定義。一部の言語・片方の OS だけ撮り直したときも、置いてある画像すべてを指す形で書き直す
python3 Tools/write_tutorial_imagesets.py "$ASSETS_DIR" $PAGES

echo "$ASSETS_DIR に保存しました"
