#!/usr/bin/env python3
"""Add a display language to the iOS app, and fill every missing translation.

    # 1. Register a language (languages.json, the Xcode project, its permission texts file):
    python3 scripts/add_language.py add --code fr --autonym "Français" --name-ja "フランス語" --flag 🇫🇷 \\
        --locale fr_FR --script latin

    # 2. Translate everything still missing, in every language (needs ANTHROPIC_API_KEY):
    python3 scripts/add_language.py fill

    # What is missing, per language (no API call):
    python3 scripts/add_language.py missing

`fill` writes the translations into strings.json, widget-strings.json and <lproj>.lproj/InfoPlist.strings, asks for the
language's own marker words and degree-word glosses when they are empty, decides whether the bundled handwriting font
has every letter the translations use, regenerates ios/Shared/DisplayLanguages.swift, and runs check_l10n.py.
Machine translations are marked `"reviewed": false` in languages.json until a person has read them on screen.
The whole procedure, for people: docs/adding-a-display-language.md.
"""
import argparse
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import l10n_languages  # noqa: E402

ROOT = l10n_languages.ROOT
IOS = os.path.join(ROOT, "ios")
TABLE = os.path.join(IOS, "CatchWords", "Resources", "Localization", "strings.json")
WIDGET_TABLE = os.path.join(IOS, "Shared", "Localization", "widget-strings.json")
RESOURCES = os.path.join(IOS, "CatchWords", "Resources")
PBXPROJ = os.path.join(IOS, "CatchWords.xcodeproj", "project.pbxproj")
FONT = os.path.join(RESOURCES, "Fonts", "ZenKurenaido-Regular.ttf")
MODEL = os.environ.get("CATCHWORDS_TRANSLATE_MODEL", "claude-opus-5-5")
BATCH = 60

# Per script: the punctuation the app puts between and around parts, and how much a short meaning keeps.
SCRIPT_DEFAULTS = {
    "latin": {"listSeparator": ", ", "openBracket": " (", "closeBracket": ")", "placeSeparator": ", ", "glossLimit": 24},
    "hangul": {"listSeparator": ", ", "openBracket": " (", "closeBracket": ")", "placeSeparator": " ", "glossLimit": 12},
    "han": {"listSeparator": "，", "openBracket": "（", "closeBracket": "）", "placeSeparator": " ", "glossLimit": 12},
    "kana": {"listSeparator": "、", "openBracket": "（", "closeBracket": "）", "placeSeparator": " ", "glossLimit": 12},
}


# MARK: - Files

def read_json(path):
    return json.load(open(path, encoding="utf-8"))


def write_json(path, data, indent=1):
    raw = open(path, encoding="utf-8").read() if os.path.exists(path) else ""
    if raw.startswith("{\n  \""):
        indent = 2
    out = json.dumps(data, ensure_ascii=False, indent=indent)
    open(path, "w", encoding="utf-8").write(out + "\n")


def read_registry():
    return read_json(l10n_languages.REGISTRY)


def write_registry(data):
    open(l10n_languages.REGISTRY, "w", encoding="utf-8").write(json.dumps(data, ensure_ascii=False, indent=2) + "\n")


def plist_path(lang):
    return os.path.join(RESOURCES, f"{lang['lproj']}.lproj", "InfoPlist.strings")


def read_plist(path):
    """InfoPlist.strings → {key: value} (one "KEY" = "value"; per line, as these files are written)."""
    if not os.path.exists(path):
        return {}
    out = {}
    for m in re.finditer(r'^\s*"([A-Za-z0-9_]+)"\s*=\s*"((?:[^"\\]|\\.)*)";', open(path, encoding="utf-8").read(), re.M):
        out[m.group(1)] = m.group(2).replace('\\"', '"').replace("\\\\", "\\")
    return out


def write_plist(path, lang, values):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lines = [f"/* Permission descriptions ({lang['autonym']}) */"]
    for k, v in values.items():
        lines.append(f'"{k}" = "{v.replace(chr(92), chr(92) * 2).replace(chr(34), chr(92) + chr(34))}";')
    open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")


