#!/usr/bin/env python3
"""App Store の説明文・キーワード・プロモーションテキスト・URL・審査メモを App Store Connect に反映する。

`AppStore/metadata/<言語>.json` と `AppStore/metadata/shared.json` を読み、
対象バージョンの言語ごとに書き込む。`AppStore/metadata/review_notes.txt` があれば、
App Review Information の Notes（審査メモ）にも書き込む。審査メモは言語ごとではなく
バージョンごとに 1 つなので、言語によらず同じ内容になる。

    python3 Tools/upload_metadata.py            # 反映する
    python3 Tools/upload_metadata.py --dry-run  # 現在値との差分だけ出す
    python3 Tools/upload_metadata.py --check    # App Store Connect につながず、手元のファイルだけ検査する
    python3 Tools/upload_metadata.py --export   # App Store Connect の現在値を AppStore/metadata の JSON に書き出す

このアプリは iOS と macOS を同じ Bundle ID で配信しているが、App Store Connect のバージョン
（と説明文）は platform ごとに別物。`--platform ios` / `--platform macos` / `--platform both`（既定）で
反映先を選ぶ。both のときは両方のバージョンに同じ内容を書き込む。

認証は App Store Connect API Key（.p8）。次の環境変数でも渡せる。

    APP_STORE_CONNECT_KEY_ID / APP_STORE_CONNECT_ISSUER_ID / APP_STORE_CONNECT_PRIVATE_KEY_PATH

触るのは **編集できる状態のバージョンだけ**。審査中や配信済みのバージョンは対象にしない。
JSON に書いていない項目（例: 省略した promotionalText）は App Store Connect 側の値をそのまま残す。

PyJWT が要る（--check では不要）: `python3 -m pip install pyjwt cryptography`
"""

from __future__ import annotations

import argparse
import difflib
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from app_store_config import ROOT, Language, bundle_id, languages, parse_list, platforms

METADATA_DIR = ROOT / "AppStore" / "metadata"

#: 言語によらない値をまとめたファイル
SHARED_FILE = "shared.json"

#: App Store Connect 側の上限。超えると反映時に弾かれるので、手元で先に落とす。
LIMITS = {
    "description": 4000,
    "keywords": 100,
    "promotionalText": 170,
}

#: App Review Information の Notes に書く内容。言語によらず 1 つ。無ければ App Store Connect 側の値をそのまま残す
REVIEW_NOTES_FILE = "review_notes.txt"

#: Notes の上限（App Store Connect の画面と同じ）
REVIEW_NOTES_LIMIT = 4000

#: `--export` が書き出すファイルに付けるコメント（既にファイルがあればそちらの _comment を残す）
SHARED_COMMENT = [
    "言語によらず同じ値を使う App Store のメタデータ。iOS / macOS の両バージョンに同じ値を書き込む。",
    "supportUrl は Apple の審査で実際に開かれるので、必ず到達できる URL にすること。",
    "marketingUrl は任意。消すと App Store Connect 側の値をそのまま残す。",
]
LANGUAGE_COMMENT = [
    "App Store の説明文など。上限: description 4000 字 / keywords 合計 100 字（カンマ込み）/ promotionalText 170 字。",
    "promotionalText は省略できる（省略すると App Store Connect 側の値をそのまま残す）。",
    "初期値は Tools/upload_metadata.py --export で App Store Connect の現在値を取り込んだもの。",
]


def load_shared(directory: Path) -> tuple[dict[str, str], list[str]]:
    path = directory / SHARED_FILE
    if not path.is_file():
        return {}, [f"{path} がありません"]
    raw = json.loads(path.read_text(encoding="utf-8"))
    problems = []
    attributes = {}
    # supportUrl は審査で実際に開かれるので必須。marketingUrl は任意
    for key, required in (("supportUrl", True), ("marketingUrl", False)):
        value = raw.get(key)
        if isinstance(value, str) and value.strip():
            if not value.startswith("https://"):
                problems.append(f"{path}: {key} は https:// で始まる URL にしてください")
            attributes[key] = value
        elif required:
            problems.append(f"{path}: {key} がありません")
    return attributes, problems


