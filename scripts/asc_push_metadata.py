#!/usr/bin/env python3
"""ios/metadata の文言を App Store Connect に入れる（説明文・キーワード・サブタイトルなど。審査には出さない）。

入れるもの（このリポジトリの `ios/metadata`）:
  app-info/<言語>.json            name / subtitle / privacyPolicyUrl
  version/<版>/<言語>.json         description / keywords / promotionalText / supportUrl / marketingUrl
  docs/app-store/review-notes.en.txt   App Review Information の Notes（--notes を付けた時だけ）

触らないもの: 審査用アカウント（メール・パスワード）、連絡先、ビルド、価格、配信国、審査への提出。
App Store Connect にあって `ios/metadata` に無い言語は、一覧に出すだけ（消さない。消すのは App Store Connect の画面で）。

既定は「試すだけ」（何が変わるかを出すだけ）。--apply を付けた時だけ書き込む。
このリポジトリは公開なので、App Store Connect に今入っている審査メモの本文は出さない（長さだけ）。

使い方（環境変数 ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH が必要）:
  asc_push_metadata.py BUNDLE_ID METADATA_DIR VERSION [--notes FILE] [--apply]
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

from asc_dev_certs import API, token

LIMITS = {"name": 30, "subtitle": 30, "promotionalText": 170, "description": 4000, "whatsNew": 4000}
BYTE_LIMITS = {"keywords": 100, "notes": 4000}
INFO_FIELDS = ("name", "subtitle", "privacyPolicyUrl")
VERSION_FIELDS = ("description", "keywords", "promotionalText", "whatsNew", "supportUrl", "marketingUrl")
# Versions whose text can still be edited (the first version has never been on sale).
EDITABLE = {"PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED",
            "INVALID_BINARY"}


def call(method: str, url: str, body: dict | None = None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, method=method, data=data, headers={
        "Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as res:
        raw = res.read()
        return json.loads(raw) if raw else None


def get_all(url: str):
    out = []
    while url:
        d = call("GET", url)
        out += d.get("data", [])
        url = d.get("links", {}).get("next")
    return out


def error_detail(e: urllib.error.HTTPError) -> str:
    try:
        errs = json.loads(e.read().decode()).get("errors", [])
        return "; ".join(f"{x.get('title', '')}: {x.get('detail', '')}" for x in errs)[:500]
    except Exception:
        return str(e)


def check_limits(fields: dict, where: str) -> list[str]:
    bad = []
    for k, n in LIMITS.items():
        if k in fields and fields[k] is not None and len(fields[k]) > n:
            bad.append(f"{where} {k}: {len(fields[k])} 字（上限 {n}）")
    for k, n in BYTE_LIMITS.items():
        if k in fields and fields[k] is not None and len(fields[k].encode()) > n:
            bad.append(f"{where} {k}: {len(fields[k].encode())} バイト（上限 {n}）")
    return bad


def describe(old, new) -> str:
    o = old or ""
    return f"{len(o)} → {len(new)} 字"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    apply = "--apply" in sys.argv
    notes_path = None
    if "--notes" in sys.argv:
        notes_path = sys.argv[sys.argv.index("--notes") + 1]
        args = [a for a in args if a != notes_path]
    bundle_id, meta_dir, version = args[0], args[1], args[2]
    print(f"# App Store Connect の文言 {'を書き込む' if apply else 'の変更点（試すだけ。書き込まない）'}\n")

    want_info = {f[:-5]: json.load(open(os.path.join(meta_dir, "app-info", f), encoding="utf-8"))
                 for f in sorted(os.listdir(os.path.join(meta_dir, "app-info"))) if f.endswith(".json")}
    vdir = os.path.join(meta_dir, "version", version)
    want_ver = {f[:-5]: json.load(open(os.path.join(vdir, f), encoding="utf-8"))
                for f in sorted(os.listdir(vdir)) if f.endswith(".json")}
    notes = open(notes_path, encoding="utf-8").read().strip() if notes_path else None

    problems = []
    for loc, d in want_info.items():
        problems += check_limits(d, f"app-info/{loc}")
    for loc, d in want_ver.items():
        problems += check_limits(d, f"version/{version}/{loc}")
    if notes is not None:
        problems += check_limits({"notes": notes}, "review notes")
    if problems:
        print("長さの上限を超えています。直してからもう一度:\n" + "\n".join(f"- {p}" for p in problems))
        return 1

    app = call("GET", f"{API}/apps?filter[bundleId]={urllib.parse.quote(bundle_id)}&limit=1")["data"][0]
    changes = 0
    failures = 0

    def patch(kind: str, rid: str, attrs: dict, label: str):
        nonlocal failures
        if not apply:
            return
        try:
            call("PATCH", f"{API}/{kind}/{rid}", {"data": {"type": kind, "id": rid, "attributes": attrs}})
            print(f"  - 書き込みました: {label}")
        except urllib.error.HTTPError as e:
            failures += 1
            print(f"  - **書き込めませんでした**: {label}（HTTP {e.code} {error_detail(e)}）")

    def report_extra(have: dict, want: dict):
        """Languages App Store Connect has but ios/metadata does not: listed only, never removed here."""
        for loc in sorted(set(have) - set(want)):
            print(f"- {loc}: `ios/metadata` に無い言語。ここでは消さない（消すなら App Store Connect の画面で）")

    def create(kind: str, attrs: dict, rel_name: str, rel_type: str, rel_id: str, label: str):
        nonlocal failures
        if not apply:
            return
        try:
            call("POST", f"{API}/{kind}", {"data": {"type": kind, "attributes": attrs, "relationships": {
                rel_name: {"data": {"type": rel_type, "id": rel_id}}}}})
            print(f"  - 作りました: {label}")
        except urllib.error.HTTPError as e:
            failures += 1
            print(f"  - **作れませんでした**: {label}（HTTP {e.code} {error_detail(e)}）")

    # App information (name, subtitle, privacy policy URL): the editable appInfo.
    infos = get_all(f"{API}/apps/{app['id']}/appInfos")
    info = next((i for i in infos if (i["attributes"].get("state") or i["attributes"].get("appStoreState"))
                 not in ("READY_FOR_DISTRIBUTION", "READY_FOR_SALE")), infos[0] if infos else None)
    print("## App 情報（名前・サブタイトル・プライバシーポリシー）")
    have = {l["attributes"]["locale"]: l for l in get_all(f"{API}/appInfos/{info['id']}/appInfoLocalizations")}
    for loc, d in want_info.items():
        attrs = {k: d[k] for k in INFO_FIELDS if k in d}
        cur = have.get(loc)
        if not cur:
            changes += 1
            print(f"- {loc}: まだ無いので作る（{', '.join(attrs)}）")
            create("appInfoLocalizations", {"locale": loc, **attrs}, "appInfo", "appInfos", info["id"], f"App 情報 {loc}")
            continue
        diff = {k: v for k, v in attrs.items() if (cur["attributes"].get(k) or "") != v}
        if not diff:
            print(f"- {loc}: 同じ")
            continue
        changes += 1
        print(f"- {loc}: " + "、".join(f"{k}「{cur['attributes'].get(k) or ''}」→「{v}」" for k, v in diff.items()))
        patch("appInfoLocalizations", cur["id"], diff, f"App 情報 {loc}")
    report_extra(have, want_info)

    # The version's text.
    versions = get_all(f"{API}/apps/{app['id']}/appStoreVersions?filter[platform]=IOS&filter[versionString]={version}")
    if not versions:
        # A new version (e.g. 1.0.1 after 1.0.0 went on sale) is created here, like the "+" in the sidebar.
        # Its text is written on the next run, once App Store Connect has the version.
        changes += 1
        if not apply:
            print(f"\n版 {version} が App Store Connect にまだ無い。apply をオンにすると作る（説明文はその次の実行で入る）")
            print(f"\n変わる所: {changes} か所（試すだけ。書き込むには apply をオンにして実行）")
            return 0
        try:
            call("POST", f"{API}/appStoreVersions", {"data": {"type": "appStoreVersions", "attributes": {
                "platform": "IOS", "versionString": version}, "relationships": {
                "app": {"data": {"type": "apps", "id": app["id"]}}}}})
            print(f"\n版 {version} を App Store Connect に作りました。説明文はもう一度実行すると入ります。")
            return 0
        except urllib.error.HTTPError as e:
            print(f"\n版 {version} を作れませんでした（HTTP {e.code} {error_detail(e)}）。前の版が審査中・審査待ちの間は作れません")
            return 1
    ver = versions[0]
    state = ver["attributes"].get("appVersionState") or ver["attributes"].get("appStoreState")
    print(f"\n## 版 {version}（状態 {state}）の説明文など")
    if state not in EDITABLE and ver["attributes"].get("appStoreState") not in EDITABLE:
        print(f"この状態（{state}）では書き換えられないので、ここで止めます。")
        return 1
    have = {l["attributes"]["locale"]: l for l in get_all(f"{API}/appStoreVersions/{ver['id']}/appStoreVersionLocalizations")}
    for loc, d in want_ver.items():
        attrs = {k: d[k] for k in VERSION_FIELDS if k in d}
        cur = have.get(loc)
        if not cur:
            changes += 1
            print(f"- {loc}: まだ無いので作る（{', '.join(attrs)}）")
            create("appStoreVersionLocalizations", {"locale": loc, **attrs}, "appStoreVersion", "appStoreVersions",
                   ver["id"], f"説明文 {loc}")
            continue
        diff = {k: v for k, v in attrs.items() if (cur["attributes"].get(k) or "") != v}
        if not diff:
            print(f"- {loc}: 同じ")
            continue
        changes += 1
        parts = []
        for k, v in diff.items():
            old = cur["attributes"].get(k)
            parts.append(f"{k} {describe(old, v)}" if k in ("description", "promotionalText")
                         else f"{k}「{old or ''}」→「{v}」")
        print(f"- {loc}: " + "、".join(parts))
        patch("appStoreVersionLocalizations", cur["id"], diff, f"説明文 {loc}")
    report_extra(have, want_ver)

    # Review notes only (never the demo account or the contact).
    if notes is not None:
        print("\n## 審査メモ（App Review Information の Notes）")
        d = call("GET", f"{API}/appStoreVersions/{ver['id']}/appStoreReviewDetail").get("data")
        if not d:
            print("- 審査の情報がまだ無いので入れられません（App Store Connect の画面で連絡先とサインイン情報を先に入れる）")
        else:
            old = d["attributes"].get("notes") or ""
            if old.strip() == notes:
                print("- 同じ")
            else:
                changes += 1
                print(f"- 今の Notes {len(old.encode())} バイト → 新しい Notes {len(notes.encode())} バイト"
                      f"（`{notes_path}` の内容。今の本文は公開しないため出さない）")
                patch("appStoreReviewDetails", d["id"], {"notes": notes}, "審査メモ")

    print(f"\n変わる所: {changes} か所" + ("" if apply else "（試すだけ。書き込むには apply をオンにして実行）"))
    if failures:
        print(f"書き込めなかった所: {failures} か所")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
