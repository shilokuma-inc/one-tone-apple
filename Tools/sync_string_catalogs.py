#!/usr/bin/env python3
"""ソースコードから String Catalog にキーを同期する。

Xcode.app でビルドすると `.xcstrings` へのキー追加は自動で行われるが、
`xcodebuild` では行われない。コマンドラインで作業するときはこのスクリプトを使う。

やっていること:
  1. `xcodebuild build` で各ソースファイルの `.stringsdata` を作らせる（macOS と iOS の両方）
  2. `xcrun xcstringstool sync` で `.stringsdata` を `.xcstrings` にマージする

`#if os(macOS)` / `#if os(iOS)` の片方にしか無い文言もあるため、両方のプラットフォームの
`.stringsdata` をまとめて渡す。片方だけ渡すと、もう片方にしか無いキーが stale にされる。

使い方:
    python3 Tools/sync_string_catalogs.py
    python3 Tools/sync_string_catalogs.py --no-build                 # 直前のビルド成果物を使う
    python3 Tools/sync_string_catalogs.py --derived-data <ディレクトリ>  # -derivedDataPath を指定する
"""

from __future__ import annotations

import argparse
import os
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
PROJECT = "OneTone.xcodeproj"
SCHEME = "OneTone"
TARGET = "OneTone"
DESTINATIONS = ("generic/platform=macOS", "generic/platform=iOS Simulator")

# 1 ターゲット・1 テーブル。InfoPlist.xcstrings を足しても sync には渡さない
# （キーが Info.plist 側にしかなく、渡すと毎回 extractionState を "stale" にされるため）
CATALOGS = ["OneTone/Localizable.xcstrings"]


def xcodebuild(destination: str, derived_data: str | None, *args: str, capture: bool = False) -> subprocess.CompletedProcess[str]:
    command = [
        "xcodebuild",
        "-project", PROJECT,
        "-scheme", SCHEME,
        "-destination", destination,
        *(["-derivedDataPath", derived_data] if derived_data else []),
        # SwiftLint のビルドツールプラグインの信頼確認を飛ばすのは、中身を確かめたチェックアウトで
        # SKIP_PACKAGE_PLUGIN_VALIDATION=1 を付けたときだけ（既定では Xcode.app で信頼しておく）
        *(["-skipPackagePluginValidation"] if os.environ.get("SKIP_PACKAGE_PLUGIN_VALIDATION") == "1" else []),
        # 署名は文言の抽出に関係ないので外す（手元に証明書が無くても動くように）
        "CODE_SIGNING_ALLOWED=NO",
        *args,
    ]
    return subprocess.run(command, cwd=ROOT, text=True, capture_output=capture, check=False)


def build_settings(destination: str, derived_data: str | None) -> dict[str, str]:
    """`-showBuildSettings` から中間生成物の場所を割り出すための設定を読む。"""
    result = xcodebuild(destination, derived_data, "-showBuildSettings", capture=True)
    if result.returncode != 0:
        sys.exit(f"xcodebuild -showBuildSettings が失敗しました:\n{result.stderr}")
    settings: dict[str, str] = {}
    for line in result.stdout.splitlines():
        if " = " not in line:
            continue
        key, _, value = line.strip().partition(" = ")
        settings.setdefault(key, value)
    return settings


def stringsdata_files(destination: str, derived_data: str | None) -> list[pathlib.Path]:
    """対象プラットフォームの `.stringsdata` を集める。

    中間生成物は `<OBJROOT>/<Project>.build/<Config><Platform>/<Target>.build/Objects-normal/<arch>/`
    に置かれる。テストターゲットや他プラットフォームのものを拾わないよう、ターゲットまで絞って探す。
    """
    settings = build_settings(destination, derived_data)
    objroot = pathlib.Path(settings["OBJROOT"])
    config_dir = settings["CONFIGURATION"] + settings.get("EFFECTIVE_PLATFORM_NAME", "")
    base = objroot / f"{SCHEME}.build" / config_dir / f"{TARGET}.build" / "Objects-normal"
    return sorted(base.glob("*/*.stringsdata"))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--no-build", action="store_true", help="ビルドを省略し、直前の成果物を使う")
    parser.add_argument("--derived-data", help="xcodebuild の -derivedDataPath")
    args = parser.parse_args()

    files: list[pathlib.Path] = []
    for destination in DESTINATIONS:
        if not args.no_build:
            print(f"==> ビルドして .stringsdata を生成（{destination}）")
            if xcodebuild(destination, args.derived_data, "build", "-quiet").returncode != 0:
                return 1
        found = stringsdata_files(destination, args.derived_data)
        if not found:
            print(f"!! {destination}: .stringsdata が見つかりません（ビルドが必要かもしれません）")
            return 1
        files.extend(found)

    command = ["xcrun", "xcstringstool", "sync", *CATALOGS, "--stringsdata", *map(str, files)]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True, check=False)
    if result.returncode != 0:
        print(f"!! sync に失敗\n{result.stderr}")
        return 1
    print(f"==> 同期しました（.stringsdata {len(files)} 件）: {', '.join(CATALOGS)}")
    if result.stderr.strip():
        print(result.stderr.strip())

    # sync は Xcode と同じ整形で書き出すが、スクリプトで編集した直後は崩れていることがある
    if subprocess.run([sys.executable, "Tools/format_string_catalogs.py"], cwd=ROOT, check=False).returncode != 0:
        return 1

    print("\n同期が完了しました。未翻訳のキーに訳を入れてください。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
