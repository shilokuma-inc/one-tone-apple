#!/usr/bin/env python3
"""プロダクトページのヘッダーと検索結果のクリエイティブアセットを App Store Connect に反映する。

iOS 27 / iPadOS 27 から、スクリーンショットとは別に「クリエイティブアセット」を App Store に載せられる
（https://developer.apple.com/app-store/asset-best-practices/）。置き場所・寸法・配置する platform は
`AppStore/creative_assets.json`、画像は `AppStore/creative/<言語>/<ファイル名>`。

    python3 Tools/upload_creative_assets.py --app-version 1.3.0  # 全言語を 1.3.0 に反映する
    python3 Tools/upload_creative_assets.py --dry-run     # 何も書き換えず、やることだけ出す
    python3 Tools/upload_creative_assets.py --ref-data    # 置き場所と画像の仕様を App Store Connect から読んで出す
    python3 Tools/upload_creative_assets.py --check       # App Store Connect につながず、手元の画像だけ検査する

App Asset Library の API で、言語ごとに次の順で反映する。

1. 画像を Asset Library に上げ（予約 → 転送 → 確定）、Apple 側の処理が終わるのを待つ
2. 処理で決まった画像の仕様（specId）を受け付ける置き場所のグループを、参照データから探す
3. その言語の同じ置き場所にある既存の配置を外し、新しい画像を配置する

置き場所のグループや仕様の ID は、Apple が機種を足すたびに増えるので決め打ちせず、
毎回参照データ（appAssetLibraryRefData）から引く。

このアプリは iOS と macOS を同じ Bundle ID で配信しているが、App Store Connect のバージョンは
platform ごとに別物。クリエイティブアセットは iOS / iPadOS の App Store にだけ出るので、
`creative_assets.json` の platforms（IOS）のバージョンにだけ配置する。

触るのは **編集できる状態のバージョンだけ**。配置したアセットは、そのバージョンと一緒に審査に出る。
そのため反映（upload）では `--app-version` を必ず指定する（自動で選ぶと、審査に出す直前の別のバージョンに入りうる）。
外した配置の画像は Asset Library に残る。

認証は App Store Connect API Key（.p8）。次の環境変数でも渡せる。

    APP_STORE_CONNECT_KEY_ID / APP_STORE_CONNECT_ISSUER_ID / APP_STORE_CONNECT_PRIVATE_KEY_PATH

PyJWT が要る（--check では不要）: `python3 -m pip install pyjwt cryptography`
"""

from __future__ import annotations

import argparse
import os
import struct
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from app_store_config import (
    ROOT,
    CreativeAsset,
    Language,
    bundle_id,
    creative_assets,
    creative_platforms,
    languages,
    parse_list,
)

ASSETS_DIR = ROOT / "AppStore" / "creative"

#: App Store のバージョンに載せるときの機能名（参照データの features）
FEATURE = "APP_STORE_VERSIONS"

#: Asset Library に上げる画像の種類。ヘッダーと検索結果はこれ
CATEGORY = "CREATIVE_ASSETS"

#: Asset Library に上げた画像の、Apple 側の処理が終わるのを待つ上限（秒）
PROCESSING_TIMEOUT = 600

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


# MARK: - 手元の画像


def png_info(path: Path) -> tuple[int, int, bool]:
    """PNG の幅・高さと、透過を持つか（アルファのある色の型、または tRNS がある）を返す。"""
    data = path.read_bytes()
    if not data.startswith(PNG_SIGNATURE):
        raise ValueError("PNG ではありません")
    offset = len(PNG_SIGNATURE)
    width = height = color_type = None
    has_transparency = False
    while offset + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[offset:offset + 8])
        body = data[offset + 8:offset + 8 + length]
        if kind == b"IHDR":
            width, height = struct.unpack(">II", body[:8])
            color_type = body[9]
        elif kind == b"tRNS":
            has_transparency = True
        elif kind == b"IEND":
            break
        offset += 12 + length
    if width is None:
        raise ValueError("IHDR がありません")
    # 4: グレー + アルファ / 6: RGB + アルファ
    return width, height, has_transparency or color_type in (4, 6)


def image_problems(targets: list[Language], assets: list[CreativeAsset]) -> list[str]:
    """全言語・全置き場所の画像が、決めた寸法の透過なしの PNG で揃っているか。"""
    problems = []
    for target in targets:
        for asset in assets:
            path = ASSETS_DIR / target.language / asset.file
            relative = path.relative_to(ROOT)
            if not path.is_file():
                problems.append(f"{relative} がありません（Tools/render_creative_assets.sh で書き出してください）")
                continue
            try:
                width, height, has_alpha = png_info(path)
            except ValueError as error:
                problems.append(f"{relative}: {error}")
                continue
            if (width, height) != (asset.width, asset.height):
                problems.append(f"{relative} の寸法が {asset.width}x{asset.height} ではありません（{width}x{height}）")
            if has_alpha:
                problems.append(f"{relative} に透過があります（App Store Connect は受け付けません）")
    return problems