def add_known_region(lproj):
    pbx = open(PBXPROJ, encoding="utf-8").read()
    m = re.search(r"(knownRegions = \()([^)]*)(\);)", pbx)
    if not m:
        sys.exit("knownRegions not found in project.pbxproj")
    regions = [r.strip() for r in m.group(2).split(",") if r.strip()]
    if lproj in [r.strip('"') for r in regions]:
        return False
    name = f'"{lproj}"' if re.search(r"[^A-Za-z0-9_]", lproj) else lproj
    indent = re.search(r"\n(\s*)\S", m.group(2)).group(1) if "\n" in m.group(2) else "\t\t\t\t"
    body = m.group(2).rstrip()
    body = body + ("" if body.endswith(",") else ",") + f"\n{indent}{name},\n{indent[:-1]}"
    open(PBXPROJ, "w", encoding="utf-8").write(pbx[:m.start(2)] + body + pbx[m.end(2):])
    return True


# MARK: - add

def cmd_add(args):
    data = read_registry()
    if any(l["code"] == args.code for l in data["languages"]):
        sys.exit(f"{args.code} is already listed in languages.json")
    if args.script not in SCRIPT_DEFAULTS:
        sys.exit(f"--script must be one of {', '.join(SCRIPT_DEFAULTS)}. A language in another script (Thai, Arabic, "
                 f"Cyrillic, Devanagari …) needs reader rules in LanguageRules.swift first — see the doc.")
    lproj = args.lproj or args.code
    entry = {
        "code": args.code,
        "autonym": args.autonym,
        "nameJa": args.name_ja,
        "flag": args.flag,
        "locale": args.locale,
        "lproj": lproj,
        "devicePrefixes": [p.lower() for p in (args.device or [args.code.lower()])],
        "script": args.script,
        **SCRIPT_DEFAULTS[args.script],
        "handwritingFont": False,
        "legalDocs": False,
        "reviewed": False,
        "plurals": {},
        "markerWords": [],
        "markerLetters": "",
        "degreeGlosses": {},
    }
    data["languages"].append(entry)
    write_registry(data)
    added = add_known_region(lproj)
    plist = plist_path(entry)
    if not os.path.exists(plist):
        write_plist(plist, entry, {})
    subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "l10n_languages.py")], check=True)
    print(f"Added {args.code} ({args.autonym}) to languages.json"
          + (f", knownRegions {lproj}" if added else "") + f", {os.path.relpath(plist, ROOT)}.")
    print("Next: python3 scripts/add_language.py fill   (ANTHROPIC_API_KEY set), then read the screens.")
    print("Also: the web repository's explanation languages (src/lib/explain-languages.ts) — see the doc, step 4.")


# MARK: - missing

def missing_work(data):
    """Everything that has no translation yet: (table name, key, source texts, language) rows."""
    table = read_json(TABLE)
    widgets = read_json(WIDGET_TABLE)
    langs = l10n_languages.targets(data)
    work = []
    names = {l["nameJa"] for l in data["languages"]}
    for k in names:
        table.setdefault(k, {})
    for name, t in (("strings", table), ("widgets", widgets)):
        for k, entry in t.items():
            for lang in langs:
                if not entry.get(lang["code"]):
                    work.append((name, k, {"ja": k, "en": entry.get("en", "")}, lang))
    source = next(l for l in data["languages"] if l["code"] == data["source"])
    fallback = next(l for l in data["languages"] if l["code"] == data["fallback"])
    base, en = read_plist(plist_path(source)), read_plist(plist_path(fallback))
    for lang in langs:
        have = read_plist(plist_path(lang))
        for k, v in base.items():
            if not have.get(k):
                work.append(("plist", k, {"ja": v, "en": en.get(k, "")}, lang))
    return work


def cmd_missing(_args):
    data = l10n_languages.load()
    work = missing_work(data)
    if not work:
        print("Nothing is missing.")
        return
    by = {}
    for name, _k, _s, lang in work:
        by.setdefault(lang["code"], {}).setdefault(name, 0)
        by[lang["code"]][name] += 1
    for code, counts in by.items():
        print(f"{code}: " + ", ".join(f"{n} {name}" for name, n in counts.items()))


# MARK: - fill (Claude API)

SCHEMA = {
    "type": "object",
    "properties": {
        "translations": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {"id": {"type": "string"}, "text": {"type": "string"}},
                "required": ["id", "text"],
                "additionalProperties": False,
            },
        }
    },
    "required": ["translations"],
    "additionalProperties": False,
}


