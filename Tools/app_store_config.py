#!/usr/bin/env python3
"""`AppStore/languages.json` と `AppStore/screenshots.json`・`AppStore/creative_assets.json` を読む共通処理。

スクリーンショットの撮影（capture_screenshots.sh / capture_mac_screenshots.sh）と
App Store Connect への反映（upload_screenshots.py / upload_metadata.py / upload_creative_assets.py）、
クリエイティブアセットの書き出し（render_creative_assets.sh）、および GitHub Actions のワークフローから使う。
設定はこれらの JSON が単一の定義で、ここには「読んで整合を確かめる」以上のことは書かない。

シェルから使うときはタブ区切りで出す。

    python3 Tools/app_store_config.py languages [ja]      # 言語ごとの撮影・反映の設定
    python3 Tools/app_store_config.py app-languages [ja]  # アプリの対応言語ごとの撮影の設定（チュートリアル画像用）
    python3 Tools/app_store_config.py scenes              # 撮る画面
    python3 Tools/app_store_config.py devices APP_IPHONE_67
    python3 Tools/app_store_config.py sizes APP_IPHONE_67
    python3 Tools/app_store_config.py platform APP_DESKTOP    # IOS / MAC_OS
    python3 Tools/app_store_config.py display-types [APP_IPHONE_67,...]  # GitHub Actions の matrix 用 JSON
    python3 Tools/app_store_config.py creative-assets     # クリエイティブアセットの layout・ファイル名・寸法
    python3 Tools/app_store_config.py bundle-id
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parent.parent
LANGUAGES_FILE = ROOT / "AppStore" / "languages.json"
SUPPORTED_LANGUAGES_FILE = ROOT / "Localization" / "supported-languages.json"
SCREENSHOTS_FILE = ROOT / "AppStore" / "screenshots.json"
CREATIVE_ASSETS_FILE = ROOT / "AppStore" / "creative_assets.json"
PROJECT_FILE = ROOT / "OneTone.xcodeproj" / "project.pbxproj"

#: 1 つの言語・表示サイズに載せられる枚数の上限（App Store Connect の制限）
MAX_SCREENSHOTS = 10

#: このリポジトリでの呼び名 → App Store Connect API の platform。
#: iOS と macOS は同じターゲット・同じ Bundle ID で配信しているが、App Store Connect の
#: バージョンは platform ごとに別物なので、反映先を選ぶときはこの値で絞る
PLATFORMS = {
    "ios": "IOS",
    "macos": "MAC_OS",
}


class Language(NamedTuple):
    #: このリポジトリ内での言語コード。metadata の JSON と撮影結果のフォルダ名
    language: str
    #: -AppleLanguages に渡す値
    apple_language: str
    #: -AppleLocale に渡す値
    apple_locale: str
    #: App Store Connect のロケール
    store_locale: str


class Scene(NamedTuple):
    #: 出力するファイル名（拡張子なし）。この順が App Store の並び順
    file: str
    #: -screenshot-scene に渡す値
    scene: str


class CreativeAsset(NamedTuple):
    #: creative.html に渡す type（`header` / `search`）
    layout: str
    #: AppStore/creative/<言語>/ の下のファイル名
    file: str
    #: 書き出す寸法（px）
    width: int
    height: int
    #: App Asset Library の置き場所（PRODUCT_PAGE_HEADER_ASSET など）
    placement_type: str
    #: Asset Library に上げるときの名前の頭（言語とバージョンを後ろに付ける）
    reference_name: str


def languages(selected: list[str] | None = None) -> list[Language]:
    """指定した言語（省略時は全言語）の設定を返す。知らない言語を指定したらその場で止める。"""
    entries = json.loads(LANGUAGES_FILE.read_text(encoding="utf-8"))["languages"]
    known = {entry["language"]: entry for entry in entries}
    targets = [entry["language"] for entry in entries] if selected is None else selected

    unknown = [language for language in targets if language not in known]
    if unknown:
        raise SystemExit(
            f"{LANGUAGES_FILE.name} に無い言語: {', '.join(unknown)}\n"
            f"指定できるのは: {', '.join(known)}"
        )
    return [
        Language(
            language=language,
            apple_language=known[language]["appleLanguage"],
            apple_locale=known[language]["appleLocale"],
            store_locale=known[language]["storeLocale"],
        )
        for language in targets
    ]


def app_languages(selected: list[str] | None = None) -> list[Language]:
    """アプリが対応する言語（`Localization/supported-languages.json`）ごとの撮影の設定を返す。

    App Store に載せる言語（`AppStore/languages.json`）とは別に、アプリの UI を訳した全言語を撮るときに使う
    （チュートリアルの画像）。`languages()` と同じ形で返し、撮影スクリプトはどちらも同じように読める。
    """
    config = json.loads(SUPPORTED_LANGUAGES_FILE.read_text(encoding="utf-8"))
    known = config["languages"]
    targets = known if selected is None else selected

    unknown = [language for language in targets if language not in known]
    if unknown:
        raise SystemExit(
            f"{SUPPORTED_LANGUAGES_FILE.name} に無い言語: {', '.join(unknown)}\n"
            f"指定できるのは: {', '.join(known)}"
        )
    result = []
    for language in targets:
        entry = config["appStore"][language]
        test_language = entry["testLanguage"]
        # -AppleLocale は「言語_地域」。pt-BR のように言語コードが地域を含むときは地域を重ねない
        base = test_language.split("-")[0] if test_language.endswith(f"-{entry['testRegion']}") else test_language
        result.append(Language(
            language=language,
            apple_language=test_language,
            apple_locale=f"{base}_{entry['testRegion']}",
            store_locale=entry["storeLocale"],
        ))
    return result


def _screenshots_config() -> dict:
    return json.loads(SCREENSHOTS_FILE.read_text(encoding="utf-8"))


def scenes() -> list[Scene]:
    entries = _screenshots_config()["scenes"]
    if len(entries) > MAX_SCREENSHOTS:
        raise SystemExit(
            f"{SCREENSHOTS_FILE.name} の scenes が {len(entries)} 件あります。"
            f"App Store Connect は 1 つの表示サイズにつき {MAX_SCREENSHOTS} 枚までです。"
        )
    return [Scene(file=entry["file"], scene=entry["scene"]) for entry in entries]


def display_type(name: str) -> dict:
    display_types = _screenshots_config()["displayTypes"]
    if name not in display_types:
        raise SystemExit(
            f"{SCREENSHOTS_FILE.name} に無い表示サイズ: {name}\n"
            f"指定できるのは: {', '.join(display_types)}"
        )
    entry = display_types[name]
    if entry.get("platform") not in PLATFORMS.values():
        raise SystemExit(
            f"{SCREENSHOTS_FILE.name} の {name} の platform が不正です: {entry.get('platform')!r}\n"
            f"指定できるのは: {', '.join(PLATFORMS.values())}"
        )
    return entry


def display_type_names(selected: list[str] | None = None) -> list[str]:
    names = list(_screenshots_config()["displayTypes"]) if selected is None else selected
    for name in names:
        display_type(name)
    return names


def platform_for(name: str) -> str:
    """表示サイズが属する App Store Connect の platform（`IOS` / `MAC_OS`）。

    macOS の表示サイズ（APP_DESKTOP）は macOS のバージョンに、それ以外は iOS のバージョンに載る。
    """
    return display_type(name)["platform"]


def platforms(selected: str | None) -> list[str]:
    """`ios` / `macos` / `both`（省略時）を App Store Connect の platform の一覧にする。"""
    if selected in (None, "", "both"):
        return list(PLATFORMS.values())
    if selected not in PLATFORMS:
        raise SystemExit(f"platform は {', '.join(PLATFORMS)}, both のどれかにしてください: {selected}")
    return [PLATFORMS[selected]]


def _creative_assets_config() -> dict:
    return json.loads(CREATIVE_ASSETS_FILE.read_text(encoding="utf-8"))


def creative_assets() -> list[CreativeAsset]:
    return [
        CreativeAsset(
            layout=entry["layout"],
            file=entry["file"],
            width=int(entry["width"]),
            height=int(entry["height"]),
            placement_type=entry["placementType"],
            reference_name=entry.get("referenceName", entry["placementType"]),
        )
        for entry in _creative_assets_config()["assets"]
    ]


def creative_platforms() -> list[str]:
    """クリエイティブアセットを配置する App Store Connect の platform（`IOS` / `MAC_OS`）。"""
    names = _creative_assets_config()["platforms"]
    unknown = [name for name in names if name not in PLATFORMS.values()]
    if unknown or not names:
        raise SystemExit(
            f"{CREATIVE_ASSETS_FILE.name} の platforms が不正です: {names!r}\n"
            f"指定できるのは: {', '.join(PLATFORMS.values())}"
        )
    return names


def bundle_id() -> str:
    """アプリの bundle id を project.pbxproj から読む。ワークフローに書き写すと二重管理になるため。

    pbxproj にはアプリ本体のほか Tests / UITests のターゲットの値も入っている。
    テストバンドルは慣例どおりアプリの bundle id の下（`<app>.OneToneTests` など）にぶら下がるので、
    「ほかの値の接頭辞になっている値」をアプリのものとして採る。1 つに決まらなければ止める。
    """
    found = set(re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = \"?([^\";]+)\"?;", PROJECT_FILE.read_text(encoding="utf-8")))
    candidates = {
        value for value in found
        if not any(value != other and value.startswith(f"{other}.") for other in found)
    }
    if len(candidates) != 1:
        raise SystemExit(
            f"{PROJECT_FILE.name} の PRODUCT_BUNDLE_IDENTIFIER からアプリの値が 1 つに決まりません: "
            f"{', '.join(sorted(found)) or 'なし'}"
        )
    return candidates.pop()


def parse_list(raw: str | None) -> list[str] | None:
    """カンマ区切り（または空白区切り）の指定を配列にする。空なら None（＝すべて）。"""
    if raw is None:
        return None
    items = [item.strip() for item in raw.replace(",", " ").split()]
    return items or None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "command",
        choices=(
            "languages", "app-languages", "scenes", "devices", "sizes", "platform", "display-types",
            "creative-assets", "bundle-id",
        ),
    )
    parser.add_argument("argument", nargs="?", default=None)
    args = parser.parse_args()

    if args.command in ("languages", "app-languages"):
        read = languages if args.command == "languages" else app_languages
        for entry in read(parse_list(args.argument)):
            print("\t".join(entry))
    elif args.command == "scenes":
        for entry in scenes():
            print("\t".join(entry))
    elif args.command in ("devices", "sizes"):
        if not args.argument:
            raise SystemExit("表示サイズ（例: APP_IPHONE_67）を指定してください")
        for value in display_type(args.argument)[args.command]:
            print(value)
    elif args.command == "platform":
        if not args.argument:
            raise SystemExit("表示サイズ（例: APP_DESKTOP）を指定してください")
        print(platform_for(args.argument))
    elif args.command == "creative-assets":
        for entry in creative_assets():
            print("\t".join([entry.layout, entry.file, str(entry.width), str(entry.height)]))
    elif args.command == "bundle-id":
        print(bundle_id())
    else:
        names = display_type_names(parse_list(args.argument))
        print(json.dumps(
            [
                {
                    "display_type": name,
                    "label": display_type(name)["label"],
                    "platform": display_type(name)["platform"],
                }
                for name in names
            ],
            ensure_ascii=False,
        ))
    return 0


if __name__ == "__main__":
    sys.exit(main())