# MARK: - 参照データ


class RefData:
    """App Asset Library の参照データ（置き場所・グループ・画像の仕様）。"""

    def __init__(self, attributes: dict):
        self.raw = attributes

    def placement_type(self, name: str) -> dict:
        for entry in self.raw.get("placementTypes", []):
            if entry.get("placementTypeId") == name:
                return entry
        raise SystemExit(f"参照データに置き場所 {name} がありません")

    def groups_for_spec(self, placement_type: str, spec_id: str) -> list[str]:
        """その置き場所で、この仕様の画像を受け付けるグループ。"""
        return [
            mapping["placementGroupId"]
            for mapping in self.placement_type(placement_type).get("specMappings", [])
            if spec_id in (mapping.get("specs") or [])
        ]

    def group_platform(self, group: str) -> str | None:
        """グループが出る App Store（IPHONE_APP_STORE など。DEFAULT_PROFILE は ANY）。"""
        for entry in self.raw.get("placementProfileGroups", []):
            if entry.get("placementProfileGroupId") == group:
                return entry.get("platform")
        return None

    def group_limit(self, placement_type: str, group: str) -> int | None:
        for feature in self.raw.get("features", []):
            if feature.get("featureId") != FEATURE:
                continue
            for policy in feature.get("placementPolicies", []):
                if policy.get("placementType") != placement_type:
                    continue
                for limit in policy.get("groupLimits", []):
                    if group in (limit.get("groupIds") or []):
                        return limit.get("maxCount")
        return None

    def image_spec(self, spec_id: str) -> dict | None:
        for spec in self.raw.get("imageSpecs", []):
            if spec.get("specId") == spec_id:
                return spec
        return None

    def expected_spec(self, placement_type: str, width: int, height: int) -> dict | None:
        """この寸法の画像が、上げたあとの処理で割り当てられるはずの仕様。

        dry-run で配置先のグループを示すのに使う。実際の配置は、処理で決まった specId で選び直す。
        ヘッダーと検索結果の両方に使える universal（16:9）は、寸法が合わないので候補に入らない。
        """
        for mapping in self.placement_type(placement_type).get("specMappings", []):
            for spec_id in mapping.get("specs") or []:
                spec = self.image_spec(spec_id)
                if spec is None:
                    continue
                d = spec.get("dimensions", {})
                if d.get("minWidth", 0) <= width <= d.get("maxWidth", 0) \
                        and d.get("minHeight", 0) <= height <= d.get("maxHeight", 0):
                    return spec
        return None

    def describe(self, placement_types: list[str]) -> str:
        """置き場所ごとの、受け付けるグループ（と、それが出る App Store）と画像の仕様を人が読める形にする。"""
        lines = []
        features = [f.get("featureId") for f in self.raw.get("features", [])]
        lines.append(f"features: {', '.join(str(f) for f in features)}")
        for name in placement_types:
            entry = self.placement_type(name)
            lines.append(f"\n{name}（accepts: {entry.get('acceptsAssetCategories')}）")
            for mapping in entry.get("specMappings", []):
                group = mapping.get("placementGroupId")
                lines.append(
                    f"  group {group}（platform: {self.group_platform(group)} / "
                    f"{FEATURE} の上限: {self.group_limit(name, group)}）"
                )
                for spec_id in mapping.get("specs") or []:
                    spec = self.image_spec(spec_id)
                    if spec is None:
                        lines.append(f"    {spec_id}（動画）")
                        continue
                    d = spec.get("dimensions", {})
                    lines.append(
                        f"    {spec.get('shortName')} {d.get('minWidth')}-{d.get('maxWidth')}x"
                        f"{d.get('minHeight')}-{d.get('maxHeight')} {spec.get('aspectRatio')} "
                        f"{spec.get('fileExtensions')} alpha={spec.get('alphaAllowed')} "
                        f"universal={spec.get('universalAsset')} compatible={spec.get('compatiblePlacementTypes')}"
                    )
        return "\n".join(lines)


# MARK: - Asset Library