def load_review_notes(directory: Path) -> tuple[str | None, list[str]]:
    """審査メモを読む。ファイルが無ければ None（App Store Connect 側の値を残す）。"""
    path = directory / REVIEW_NOTES_FILE
    if not path.is_file():
        return None, []
    # 末尾の改行の有無で毎回差分が出ないよう、前後の空白は落として比べる
    notes = path.read_text(encoding="utf-8").strip()
    if not notes:
        return None, [f"{path} が空です（使わないならファイルごと消す）"]
    if len(notes) > REVIEW_NOTES_LIMIT:
        return None, [f"{path} が {len(notes)} 字あります（上限 {REVIEW_NOTES_LIMIT} 字）"]
    return notes, []


def apply_review_notes(client, version_id: str, notes: str, dry_run: bool) -> None:
    """そのバージョンの審査メモを `notes` にする。審査情報がまだ無ければ作る。"""
    detail = client.review_detail(version_id)
    if detail is None:
        client.create_review_detail(version_id, {"notes": notes})
        print(f"  審査メモ: {'審査情報を作って書き込む予定' if dry_run else '審査情報を作って書き込み'}")
        for line in describe_changes({}, {"notes": notes}):
            print(line)
        return

    changes = describe_changes({"notes": (detail["attributes"].get("notes") or "").strip()}, {"notes": notes})
    if not changes:
        print("  審査メモ: 変更なし")
        return
    print(f"  審査メモ: {'書き込む予定' if dry_run else '書き込み'}")
    for line in changes:
        print(line)
    if not dry_run:
        client.patch(
            f"/v1/appStoreReviewDetails/{detail['id']}",
            {"data": {"type": "appStoreReviewDetails", "id": detail["id"], "attributes": {"notes": notes}}},
        )


def load(directory: Path, target: Language, shared: dict[str, str]) -> tuple[dict[str, str] | None, list[str]]:
    """1 言語ぶんの書き込む値を読む。問題があれば値の代わりに理由を返す。"""
    path = directory / f"{target.language}.json"
    if not path.is_file():
        return None, [f"{path} がありません"]
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        return None, [f"{path} が JSON として読めません: {error}"]

    problems: list[str] = []
    attributes: dict[str, str] = {}

    description = raw.get("description")
    if isinstance(description, str) and description.strip():
        attributes["description"] = description
    else:
        problems.append(f"{path}: description がありません")

    keywords = raw.get("keywords")
    if isinstance(keywords, list) and keywords:
        # App Store Connect にはカンマ区切りの 1 本の文字列として渡す。
        # 区切りのあとに空白を入れると、そのぶん 100 字の枠を食うので詰めて繋ぐ。
        attributes["keywords"] = ",".join(str(keyword).strip() for keyword in keywords)
    else:
        problems.append(f"{path}: keywords がありません（配列で書く）")

    promotional_text = raw.get("promotionalText")
    if promotional_text is not None:
        if isinstance(promotional_text, str) and promotional_text.strip():
            attributes["promotionalText"] = promotional_text
        else:
            problems.append(f"{path}: promotionalText が空です（使わないなら項目ごと消す）")

    for field, limit in LIMITS.items():
        value = attributes.get(field, "")
        if len(value) > limit:
            problems.append(f"{path}: {field} が {len(value)} 字あります（上限 {limit} 字）")

    if problems:
        return None, problems
    return {**attributes, **shared}, []


def describe_changes(current: dict, new: dict[str, str]) -> list[str]:
    """現在値から変わる項目を、人が読める形で返す。長い文章は行単位の差分にする。"""
    lines: list[str] = []
    for field, value in new.items():
        before = current.get(field) or ""
        if before == value:
            continue
        if "\n" in before or "\n" in value:
            lines.append(f"    {field}:")
            diff = difflib.unified_diff(before.splitlines(), value.splitlines(), lineterm="", n=1)
            lines.extend(f"      {line}" for line in list(diff)[2:])
        else:
            lines.append(f"    {field}: {before or '（空）'} → {value}")
    return lines


