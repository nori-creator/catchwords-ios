#!/usr/bin/env python3
"""The promise between the iOS app and the web server (`/api/native-fn`).

Every server function the iOS app calls (`NativeAPI.call("name", …)`) must be
  1. on the web's list of functions iOS may call (`NATIVE_FNS` in src/lib/native-fn.ts), and
  2. still exist in the web code (the file it is loaded from, and its `export const name`).

When the web side deletes or renames one, the iOS button behind it silently does nothing.
This check turns that into a red CI run instead.

The one exception is PENDING_WEB_DEPLOY below: functions the iOS app already calls ahead of a web
patch that is written but not deployed yet, where the iOS side is built to tolerate their absence
(every failure ignored). Only the names listed there are let through, each with the patch that adds
it; any other unknown function still fails. A listed function that the web side has is checked
like every other one (file and export), with a warning to remove the entry.

  python3 scripts/check_native_contract.py                 # against the web's main branch on GitHub
  python3 scripts/check_native_contract.py --web ../web    # against a local checkout
  python3 scripts/check_native_contract.py --ref some-branch
"""
import argparse
import glob
import os
import re
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import l10n_languages  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..", "ios", "CatchWords")
REPO = "nori-creator/Lovable-catch-words-app"

# Called by iOS before the web side has them. Each entry: function → the web patch that adds it.
# The iOS code behind them must treat any failure (unknown function, 400, 404, network) as "no answer".
# Remove an entry as soon as the patch is on the web's main (the check then warns, and checks the
# function fully: the allowance only ever covers a function missing from NATIVE_FNS).
PENDING_WEB_DEPLOY = {
    # The developer's per-use AI with backups and the AI costs (adminSetAiTask / adminGetAiCosts / adminSetAiPrice,
    # Views/AdminAiSettingsView.swift, Views/AdminAiCostCard.swift) are on the web's main now (PR #179). Until the web is
    # published they answer 404: the settings screen keeps the per-feature list and the cost card says so.
    # recordAiConsent / getAiConsent (AI consent, docs/web-changes/ 0003) are on the web now.
    # Add an entry here as "name": "where the web patch is" when iOS calls a function ahead of its deploy.
    # storeAppleAuthCode (Sign in with Apple revocation, audit R7-03) is on the web's main now.
    # The developer "AI settings" (admin*, docs/admin-ai-api.md) are on the web's main now (PR #168).
    # Speed and accuracy by model, the fixed-photo test and the candidate rank log are on the web's main now
    # (PR #176).
    # The developer's users and metrics (adminListUsers … adminGetBetaMetrics, Services/AdminAnalytics.swift) are on
    # the web's main now (PR #178). Until the web is published they answer 404 and the screens say so.
    # The learners' error reports (adminListEntryReports / adminSetEntryReportStatus, Views/Admin/AdminReportsView.swift)
    # are on the web's main now (PR #187). Until the web is published they answer 404 and the screen says so.
}


# iOS display languages the web cannot write explanations in yet, each with the web patch that adds them.
# The iOS app works without them (explanations come back in Japanese until the patch is published), so they
# are let through with a warning. Remove an entry as soon as the web's main has the language.
PENDING_WEB_LANGUAGES = {
    "es": "nori-creator/Lovable-catch-words-app#190",
    "ko": "nori-creator/Lovable-catch-words-app#190",
    "vi": "nori-creator/Lovable-catch-words-app#190",
}
# The web's explanation languages before src/lib/explain-languages.ts existed.
WEB_LANGUAGES_BEFORE_REGISTRY = {"ja", "en", "zh-TW"}


def check_languages(read, problems, pending):
    """Every iOS display language (ios/Localization/languages.json) is one the web server writes explanations in
    (src/lib/explain-languages.ts), in the same order — iOS picks the explanation row's l1 by that order."""
    ios = [l["code"] for l in l10n_languages.load()["languages"]]
    src = read("src/lib/explain-languages.ts")
    if src is None:
        web = [c for c in ios if c in WEB_LANGUAGES_BEFORE_REGISTRY]
    else:
        block = src[src.find("EXPLAIN_LANGUAGES"):]
        web = re.findall(r'^\s*code:\s*(?:"([\w-]+)"|CHINESE_EXPLANATION_LANGUAGE)', block, re.M)
        web = [c or "zh-TW" for c in web]
    for code in sorted(PENDING_WEB_LANGUAGES):
        if code in web:
            print(f"::warning::display language {code} is on the web now: remove it from PENDING_WEB_LANGUAGES "
                  "(scripts/check_native_contract.py)")
    for code in ios:
        if code in web:
            continue
        if code in PENDING_WEB_LANGUAGES:
            pending.append(f"display language {code} (awaiting {PENDING_WEB_LANGUAGES[code]})")
        else:
            problems.append(f"display language {code}: the web server does not write explanations in it "
                            "(src/lib/explain-languages.ts — docs/adding-a-display-language.md step 4)")
    shared = [c for c in web if c in ios]
    if shared != [c for c in ios if c in web]:
        problems.append(f"display languages in another order than the web's explanation languages ({', '.join(web)}): "
                        "the explanation rows iOS looks for (l1) would not be the ones the server writes")