def brief(lang, glossary):
    rules = {
        "latin": "No Japanese kana, no Chinese characters, no Hangul.",
        "hangul": "No Japanese kana and no Chinese characters (write everything in Hangul, Latin only for names).",
        "han": "Traditional characters as written in Taiwan; no Japanese kana, no Hangul, no Japanese-only kanji forms.",
        "kana": "Natural Japanese.",
    }[lang["script"]]
    return (
        "You localize the UI of CatchWords, an iPhone app for learning Taiwanese Mandarin from photos (you photograph "
        "things, the app names them in Mandarin, the words go into a collection, spaced-repetition review brings them "
        f"back). Translate each item into {lang['autonym']} (code {lang['code']}) for this app's screens.\n\n"
        "Each item has the Japanese source (`ja`, authoritative) and the reviewed English (`en`, a guide to meaning, "
        "tone and length). Translate the meaning, the way a professional app localizer would.\n"
        "Rules:\n"
        "- Keep every placeholder {1}, {2} … exactly (you may move it). They hold numbers, words, names and dates.\n"
        f"- {rules}\n"
        "- Where the Japanese mentions a Mandarin word, follow the English (which never contains Chinese characters). "
        "Bopomofo (ㄅㄆㄇ …) stays as it is.\n"
        "- Keep line breaks where the Japanese has them. Keep names as they are: CatchWords, Pro, App Store, iPhone, "
        "Apple, Google, TOCFL, CEFR, JLPT, Weblio, YouTube, emoji, URLs.\n"
        "- Short labels stay short (buttons, tabs, chips). Informal, friendly, consistent terminology.\n"
        "- Counted nouns after a number: the plural form ({1} words); the app makes the singular after 1 itself.\n\n"
        "Terms already used in this language (keep them consistent):\n" + glossary
    )


def glossary_for(lang, table):
    terms = ["図鑑", "復習", "単語", "例文", "意味", "撮る", "写真", "設定", "表示言語", "学習言語", "台湾華語", "削除", "キャッチ"]
    rows = [f"- {t}: {table[t][lang['code']]}" for t in terms if table.get(t, {}).get(lang["code"])]
    return "\n".join(rows) or "- (none yet: you are choosing them now)"


def call_claude(client, system, items):
    """One batch: [{id, ja, en}] → {id: text}. Structured output, server-side refusal fallback."""
    with client.beta.messages.stream(
        model=MODEL,
        max_tokens=32000,
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
        system=system,
        output_config={"effort": "high", "format": {"type": "json_schema", "schema": SCHEMA}},
        messages=[{"role": "user", "content": json.dumps(items, ensure_ascii=False)}],
    ) as stream:
        msg = stream.get_final_message()
    if msg.stop_reason == "refusal":
        raise RuntimeError(f"the model declined this batch ({getattr(msg.stop_details, 'category', None)})")
    if msg.stop_reason == "max_tokens":
        raise RuntimeError("the answer was cut off (max_tokens); run again with a smaller CATCHWORDS_TRANSLATE_BATCH")
    text = next(b.text for b in msg.content if b.type == "text")
    return {t["id"]: t["text"] for t in json.loads(text)["translations"]}


def placeholders_ok(src, out):
    return all(("{%d}" % i in src) == ("{%d}" % i in out) for i in range(1, 10))


def ask_language_data(client, lang, data):
    """Marker words / letters (Latin script) and the Mandarin degree-word glosses, when still empty."""
    want = {}
    if lang["script"] == "latin" and not lang["markerWords"]:
        want["markerWords"] = ("Up to 40 very common function words of this language (articles, prepositions, "
                               "pronouns, conjunctions, common verbs), lowercase, one per item, that rarely appear "
                               "in English, Spanish, Vietnamese or the other listed languages.")
        want["markerLetters"] = "The accented or special letters typical of this language, all in one item, lowercase."
    if not lang["degreeGlosses"]:
        en = next(l for l in data["languages"] if l["code"] == "en")["degreeGlosses"]
        for word, gloss in en.items():
            want[f"degree:{word}"] = f"The Mandarin degree word {word} (English “{gloss}”), as it reads in a translation."
    if not want:
        return False
    items = [{"id": k, "ja": "", "en": v} for k, v in want.items()]
    system = (f"Answer for the language {lang['autonym']} ({lang['code']}). Each item asks for data about that "
              "language; put the answer in `text`. For lists, separate items with a single space.")
    got = call_claude(client, system, items)
    if "markerWords" in got:
        lang["markerWords"] = sorted(set(got["markerWords"].lower().split()))[:40]
    if "markerLetters" in got:
        lang["markerLetters"] = "".join(sorted(set(re.sub(r"[\sA-Za-z]", "", got["markerLetters"].lower()))))
    for k, v in got.items():
        if k.startswith("degree:") and v.strip():
            lang["degreeGlosses"][k.split(":", 1)[1]] = v.strip()
    return True