# MARK: - export

def exported_shared(attributes: dict) -> dict:
    """App Store Connect の現在値から shared.json の中身を組み立てる。"""
    result = {key: attributes[key] for key in ("supportUrl", "marketingUrl") if attributes.get(key)}
    return result


def exported_language(attributes: dict) -> dict:
    """App Store Connect の現在値から <言語>.json の中身を組み立てる。"""
    result: dict = {}
    if attributes.get("promotionalText"):
        result["promotionalText"] = attributes["promotionalText"]
    result["description"] = attributes.get("description") or ""
    result["keywords"] = [
        keyword.strip() for keyword in (attributes.get("keywords") or "").split(",") if keyword.strip()
    ]
    return result


def write_json(path: Path, body: dict, default_comment: list[str]) -> None:
    """`_comment` を先頭に置いて書き出す。既にあるファイルの `_comment` は引き継ぐ。"""
    comment = default_comment
    if path.is_file():
        try:
            existing = json.loads(path.read_text(encoding="utf-8")).get("_comment")
            if isinstance(existing, list) and existing:
                comment = existing
        except json.JSONDecodeError:
            pass
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"_comment": comment, **body}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def export(directory: Path, targets: list[Language], current: dict[str, dict[str, dict]],
           review_notes: dict[str, str]) -> int:
    """platform ごとの現在値（platform → store_locale → attributes）を AppStore/metadata に書き出す。

    `review_notes` は platform → 審査メモ。空のものは書き出さない。

    both のときは iOS と macOS で値が食い違うことがある（別々に手で編集してきたため）。
    どちらを正にするかは人が決めることなので、食い違いがあれば書き出さずに差分を出して止める。
    """
    platforms_found = list(current)
    if not platforms_found:
        print("書き出せる現在値がありません")
        return 1

    conflicts: list[str] = []
    first = platforms_found[0]
    for other in platforms_found[1:]:
        for target in targets:
            before = current[first].get(target.store_locale, {})
            after = current[other].get(target.store_locale, {})
            lines = describe_changes(before, {
                field: after.get(field) or ""
                for field in ("description", "keywords", "promotionalText", "supportUrl", "marketingUrl")
            })
            if lines:
                conflicts.append(f"  {target.store_locale}: {first} と {other} で値が違います")
                conflicts.extend(lines)
        lines = describe_changes({"notes": review_notes.get(first, "")}, {"notes": review_notes.get(other, "")})
        if lines:
            conflicts.append(f"  審査メモ: {first} と {other} で値が違います")
            conflicts.extend(lines)
    if conflicts:
        print("platform の間で現在値が食い違っているため書き出しません。--platform で片方を選んでください。")
        print("\n".join(conflicts))
        return 1

    values = current[first]
    missing = [target.store_locale for target in targets if target.store_locale not in values]
    if missing:
        print(f"App Store Connect に無い言語なので書き出せません: {', '.join(missing)}")
        return 1

    shared_source = values[targets[0].store_locale]
    write_json(directory / SHARED_FILE, exported_shared(shared_source), SHARED_COMMENT)
    print(f"  {SHARED_FILE}: {json.dumps(exported_shared(shared_source), ensure_ascii=False)}")
    for target in targets:
        body = exported_language(values[target.store_locale])
        write_json(directory / f"{target.language}.json", body, LANGUAGE_COMMENT)
        print(f"  {target.language}.json（{target.store_locale}）:")
        for line in json.dumps(body, ensure_ascii=False, indent=2).splitlines():
            print(f"    {line}")
    if review_notes.get(first):
        (directory / REVIEW_NOTES_FILE).write_text(review_notes[first] + "\n", encoding="utf-8")
        print(f"  {REVIEW_NOTES_FILE}: {len(review_notes[first])} 字")
    elif (directory / REVIEW_NOTES_FILE).is_file():
        # 消すと次の upload で App Store Connect 側の値を残す扱いになり、意図が変わるので手元のファイルは触らない
        print(f"  {REVIEW_NOTES_FILE}: App Store Connect 側が空のため書き出しません。"
              "手元のファイルは残っているので、次の upload でその内容が反映されます")
    print(f"書き出しました: {directory}（{first} の現在値）")
    return 0


