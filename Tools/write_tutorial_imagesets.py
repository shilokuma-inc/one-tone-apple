#!/usr/bin/env python3
"""チュートリアルの画像セット（`Tutorial-<ページ名>.imageset`）の Contents.json を、置いてある画像から書き直す。

`Tools/capture_tutorial_screenshots.sh` が撮影のあとに呼ぶ。一部の言語・片方の OS だけ撮り直しても、
画像セットに置いてある画像すべてを指す形にそろえる。

画像のファイル名と出し分け:
  ios.png / mac.png                 ソース言語（en）。locale を付けない既定の画像（対応外の言語の端末でも出る）
  ios-<言語>.png / mac-<言語>.png   それ以外の言語。locale を付けて端末の言語で出し分ける

言語は `Localization/supported-languages.json` の languages に限る（知らない言語の画像があれば止める）。

    python3 Tools/write_tutorial_imagesets.py OneTone/Assets.xcassets/Tutorial welcome playback ...
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SUPPORTED_LANGUAGES_FILE = ROOT / "Localization" / "supported-languages.json"

#: 画像のファイル名の先頭 → asset catalog の idiom
IDIOMS = {"ios": "universal", "mac": "mac"}
FILE_NAME = re.compile(r"^(ios|mac)(?:-(.+))?\.png$")
INFO = {"author": "xcode", "version": 1}


def dump(data: dict) -> str:
    """Xcode が書くのと同じ形（キーの後ろに空白を入れた `" : "`、2 字下げ）にする。"""
    return json.dumps(data, indent=2, ensure_ascii=False, separators=(",", " : ")) + "\n"


def images(imageset: Path, config: dict) -> list[dict]:
    order = config["languages"]
    entries = []
    for path in imageset.glob("*.png"):
        match = FILE_NAME.match(path.name)
        if not match:
            raise SystemExit(f"{path}: ファイル名が ios.png / mac.png / ios-<言語>.png / mac-<言語>.png のどれでもありません")
        platform, language = match.groups()
        if language is not None and language not in order:
            raise SystemExit(f"{path}: {SUPPORTED_LANGUAGES_FILE.name} に無い言語です（{language}）")
        if language == config["sourceLanguage"]:
            raise SystemExit(f"{path}: ソース言語の画像は {platform}.png に置きます")
        entry = {"filename": path.name, "idiom": IDIOMS[platform]}
        if language is not None:
            entry["locale"] = language
        entries.append(entry)
    # 既定の画像を先に、あとは言語の定義順・iOS → macOS の順に並べて、撮り直しても差分が出ないようにする
    entries.sort(key=lambda e: (order.index(e["locale"]) if "locale" in e else -1, e["idiom"] != "universal"))
    return entries


def main() -> int:
    if len(sys.argv) < 3:
        raise SystemExit("使い方: write_tutorial_imagesets.py <Tutorial フォルダ> <ページ名>...")
    assets_dir = Path(sys.argv[1])
    config = json.loads(SUPPORTED_LANGUAGES_FILE.read_text(encoding="utf-8"))

    assets_dir.mkdir(parents=True, exist_ok=True)
    (assets_dir / "Contents.json").write_text(dump({"info": INFO}), encoding="utf-8")
    for page in sys.argv[2:]:
        imageset = assets_dir / f"Tutorial-{page}.imageset"
        entries = images(imageset, config)
        missing = [f"{platform}.png" for platform in IDIOMS if not (imageset / f"{platform}.png").exists()]
        if missing:
            raise SystemExit(f"{imageset}: ソース言語の画像（{', '.join(missing)}）がありません")
        contents = {"images": entries, "info": INFO}
        if any("locale" in e for e in entries):
            # 言語ごとの画像を出し分ける印（Xcode の Localize… と同じ）
            contents["properties"] = {"localizable": True}
        (imageset / "Contents.json").write_text(dump(contents), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
