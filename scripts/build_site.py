#!/usr/bin/env python3
"""Builds the public site for https://catchwords.app (GitHub Pages) from site/src into site/public.

  python3 scripts/build_site.py

Each page carries every language it has (ja / en / zh-TW, the languages with `legalDocs` in
ios/Localization/languages.json) and shows one: `?lang=` first (the app sends it), then the
browser's language, then English. Only the chosen language is visible, so languages never mix.

Pages: / , /privacy, /terms, /legal/tokushoho, /support, /reset-password (the link in the
password e-mail lands here; it sets the new password through Supabase Auth).
"""
from __future__ import annotations

import html
import json
import pathlib
import re
import shutil

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "site" / "src"
OUT = ROOT / "site" / "public"
DOMAIN = "catchwords.app"
LANGS = ["ja", "en", "zh-TW"]
FALLBACK = "en"

# The project's public address and publishable key, the same values as ios/CatchWords/AppConfig.swift
# (both are meant to be public; every row is protected by RLS).
APP_CONFIG = (ROOT / "ios" / "CatchWords" / "AppConfig.swift").read_text()
SUPABASE_URL = re.search(r'supabaseURL = "([^"]+)"', APP_CONFIG).group(1)
SUPABASE_KEY = re.search(r'supabasePublishableKey = "([^"]+)"', APP_CONFIG).group(1)

LANG_NAMES = {"ja": "日本語", "en": "English", "zh-TW": "繁體中文"}

# path → (source name, title per language)
PAGES = {
    "privacy": ("privacy", {"ja": "プライバシーポリシー", "en": "Privacy Policy", "zh-TW": "隱私權政策"}),
    "terms": ("terms", {"ja": "利用規約", "en": "Terms of Use", "zh-TW": "使用條款"}),
    "legal/tokushoho": (
        "tokushoho",
        {"ja": "特定商取引法に基づく表記", "en": "Legal Notice (Specified Commercial Transactions Act)", "zh-TW": "特定商業交易法標示"},
    ),
    "support": ("support", {"ja": "お問い合わせ・サポート", "en": "Contact & Support", "zh-TW": "聯絡與支援"}),
}

UI = {
    "language": {"ja": "表示言語", "en": "Language", "zh-TW": "顯示語言"},
    "home": {"ja": "CatchWords", "en": "CatchWords", "zh-TW": "CatchWords"},
    "tagline": {
        "ja": "写真に撮った身の回りの物が、学んでいる言語の単語カードになる iPhone アプリです。",
        "en": "An iPhone app that turns the things you photograph into word cards in the language you are learning.",
        "zh-TW": "把身邊拍下的東西，變成你正在學習的語言單字卡的 iPhone App。",
    },
}

RESET = {
    "title": {"ja": "パスワードの再設定", "en": "Reset your password", "zh-TW": "重設密碼"},
    "intro": {
        "ja": "新しいパスワードを入れてください（8文字以上）。",
        "en": "Enter a new password (at least 8 characters).",
        "zh-TW": "請輸入新密碼（至少 8 個字元）。",
    },
    "new": {"ja": "新しいパスワード", "en": "New password", "zh-TW": "新密碼"},
    "again": {"ja": "もう一度", "en": "Confirm password", "zh-TW": "再輸入一次"},
    "save": {"ja": "保存する", "en": "Save", "zh-TW": "儲存"},
    "short": {"ja": "8文字以上にしてください。", "en": "Use at least 8 characters.", "zh-TW": "請使用至少 8 個字元。"},
    "mismatch": {"ja": "2つのパスワードが違います。", "en": "The two passwords do not match.", "zh-TW": "兩次輸入的密碼不一致。"},
    "done": {
        "ja": "パスワードを変えました。アプリに戻って、新しいパスワードでログインしてください。",
        "en": "Your password has been changed. Go back to the app and sign in with the new password.",
        "zh-TW": "密碼已變更。請回到 App，用新密碼登入。",
    },
    "expired": {
        "ja": "このリンクは使えません（期限切れか、使用済みです）。アプリの「パスワードを忘れた」から、もう一度メールを送ってください。",
        "en": "This link can no longer be used (it has expired or was already used). Request a new e-mail from “Forgot password” in the app.",
        "zh-TW": "此連結已無法使用（已過期或已使用）。請在 App 的「忘記密碼」重新寄送郵件。",
    },
    "failed": {
        "ja": "保存できませんでした。時間をおいてもう一度お試しください。",
        "en": "The password could not be saved. Please try again later.",
        "zh-TW": "無法儲存。請稍後再試。",
    },
}


def per_lang(texts: dict[str, str], tag: str = "span") -> str:
    return "".join(f'<{tag} class="l" lang="{l}">{texts[l]}</{tag}>' for l in LANGS)