def font_covers(texts):
    """Whether the bundled handwriting font has every letter of these texts (fontTools; False when it can't tell)."""
    try:
        from fontTools.ttLib import TTFont
    except ImportError:
        return False
    cmap = TTFont(FONT).getBestCmap()
    letters = {c for t in texts for c in t if c.isalpha()}
    return all(ord(c) in cmap for c in letters)


def cmd_fill(args):
    try:
        import anthropic
    except ImportError:
        sys.exit("pip install anthropic   (and set ANTHROPIC_API_KEY)")
    client = anthropic.Anthropic()
    data = read_registry()
    l10n_languages.load()  # validates
    table = read_json(TABLE)
    widgets = read_json(WIDGET_TABLE)
    work = missing_work(data)
    if args.only:
        work = [w for w in work if w[3]["code"] in args.only]
    by_lang = {}
    for row in work:
        by_lang.setdefault(row[3]["code"], []).append(row)
    batch = int(os.environ.get("CATCHWORDS_TRANSLATE_BATCH", BATCH))
    failed = []
    for code, rows in by_lang.items():
        lang = next(l for l in data["languages"] if l["code"] == code)
        system = brief(lang, glossary_for(lang, table))
        plist_values = read_plist(plist_path(lang))
        print(f"{code}: {len(rows)} to translate")
        for i in range(0, len(rows), batch):
            part = rows[i:i + batch]
            items = [{"id": str(n), "ja": src["ja"], "en": src["en"]} for n, (_t, _k, src, _l) in enumerate(part)]
            got = call_claude(client, system, items)
            for n, (name, key, src, _l) in enumerate(part):
                text = (got.get(str(n)) or "").strip()
                if not text or not placeholders_ok(src["ja"], text):
                    failed.append(f"{code} {name}: {key}")
                    continue
                if name == "strings":
                    table.setdefault(key, {})[code] = text
                elif name == "widgets":
                    widgets.setdefault(key, {})[code] = text
                else:
                    plist_values[key] = text
            write_json(TABLE, table)
            write_json(WIDGET_TABLE, widgets)
            if plist_values:
                write_plist(plist_path(lang), lang, plist_values)
            print(f"  {min(i + batch, len(rows))}/{len(rows)}")
    # Language data and the font decision, for every machine-translated language.
    for lang in data["languages"]:
        if lang["reviewed"] or (args.only and lang["code"] not in args.only):
            continue
        ask_language_data(client, lang, data)
        texts = [e.get(lang["code"], "") for e in table.values()] + [e.get(lang["code"], "") for e in widgets.values()]
        lang["handwritingFont"] = font_covers(texts)
    write_registry(data)
    subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "l10n_languages.py")], check=True)
    if failed:
        print(f"{len(failed)} item(s) came back without a usable translation; run fill again:")
        print("\n".join(failed[:30]))
    result = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "check_l10n.py")])
    sys.exit(result.returncode or (1 if failed else 0))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("add", help="register a new display language")
    a.add_argument("--code", required=True, help="the web's code, also saved in profiles.ui_language (fr, pt-BR …)")
    a.add_argument("--autonym", required=True, help="the language's own name (Français)")
    a.add_argument("--name-ja", required=True, help="its Japanese name (フランス語), a key of strings.json")
    a.add_argument("--flag", required=True, help="the flag emoji shown in onboarding")
    a.add_argument("--locale", required=True, help="dates and numbers (fr_FR)")
    a.add_argument("--script", required=True, choices=sorted(SCRIPT_DEFAULTS), help="the script it is written in")
    a.add_argument("--lproj", help="Xcode localization folder name (default: the code)")
    a.add_argument("--device", nargs="*", help="iPhone language ids that start the app in it (default: the code)")
    a.set_defaults(fn=cmd_add)
    f = sub.add_parser("fill", help="translate everything missing with the Claude API")
    f.add_argument("--only", nargs="*", help="only these language codes")
    f.set_defaults(fn=cmd_fill)
    m = sub.add_parser("missing", help="list what is missing")
    m.set_defaults(fn=cmd_missing)
    args = p.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