# MARK: - main

def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--metadata-dir", type=Path, default=METADATA_DIR, help="<ここ>/<言語>.json を読む")
    parser.add_argument("--languages", help="対象の言語（カンマ区切り）。省略すると全言語")
    parser.add_argument("--platform", choices=("ios", "macos", "both"), default="both",
                        help="反映先のプラットフォーム。既定は both（iOS と macOS の両バージョン）")
    parser.add_argument("--bundle-id", help="省略すると project.pbxproj から読む")
    parser.add_argument("--app-version", help="反映先のバージョン。省略すると編集できるバージョンを自動で選ぶ")
    parser.add_argument("--key-id", default=os.environ.get("APP_STORE_CONNECT_KEY_ID"))
    parser.add_argument("--issuer-id", default=os.environ.get("APP_STORE_CONNECT_ISSUER_ID"))
    parser.add_argument(
        "--private-key",
        type=Path,
        default=os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY_PATH"),
        help="App Store Connect API Key の .p8",
    )
    parser.add_argument(
        "--missing-locales",
        choices=("fail", "skip", "create"),
        default="fail",
        help="App Store Connect にその言語が無いときの扱い。"
             "fail: 止める（既定） / skip: 飛ばす / create: その言語を追加してから反映する",
    )
    parser.add_argument("--check", action="store_true",
                        help="App Store Connect につながず、手元のファイルの欠損と文字数だけ見る")
    parser.add_argument("--dry-run", action="store_true", help="何も書き換えず、現在値との差分だけ出す")
    parser.add_argument("--export", action="store_true",
                        help="App Store Connect の現在値を AppStore/metadata の JSON に書き出す（反映はしない）")
    args = parser.parse_args()

    targets = languages(parse_list(args.languages))
    target_platforms = platforms(args.platform)

    entries: list[tuple[Language, dict[str, str]]] = []
    review_notes: str | None = None
    if not args.export:
        shared, problems = load_shared(args.metadata_dir)
        review_notes, issues = load_review_notes(args.metadata_dir)
        problems.extend(issues)
        for target in targets:
            attributes, issues = load(args.metadata_dir, target, shared)
            problems.extend(issues)
            if attributes:
                entries.append((target, attributes))
        if problems:
            raise SystemExit("\n".join(problems))

    if args.check:
        for target, attributes in entries:
            counts = " / ".join(
                f"{field} {len(attributes[field])} 字" for field in LIMITS if field in attributes
            )
            print(f"  {target.language}: {counts}")
        if review_notes is not None:
            print(f"  審査メモ: {len(review_notes)} 字")
        print(f"問題なし: {len(entries)} 言語")
        return 0

    missing_key = [
        name for name, value in
        [("--key-id", args.key_id), ("--issuer-id", args.issuer_id), ("--private-key", args.private_key)]
        if not value
    ]
    if missing_key:
        raise SystemExit(f"認証情報が足りません: {', '.join(missing_key)}")

    from app_store_connect import AppStoreConnect

    # export は読むだけなので、何も書き込まない dry_run として振る舞わせる
    client = AppStoreConnect(
        args.key_id, args.issuer_id, Path(args.private_key).read_text(), dry_run=args.dry_run or args.export
    )

    app = client.find_app(args.bundle_id or bundle_id())
    if args.dry_run:
        print("--dry-run: App Store Connect には何も書き込みません")

    # platform ごとにバージョンは別物なので、片方に編集できるバージョンが無くても
    # もう片方は進める。失敗は最後にまとめて非ゼロで返す
    failures: list[str] = []
    exported: dict[str, dict[str, dict]] = {}
    exported_notes: dict[str, str] = {}
    skipped: list[str] = []
    applied = 0
    for platform in target_platforms:
        try:
            version = client.find_version(app["id"], args.app_version, platform)
        except SystemExit as error:
            print(f"[{platform}] {error}")
            failures.append(f"{platform}: {error}")
            continue
        version_string = version["attributes"]["versionString"]
        print(f"対象: {app['attributes']['name']} {version_string} "
              f"({version['attributes']['appStoreState']}) / {platform}")

        available = client.localization_entries(version["id"])
        if args.export:
            exported[platform] = {locale: entry["attributes"] for locale, entry in available.items()}
            for locale in available:
                print(f"  {locale}: 現在値を読みました")
            detail = client.review_detail(version["id"])
            exported_notes[platform] = ((detail or {}).get("attributes", {}).get("notes") or "").strip()
            print(f"  審査メモ: {'現在値を読みました' if exported_notes[platform] else '空です'}")
            continue

        # スクリーンショットのときと同じく、書き込む前に全言語ぶんの前提を確かめる
        plan: list[tuple[Language, dict[str, str], dict | None]] = []
        missing_locales: list[str] = []
        for target, attributes in entries:
            localization = available.get(target.store_locale)
            if localization is None:
                if args.missing_locales == "create":
                    plan.append((target, attributes, None))
                elif args.missing_locales == "skip":
                    print(f"  飛ばす — {target.language}: {target.store_locale} が {version_string} にありません")
                    skipped.append(f"{platform} {target.language}")
                else:
                    missing_locales.append(f"{target.language} → {target.store_locale}")
                continue
            plan.append((target, attributes, localization))

        if missing_locales:
            message = (
                f"App Store Connect の {version_string}（{platform}）に無い言語: {', '.join(missing_locales)}。"
                "App Store Connect でこれらの言語を追加してから実行するか、"
                "--missing-locales create（追加してから反映）か "
                "--missing-locales skip（飛ばす）を付けてください。"
            )
            print(f"  {message}")
            failures.append(f"{platform}: {message}")
            continue

        for target, attributes, localization in plan:
            label = f"{target.language} → {target.store_locale}"
            if localization is None:
                client.create_localization(version["id"], target.store_locale, attributes)
                print(f"  {label}: {'言語を追加して書き込む予定' if args.dry_run else '言語を追加して書き込み'}")
                for line in describe_changes({}, attributes):
                    print(line)
                applied += 1
                continue

            changes = describe_changes(localization["attributes"], attributes)
            if not changes:
                print(f"  {label}: 変更なし")
                applied += 1
                continue
            print(f"  {label}: {'書き込む予定' if args.dry_run else '書き込み'}")
            for line in changes:
                print(line)
            if not args.dry_run:
                client.patch(
                    f"/v1/appStoreVersionLocalizations/{localization['id']}",
                    {
                        "data": {
                            "type": "appStoreVersionLocalizations",
                            "id": localization["id"],
                            "attributes": attributes,
                        }
                    },
                )
            applied += 1

        if review_notes is not None:
            apply_review_notes(client, version["id"], review_notes, args.dry_run)

    if args.export:
        if failures and len(target_platforms) > 1:
            # 片方しか読めていないと platform 間の食い違いを確かめられない。
            # 比べていない値を「both の現在値」として取り込ませないよう、書き出さずに止める
            print("一部の platform の現在値を読めなかったため、食い違いを確かめられません。書き出しません。"
                  "--platform で片方を選んでください。")
            status = 1
        else:
            status = export(args.metadata_dir, targets, exported, exported_notes)
    else:
        print(f"完了: {applied} 件（platform × 言語）")
        if skipped:
            print(f"飛ばした言語: {', '.join(skipped)}")
        status = 0

    if failures:
        print("失敗した platform があります:")
        for failure in failures:
            print(f"  {failure}")
        return 1
    return status


if __name__ == "__main__":
    sys.exit(main())