def ios_calls():
    calls = {}
    for path in sorted(glob.glob(os.path.join(ROOT, "**", "*.swift"), recursive=True)):
        src = open(path, encoding="utf-8").read()
        for m in re.finditer(r'NativeAPI\.call\(\s*"(\w+)"', src):
            line = src.count("\n", 0, m.start()) + 1
            calls.setdefault(m.group(1), []).append(f"{os.path.relpath(path, ROOT)}:{line}")
        # A call whose function name is not written out cannot be checked — keep it that way.
        for m in re.finditer(r"NativeAPI\.call\(\s*[^\s\"]", src):
            line = src.count("\n", 0, m.start()) + 1
            print(f"::error file=ios/CatchWords/{os.path.relpath(path, ROOT)},line={line}::"
                  "NativeAPI.call needs the function name written as a \"string\" so it can be checked")
            calls.setdefault("<dynamic>", []).append(f"{os.path.relpath(path, ROOT)}:{line}")
    return calls


def reader(web, ref):
    if web:
        def read(rel):
            p = os.path.join(web, rel)
            return open(p, encoding="utf-8").read() if os.path.exists(p) else None
    else:
        def read(rel):
            url = f"https://raw.githubusercontent.com/{REPO}/{ref}/{rel}"
            try:
                with urllib.request.urlopen(url, timeout=30) as r:
                    return r.read().decode("utf-8")
            except urllib.error.HTTPError as e:
                if e.code == 404:
                    return None
                raise
    return read


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--web", help="local checkout of the web repository")
    ap.add_argument("--ref", default="main", help="web branch to check against (default: main)")
    args = ap.parse_args()
    read = reader(args.web, args.ref)

    nf = read("src/lib/native-fn.ts")
    if nf is None:
        print("::error::src/lib/native-fn.ts not found in the web repository")
        return 1
    modules = dict(re.findall(r'const (\w+) = \(\) => import\("\./([\w.\-]+)"\)', nf))
    listed = {name: (mod, export) for name, mod, export in
              re.findall(r'^\s+(\w+): from\((\w+), "(\w+)"\)', nf, re.M)}

    calls = ios_calls()
    problems = []
    if "<dynamic>" in calls:
        problems.append("a NativeAPI.call without a written function name")
    cache = {}
    pending = []
    for name in sorted(PENDING_WEB_DEPLOY):
        if name not in calls:
            print(f"::warning::{name} is in PENDING_WEB_DEPLOY but iOS no longer calls it: remove the entry "
                  "(scripts/check_native_contract.py)")
        elif name in listed:
            print(f"::warning::{name} is on the web's NATIVE_FNS list now: remove it from PENDING_WEB_DEPLOY "
                  "(scripts/check_native_contract.py)")
    for name, where in sorted(calls.items()):
        if name == "<dynamic>":
            continue
        if name not in listed and name in PENDING_WEB_DEPLOY:
            pending.append(f"{name} (awaiting {PENDING_WEB_DEPLOY[name]})")
            continue
        if name not in listed:
            problems.append(f"{name}: not on the web's NATIVE_FNS list (used at {', '.join(where)})")
            continue
        mod, export = listed[name]
        rel = f"src/lib/{modules.get(mod, mod)}.ts"
        if rel not in cache:
            cache[rel] = read(rel)
        src = cache[rel]
        if src is None:
            problems.append(f"{name}: {rel} no longer exists in the web code (used at {', '.join(where)})")
        elif not re.search(r"export const " + re.escape(export) + r"\b", src):
            problems.append(f"{name}: {rel} no longer exports {export} (used at {', '.join(where)})")

    lang_pending = []
    check_languages(read, problems, lang_pending)

    target = args.web or f"{REPO}@{args.ref}"
    for p in pending + lang_pending:
        print(f"::warning::iOS ↔ web contract: not on {target} yet, allowed as pending web deploy: {p}")
    if problems:
        for p in problems:
            print(f"::error::iOS ↔ web contract: {p}")
        print(f"\n{len(problems)} broken promise(s) between the iOS app and {target}.")
        return 1
    checked = len(calls) - len(pending)
    extra = f" ({len(pending)} pending web deploy)" if pending else ""
    if lang_pending:
        extra += f"; {len(lang_pending)} display language(s) pending web deploy"
    print(f"iOS ↔ web contract OK: all {checked} checked server functions the app calls exist on {target}{extra}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