class AssetLibrary:
    """App Asset Library への画像の登録と、バージョンの言語ごとの配置。書き込みは `client.dry_run` なら何もしない。"""

    def __init__(self, client, app_id: str):
        self.client = client
        self.library_id = client.get(f"/v1/apps/{app_id}/assetLibrary")["data"]["id"]

    def upload_image(self, path: Path, reference_name: str) -> dict:
        """画像を 1 枚上げ（予約 → 本体の転送 → 確定）、Apple 側の処理が終わった画像を返す。

        返すのは `{"id": …, **attributes}`。処理で決まった画像の仕様が `specId` に入る。
        上げた画像は配置から外しても Asset Library に残る。
        """
        from app_store_connect import transfer

        if self.client.dry_run:
            return {"id": "dry-run"}
        data = path.read_bytes()
        reserved = self.client.post(
            "/v1/appAssetLibraryImages",
            {
                "data": {
                    "type": "appAssetLibraryImages",
                    "attributes": {
                        "fileName": path.name,
                        "fileSize": len(data),
                        "category": CATEGORY,
                        "referenceName": reference_name,
                    },
                    "relationships": {
                        "assetLibrary": {"data": {"type": "appAssetLibraries", "id": self.library_id}}
                    },
                }
            },
        )["data"]
        image_id = reserved["id"]
        transfer(path.name, data, reserved["attributes"]["uploadOperations"])
        self.client.patch(
            f"/v1/appAssetLibraryImages/{image_id}",
            {"data": {"type": "appAssetLibraryImages", "id": image_id, "attributes": {"uploaded": True}}},
        )

        deadline = time.time() + PROCESSING_TIMEOUT
        while True:
            attributes = self.client.get(f"/v1/appAssetLibraryImages/{image_id}")["data"]["attributes"]
            state = attributes.get("state")
            if state == "FAILED":
                raise SystemExit(f"{path.name} の処理に失敗しました: {attributes.get('stateDetails')}")
            if state not in ("AWAITING_UPLOAD", "UPLOAD_COMPLETE"):
                return {"id": image_id, **attributes}
            if time.time() > deadline:
                raise SystemExit(
                    f"{path.name} の処理が {PROCESSING_TIMEOUT} 秒で終わりませんでした（{state}）。"
                    "App Store Connect の画面で状態を確認してください。"
                )
            time.sleep(5)

    def placements(self, localization_id: str, placement_type: str) -> list[dict]:
        """その言語のその置き場所に、いま配置されているもの。"""
        return self.client.get_all(
            f"/v1/appStoreVersionLocalizations/{localization_id}/placements",
            {"filter[placementType]": placement_type, "include": "image"},
        )

    def place(self, localization_id: str, placement_type: str, group: str, image_id: str) -> None:
        if self.client.dry_run:
            return
        self.client.post(
            "/v1/appAssetLibraryPlacements",
            {
                "data": {
                    "type": "appAssetLibraryPlacements",
                    "attributes": {"placementType": placement_type, "placementGroup": group},
                    "relationships": {
                        "image": {"data": {"type": "appAssetLibraryImages", "id": image_id}},
                        "appStoreVersionLocalization": {
                            "data": {"type": "appStoreVersionLocalizations", "id": localization_id}
                        },
                    },
                }
            },
        )

    def remove(self, placement_id: str) -> None:
        """配置を外す。画像そのものは Asset Library に残る。"""
        if self.client.dry_run:
            return
        self.client.delete(f"/v1/appAssetLibraryPlacements/{placement_id}")


def load_ref_data(client) -> RefData:
    """置き場所・グループ・画像の仕様の参照データ（アプリによらない）。"""
    data = client.get("/v1/appAssetLibraryRefData")["data"]
    if isinstance(data, list):
        data = data[0]
    return RefData(data["attributes"])


