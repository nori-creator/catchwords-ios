#!/usr/bin/env python3
"""TestFlight に届いたクラッシュの記録と、Apple が集めた「固まり」の記録を App Store Connect API で読む（読むだけ）。

アプリが落ちたあと iPhone に出る「クラッシュしました。詳細情報をデベロッパと共有しますか?」で「共有」を押すと、
その時の記録（どの行で止まったか）が App Store Connect に届く。それを読み、OUT_DIR に書く:
  crashes.md        届いたクラッシュの一覧と、それぞれの記録の本文（新しい順）
  hangs.md          ビルドごとの「固まり」（HANGS）と起動の記録（Apple が日ごとにまとめるもの。届くのは翌日以降）

公開リポジトリなので、テスターのメールアドレス・名前・コメントは出さない（コメントは長さだけ）。記録の本文からも
メールアドレスの形の文字列と CrashReporter Key は消す。

使い方（環境変数 ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_PATH が必要）:
  asc_crash_reports.py BUNDLE_ID OUT_DIR

読めなかったところは理由を書いて先へ進み、0 で終わる。
"""
import json
import os
import re
import sys
import urllib.error
import urllib.parse

from asc_dev_certs import API, request

EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[\w.-]+")
# Attributes safe to show in a public repository (no email, name or free text).
SHOWN = ["createdDate", "deviceModel", "deviceFamily", "osVersion", "appPlatform", "architecture", "locale",
         "appUptimeInMilliseconds", "diskBytesAvailable", "batteryPercentage", "screenWidthInPoints",
         "screenHeightInPoints", "buildBundleId"]


def scrub(text: str) -> str:
    text = EMAIL.sub("<email>", text)
    return "\n".join(line for line in text.splitlines() if not line.startswith("CrashReporter Key"))


def get(url: str):
    try:
        return request("GET", url), None
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")[:400]
        return None, f"HTTP {e.code}: {body}"
    except Exception as e:  # network, key
        return None, f"{type(e).__name__}: {e}"


def app_id(bundle_id: str) -> str | None:
    data, err = get(f"{API}/apps?filter[bundleId]={urllib.parse.quote(bundle_id)}&limit=1")
    if err:
        print(f"::warning::アプリを読めませんでした（{err}）", file=sys.stderr)
        return None
    apps = data.get("data", [])
    return apps[0]["id"] if apps else None


def build_versions(app: str) -> dict[str, str]:
    """build id → "1.0.2 (1234)"."""
    out = {}
    data, err = get(f"{API}/builds?filter[app]={app}&sort=-uploadedDate&limit=30&include=preReleaseVersion"
                    "&fields[builds]=version,uploadedDate,preReleaseVersion&fields[preReleaseVersions]=version")
    if err:
        return out
    pre = {i["id"]: i["attributes"].get("version") for i in data.get("included", []) if i["type"] == "preReleaseVersions"}
    for b in data.get("data", []):
        rel = (b.get("relationships", {}).get("preReleaseVersion", {}).get("data") or {}).get("id")
        out[b["id"]] = f"{pre.get(rel, '?')} ({b['attributes'].get('version')})"
    return out


def crashes(app: str, builds: dict[str, str]) -> str:
    lines = ["# TestFlight に届いたクラッシュ（新しい順）", ""]
    data, err = get(f"{API}/apps/{app}/betaFeedbackCrashSubmissions?sort=-createdDate&limit=10&include=build")
    if err:
        return "\n".join(lines + [f"読めませんでした: {err}"])
    items = data.get("data", [])
    if not items:
        return "\n".join(lines + ["まだ 1 件も届いていません（クラッシュの画面で「共有」を押すと届きます）。"])
    for n, item in enumerate(items, 1):
        a = item.get("attributes", {})
        build_id = (item.get("relationships", {}).get("build", {}).get("data") or {}).get("id")
        lines.append(f"## {n}. {a.get('createdDate')}  ビルド {builds.get(build_id, build_id)}")
        for k in SHOWN[1:]:
            if a.get(k) is not None:
                lines.append(f"- {k}: {a[k]}")
        if a.get("comment"):
            lines.append(f"- comment: （{len(a['comment'])} 文字。公開しない）")
        log, lerr = get(f"{API}/betaFeedbackCrashSubmissions/{item['id']}/crashLog")
        if lerr:
            lines += ["", f"記録を読めませんでした: {lerr}", ""]
            continue
        text = ((log or {}).get("data") or {}).get("attributes", {}).get("logText") or ""
        lines += ["", "```", scrub(text).strip()[:60000], "```", ""]
    return "\n".join(lines)


def hangs(builds: dict[str, str]) -> str:
    lines = ["# Apple が集めた固まり（HANGS）・起動の記録", "",
             "テスターの iPhone が「解析データを共有」にしている時だけ、日ごとにまとめて届く。", ""]
    for build_id, name in list(builds.items())[:6]:
        data, err = get(f"{API}/builds/{build_id}/diagnosticSignatures?limit=20")
        if err:
            lines.append(f"## ビルド {name}: 読めませんでした（{err}）")
            continue
        sigs = data.get("data", [])
        lines.append(f"## ビルド {name}: {len(sigs)} 件")
        for s in sigs:
            a = s.get("attributes", {})
            lines.append(f"- {a.get('diagnosticType')} weight={a.get('weight')} {a.get('signature')}")
            logs, lerr = get(f"{API}/diagnosticSignatures/{s['id']}/logs?limit=3")
            if lerr:
                lines.append(f"  記録を読めませんでした: {lerr}")
                continue
            lines += ["", "```json", scrub(json.dumps(logs, ensure_ascii=False, indent=1))[:40000], "```", ""]
    return "\n".join(lines)


def main():
    bundle_id, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    app = app_id(bundle_id)
    if not app:
        open(os.path.join(out, "crashes.md"), "w").write("アプリが見つかりませんでした。\n")
        return 0
    builds = build_versions(app)
    open(os.path.join(out, "crashes.md"), "w").write(crashes(app, builds) + "\n")
    open(os.path.join(out, "hangs.md"), "w").write(hangs(builds) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
