#!/usr/bin/env python3
"""CI guard: no Japanese UI text may bypass L(…), and every key has every display language.

The display languages are the ones in ios/Localization/languages.json (scripts/l10n_languages.py). Checked:
  - every Japanese literal in the app is passed through L(…) (or marked `// l10n-ignore` as data);
  - every key used has a translation in every language, with its {n} placeholders, in that language's script;
  - the widgets' table (Shared/Localization/widget-strings.json) likewise, and every widget key exists in it;
  - every language name (languages.json nameJa) is in the table;
  - every language has its <lproj>.lproj/InfoPlist.strings with the same permission keys, and is a known
    region of the Xcode project;
  - ios/Shared/DisplayLanguages.swift is what languages.json makes.

Exit 1 with a list of problems. Run from the repo root:  python3 scripts/check_l10n.py
"""
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
from l10n_lib import JP_CORE, ignored, is_wrapped, key_of, line_of, scan  # noqa: E402
import l10n_languages  # noqa: E402

KANA = re.compile(r"[ぁ-んァ-ヶー]")
HAN = re.compile(r"[一-鿿㐀-䶿]")
HANGUL = re.compile(r"[가-힣ᄀ-ᇿ]")

IOS = os.path.join(os.path.dirname(__file__), "..", "ios")
ROOT = os.path.join(IOS, "CatchWords")
SKIP = {"Views/UIPreview.swift"}  # DEBUG-only fixtures for the simulator check
TABLE = os.path.join(ROOT, "Resources", "Localization", "strings.json")
WIDGET_TABLE = os.path.join(IOS, "Shared", "Localization", "widget-strings.json")
WIDGETS = os.path.join(IOS, "CatchWordsWidgets")
RESOURCES = os.path.join(ROOT, "Resources")
PBXPROJ = os.path.join(IOS, "CatchWords.xcodeproj", "project.pbxproj")


def script_problem(lang, text):
    """What a translation must not contain, by the script of its language (R1, R2 and the same for every language)."""
    script = lang["script"]
    if script == "latin":
        # R1 (docs/language-rules.md): Latin-script text never carries kana, Han or Hangul. A learning-language
        # sample goes in as a {n} value from NativeAPI.sample, never into the translation.
        if KANA.search(text) or HAN.search(text) or HANGUL.search(text):
            return f"R1 {lang['code']} contains Japanese/Chinese/Korean"
    elif script == "han":
        # R2: Traditional Chinese never carries kana, nor the Japanese middle dot (web G3), nor Hangul.
        if KANA.search(text) or "・" in text or HANGUL.search(text):
            return f"R2 {lang['code']} contains kana or Hangul"
    elif script == "hangul":
        if KANA.search(text) or HAN.search(text):
            return f"R2 {lang['code']} contains kana or Chinese characters"
    return None


def check_entry(where, key, entry, langs, problems):
    for lang in langs:
        code = lang["code"]
        t = (entry or {}).get(code, "")
        if not t:
            problems.append(f"{where}: missing {code}: \"{key}\"")
            continue
        why = script_problem(lang, t)
        if why:
            problems.append(f"{where}: {why}: \"{t}\"")
        # placeholders must survive translation
        for i in range(1, 10):
            ph = "{%d}" % i
            if ph in key and ph not in t:
                problems.append(f"{where}: {code} lost {ph}: \"{t}\"")


def strings_file_keys(path):
    """The keys of an InfoPlist.strings file ("KEY" = "…";)."""
    return set(re.findall(r'^\s*"([A-Za-z0-9_]+)"\s*=', open(path, encoding="utf-8").read(), re.M))