# MARK: - main


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--bundle-id", help="省略すると project.pbxproj から読む")
    parser.add_argument("--languages", help="対象の言語（カンマ区切り）。省略すると全言語")
    parser.add_argument("--app-version",
                        help="反映先のバージョン（例: 1.3.0）。反映では必須。--dry-run で省略すると編集できるバージョンを自動で選ぶ")
    parser.add_argument("--key-id", default=os.environ.get("APP_STORE_CONNECT_KEY_ID"))
    parser.add_argument("--issuer-id", default=os.environ.get("APP_STORE_CONNECT_ISSUER_ID"))
    parser.add_argument(
        "--private-key",
        type=Path,
        default=os.environ.get("APP_STORE_CONNECT_PRIVATE_KEY_PATH"),
        help="App Store Connect API Key の .p8",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--dry-run", action="store_true", help="何も書き換えず、やることだけ出す")
    mode.add_argument("--ref-data", action="store_true", help="置き場所と画像の仕様を出して終わる")
    mode.add_argument("--check", action="store_true", help="App Store Connect につながず、手元の画像だけ検査する")
    args = parser.parse_args()
    if not (args.dry_run or args.ref_data or args.check) and not args.app_version:
        raise SystemExit(
            "反映では --app-version で反映先のバージョンを指定してください（例: --app-version 1.3.0）。"
            "配置したアセットはそのバージョンと一緒に審査に出るため、自動では選びません。"
        )

    assets = creative_assets()
    target_platforms = creative_platforms()
    targets = languages(parse_list(args.languages))

    # 画像が揃っているかは API を叩く前に確かめる（参照データを見るだけなら画像は要らない）
    problems = image_problems(targets, assets)
    if args.check:
        if problems:
            raise SystemExit("\n".join(problems))
        print(f"OK: {len(targets)} 言語 × {len(assets)} 枚（{', '.join(a.file for a in assets)}）")
        return 0
    if problems and not args.ref_data:
        raise SystemExit("\n".join(problems))

    missing_key = [
        name for name, value in
        [("--key-id", args.key_id), ("--issuer-id", args.issuer_id), ("--private-key", args.private_key)]
        if not value
    ]
    if missing_key:
        raise SystemExit(f"認証情報が足りません: {', '.join(missing_key)}")

    # PyJWT が要るので、--check では読み込まない
    from app_store_connect import AppStoreConnect

    client = AppStoreConnect(
        args.key_id, args.issuer_id, Path(args.private_key).read_text(), dry_run=args.dry_run
    )
    app = client.find_app(args.bundle_id or bundle_id())
    reference = load_ref_data(client)

    if args.ref_data:
        print(reference.describe(sorted({asset.placement_type for asset in assets})))
        return 0

    # 書き込みを始める前に、仕様と全 platform・全言語の前提をまとめて確かめる。
    # 途中で止めると一部の言語だけ差し替わった状態になるので、直すべき点は 1 回で出し切る
    expected = {}
    for asset in assets:
        spec = reference.expected_spec(asset.placement_type, asset.width, asset.height)
        if spec is None:
            problems.append(
                f"{asset.placement_type} に {asset.width}x{asset.height} の画像を受け付ける仕様がありません。"
                "--ref-data で仕様を確かめ、AppStore/creative_assets.json の寸法を直してください。"
            )
        expected[asset.placement_type] = spec

    versions = []
    for platform in target_platforms:
        version = client.find_version(app["id"], args.app_version, platform)
        localizations = client.localizations(version["id"])
        missing = [f"{t.language} → {t.store_locale}" for t in targets if t.store_locale not in localizations]
        if missing:
            problems.append(
                f"App Store Connect の {platform} {version['attributes']['versionString']} に無い言語: "
                f"{', '.join(missing)}\n"
                "Metadata/App Store を missing_locales: create で実行して言語を追加してから反映してください。"
            )
        versions.append((platform, version, localizations))
    if problems:
        raise SystemExit("\n".join(problems))

    for platform, version, _ in versions:
        print(f"対象: {app['attributes']['name']} {version['attributes']['versionString']} "
              f"({version['attributes']['appStoreState']}) / {platform}")
    if args.dry_run:
        print("--dry-run: App Store Connect には何も書き込みません")
    version_label = "/".join(sorted({version["attributes"]["versionString"] for _, version, _ in versions}))

    library = AssetLibrary(client, app["id"])
    for target in targets:
        print(f"  {target.language} → {target.store_locale}")
        for asset in assets:
            path = ASSETS_DIR / target.language / asset.file
            existing = {
                platform: library.placements(localizations[target.store_locale], asset.placement_type)
                for platform, _, localizations in versions
            }

            if args.dry_run:
                spec = expected[asset.placement_type]
                groups = reference.groups_for_spec(asset.placement_type, spec["specId"])
                for platform, _, _ in versions:
                    print(f"    {platform} {asset.placement_type}: {asset.file}（{spec.get('shortName')}）"
                          f"→ {', '.join(groups)} に配置する予定（既存の配置 {len(existing[platform])} 件を外す）")
                continue

            image = library.upload_image(path, f"{asset.reference_name} {target.language} {version_label}")
            spec_id = image.get("specId") or ""
            spec = reference.image_spec(spec_id) or {}
            groups = reference.groups_for_spec(asset.placement_type, spec_id)
            if not groups:
                raise SystemExit(
                    f"{path.name}（{spec.get('shortName') or spec_id}）を受け付ける "
                    f"{asset.placement_type} のグループがありません。--ref-data で仕様を確かめてください。"
                )

            for platform, _, localizations in versions:
                localization_id = localizations[target.store_locale]
                for placement in existing[platform]:
                    library.remove(placement["id"])
                for group in groups:
                    library.place(localization_id, asset.placement_type, group, image["id"])
                print(f"    {platform} {asset.placement_type}: {asset.file}（{spec.get('shortName')}）"
                      f"→ {', '.join(groups)}（既存の配置 {len(existing[platform])} 件を外した）")

    print(f"完了: {version_label} / {len(targets)} 言語 × {len(assets)} 枚")
    return 0


if __name__ == "__main__":
    sys.exit(main())