def lang_nav(path: str) -> str:
    items = "".join(
        f'<li><a href="/{path}?lang={l}" hreflang="{l}" lang="{l}" data-lang-link="{l}">{LANG_NAMES[l]}</a></li>'
        for l in LANGS
    )
    return f'<nav class="langs" aria-label="Language"><ul>{items}</ul></nav>'


def page(path: str, titles: dict[str, str], body: str, extra_head: str = "") -> str:
    title_json = html.escape(json.dumps(titles, ensure_ascii=False), quote=True)
    return f"""<!doctype html>
<html lang="{FALLBACK}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(titles[FALLBACK])} — CatchWords</title>
<link rel="canonical" href="https://{DOMAIN}/{path}">
<link rel="stylesheet" href="/assets/site.css">
<script src="/assets/lang.js"></script>
{extra_head}</head>
<body data-titles="{title_json}">
<header class="top"><a class="brand" href="/">CatchWords</a>{lang_nav(path)}</header>
<main>
{body}
</main>
</body>
</html>
"""


def footer(path: str, lang: str) -> str:
    """Links to the other legal pages, titled in the reader's language."""
    items = "".join(
        f'<li><a href="/{p}?lang={lang}">{titles[lang]}</a></li>' for p, (_, titles) in PAGES.items() if p != path
    )
    return f"<nav><ul>{items}</ul></nav>"


def fragment(name: str, lang: str, path: str) -> str:
    s = (SRC / f"{name}.{lang}.html").read_text().strip() + "\n" + footer(path, lang)
    # Links between the legal pages keep the reader's language.
    s = re.sub(r'href="/(privacy|terms|support|legal/tokushoho)"', rf'href="/\1?lang={lang}"', s)
    return f'<article class="l" lang="{lang}">\n{s}\n</article>'


def build() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    (OUT / "assets").mkdir(parents=True)
    shutil.copy(SRC / "site.css", OUT / "assets" / "site.css")
    shutil.copy(SRC / "lang.js", OUT / "assets" / "lang.js")
    (OUT / "CNAME").write_text(DOMAIN + "\n")
    (OUT / ".nojekyll").write_text("")
    # The labelled photos the admin AI test fetches (AdminAIStats.swift: webBaseURL + /ai-test/photos/…).
    shutil.copytree(ROOT / "server" / "public" / "ai-test", OUT / "ai-test")

    for path, (name, titles) in PAGES.items():
        body = "\n".join(fragment(name, l, path) for l in LANGS)
        dest = OUT / f"{path}.html"
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text(page(path, titles, body))

    links = "".join(
        f'<li><a href="/{p}">{per_lang(t)}</a></li>' for p, (_, t) in PAGES.items()
    )
    home = f"""<h1>CatchWords</h1>
<p>{per_lang(UI["tagline"])}</p>
<ul class="links">{links}</ul>"""
    (OUT / "index.html").write_text(page("", {l: "CatchWords" for l in LANGS}, home).replace("<title>CatchWords — CatchWords</title>", "<title>CatchWords</title>"))

    r = {k: per_lang(v) for k, v in RESET.items()}
    reset_body = f"""<h1>{r["title"]}</h1>
<form id="reset" hidden>
<p>{r["intro"]}</p>
<label>{r["new"]}<input id="pw1" type="password" autocomplete="new-password" minlength="8" required></label>
<label>{r["again"]}<input id="pw2" type="password" autocomplete="new-password" minlength="8" required></label>
<button type="submit">{r["save"]}</button>
</form>
<p class="msg" id="m-short" hidden>{r["short"]}</p>
<p class="msg" id="m-mismatch" hidden>{r["mismatch"]}</p>
<p class="msg ok" id="m-done" hidden>{r["done"]}</p>
<p class="msg" id="m-expired" hidden>{r["expired"]}</p>
<p class="msg" id="m-failed" hidden>{r["failed"]}</p>"""
    cfg = f'<script>window.CW_AUTH={{url:{json.dumps(SUPABASE_URL)},key:{json.dumps(SUPABASE_KEY)}}};</script>\n<script src="/assets/reset.js" defer></script>\n'
    shutil.copy(SRC / "reset.js", OUT / "assets" / "reset.js")
    (OUT / "reset-password.html").write_text(page("reset-password", RESET["title"], reset_body, cfg))

    not_found = f"""<h1>404</h1><p><a href="/">CatchWords</a></p>"""
    (OUT / "404.html").write_text(page("", {l: "404" for l in LANGS}, not_found))
    print(f"site: {sum(1 for _ in OUT.rglob('*.html'))} pages → {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    build()