def main():
    data = l10n_languages.load()
    langs = l10n_languages.targets(data)
    table = json.load(open(TABLE, encoding="utf-8"))
    problems, keys = [], set()

    # 1. The app's own text.
    for path in sorted(glob.glob(os.path.join(ROOT, "**", "*.swift"), recursive=True)):
        rel = os.path.relpath(path, ROOT)
        if rel in SKIP:
            continue
        src = open(path, encoding="utf-8").read()
        for start, _end, body, _multi in scan(src):
            if not JP_CORE.search(body):
                continue
            k = key_of(body)
            wrapped = is_wrapped(src, start)
            if not wrapped and ignored(src, start):
                continue  # data (server payloads, prompts, target-language words, autonyms)
            if not wrapped:
                problems.append(f"{rel}:{line_of(src, start)}: not passed through L(): \"{k}\"")
                continue
            keys.add(k)
            check_entry(f"{rel}:{line_of(src, start)}", k, table.get(k), langs, problems)

    # 2. Language names, looked up with L10n.text(nameJa) (onboarding, 設定).
    for lang in data["languages"]:
        keys.add(lang["nameJa"])
        check_entry(f"languages.json {lang['code']} nameJa", lang["nameJa"], table.get(lang["nameJa"]), langs, problems)

    # 3. The widgets: every Japanese literal is a key of their own table, and the table is complete.
    widget_table = json.load(open(WIDGET_TABLE, encoding="utf-8"))
    for path in sorted(glob.glob(os.path.join(WIDGETS, "*.swift"))):
        rel = os.path.relpath(path, IOS)
        src = open(path, encoding="utf-8").read()
        for start, _end, body, _multi in scan(src):
            if JP_CORE.search(body) and not ignored(src, start) and key_of(body) not in widget_table:
                problems.append(f"{rel}:{line_of(src, start)}: widget text not in widget-strings.json: \"{key_of(body)}\"")
    for k, entry in widget_table.items():
        check_entry("widget-strings.json", k, entry, langs, problems)

    # 4. Permission texts (InfoPlist.strings) for every language, and every language a known region.
    pbx = open(PBXPROJ, encoding="utf-8").read()
    m = re.search(r"knownRegions = \(([^)]*)\);", pbx)
    regions = {r.strip().strip('"') for r in (m.group(1).split(",") if m else []) if r.strip()}
    source = next(l for l in data["languages"] if l["code"] == data["source"])
    base_plist = os.path.join(RESOURCES, f"{source['lproj']}.lproj", "InfoPlist.strings")
    base_keys = strings_file_keys(base_plist)
    for lang in data["languages"]:
        plist = os.path.join(RESOURCES, f"{lang['lproj']}.lproj", "InfoPlist.strings")
        if not os.path.exists(plist):
            problems.append(f"{lang['code']}: missing Resources/{lang['lproj']}.lproj/InfoPlist.strings (permission texts)")
        else:
            missing = base_keys - strings_file_keys(plist)
            if missing:
                problems.append(f"{lang['lproj']}.lproj/InfoPlist.strings: missing {', '.join(sorted(missing))}")
            if lang["code"] != data["source"]:
                body = open(plist, encoding="utf-8").read()
                values = "\n".join(re.findall(r'=\s*"(.*)";', body))
                why = script_problem(lang, values)
                if why:
                    problems.append(f"{lang['lproj']}.lproj/InfoPlist.strings: {why}")
        if lang["lproj"] not in regions:
            problems.append(f"{lang['code']}: \"{lang['lproj']}\" is not in knownRegions of CatchWords.xcodeproj")

    # 5. The generated registry is current.
    swift = open(l10n_languages.SWIFT, encoding="utf-8").read() if os.path.exists(l10n_languages.SWIFT) else ""
    if swift != l10n_languages.render(data):
        problems.append("ios/Shared/DisplayLanguages.swift is not what languages.json makes: run python3 scripts/l10n_languages.py")

    unused = sorted(set(table) - keys)
    if problems:
        print("\n".join(problems))
        print(f"\n{len(problems)} localization problem(s).")
        sys.exit(1)
    names = ", ".join(l["code"] for l in langs)
    print(f"L10n OK: {len(keys)} keys and {len(widget_table)} widget keys, all in {names}."
          + (f" ({len(unused)} unused keys)" if unused else ""))


if __name__ == "__main__":
    main()
