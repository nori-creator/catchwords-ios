#!/usr/bin/env python3
"""Writes the Supabase auth email templates (supabase/templates/*.html) in every display language.

Owner, 2026-10-23: the emails come in the learner's display language and never mix languages. Supabase
renders the templates with Go templates and hands the account's user_metadata over as `.Data`; the
profile's display language is copied there as `ui_language` (migration 20261023120000). One template
holds every language and shows only the matching one; an unknown or missing language gets the
fallback of ios/Localization/languages.json.

The texts live here, one block per language and email. The subject is the app's name only, the same
in every language, because the subject line cannot be chosen per language.

Run: python3 scripts/build_auth_emails.py   (then paste each file into Supabase → Authentication →
Emails → Templates, or keep them in sync with `supabase/config.toml`).
"""
from __future__ import annotations

import html
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "supabase" / "templates"
LANGS = json.loads((ROOT / "ios" / "Localization" / "languages.json").read_text())
CODES = [l["code"] for l in LANGS["languages"]]
FALLBACK = LANGS["fallback"]

IGNORE = {
    "ja": "このメールに心当たりがない場合は、何もしなくて大丈夫です。",
    "en": "If this wasn't you, you can ignore this email.",
    "zh-TW": "如果這不是你本人的操作，請忽略這封郵件。",
    "es": "Si no fuiste tú, puedes ignorar este correo.",
    "ko": "본인이 요청하지 않았다면 이 메일은 무시하셔도 됩니다.",
    "vi": "Nếu đây không phải là bạn, hãy bỏ qua email này.",
}

# (body, button) per language. `{new_email}` becomes the template's `{{ .NewEmail }}`.
EMAILS: dict[str, dict[str, tuple[str, str]]] = {
    "confirmation": {
        "ja": ("CatchWords へようこそ。下のボタンを押して、メールアドレスを確認してください。確認が終わったら、アプリに戻ってログインしてください。", "メールアドレスを確認する"),
        "en": ("Welcome to CatchWords. Tap the button below to confirm your email address, then go back to the app and sign in.", "Confirm email address"),
        "zh-TW": ("歡迎使用 CatchWords。請按下方按鈕確認你的電子郵件地址，確認後請回到 App 登入。", "確認電子郵件地址"),
        "es": ("Te damos la bienvenida a CatchWords. Toca el botón de abajo para confirmar tu correo electrónico y luego vuelve a la app para iniciar sesión.", "Confirmar correo electrónico"),
        "ko": ("CatchWords에 오신 것을 환영합니다. 아래 버튼을 눌러 이메일 주소를 확인한 뒤, 앱으로 돌아가 로그인해 주세요.", "이메일 주소 확인"),
        "vi": ("Chào mừng bạn đến với CatchWords. Hãy nhấn nút bên dưới để xác nhận địa chỉ email, sau đó quay lại ứng dụng và đăng nhập.", "Xác nhận email"),
    },
    "recovery": {
        "ja": ("下のボタンを押すと、パスワードを設定するページが開きます。そこで新しいパスワードを決めてください。", "パスワードを設定する"),
        "en": ("Tap the button below to open the page where you can choose a new password.", "Set password"),
        "zh-TW": ("請按下方按鈕，在開啟的頁面中設定新密碼。", "設定密碼"),
        "es": ("Toca el botón de abajo para abrir la página donde puedes elegir una contraseña nueva.", "Establecer contraseña"),
        "ko": ("아래 버튼을 누르면 새 비밀번호를 정할 수 있는 페이지가 열립니다.", "비밀번호 설정"),
        "vi": ("Hãy nhấn nút bên dưới để mở trang đặt mật khẩu mới.", "Đặt mật khẩu"),
    },
    "email_change": {
        "ja": ("メールアドレスを {new_email} に変更するには、下のボタンを押してください。", "変更を確定する"),
        "en": ("To change your email address to {new_email}, tap the button below.", "Confirm change"),
        "zh-TW": ("如要將電子郵件地址變更為 {new_email}，請按下方按鈕。", "確認變更"),
        "es": ("Para cambiar tu correo electrónico a {new_email}, toca el botón de abajo.", "Confirmar cambio"),
        "ko": ("이메일 주소를 {new_email}(으)로 변경하려면 아래 버튼을 눌러 주세요.", "변경 확인"),
        "vi": ("Để đổi địa chỉ email thành {new_email}, hãy nhấn nút bên dưới.", "Xác nhận thay đổi"),
    },
}

STYLE_P = "margin:0 0 20px;font-size:16px;line-height:1.6;color:#1c1c1e"
STYLE_A = ("display:inline-block;padding:12px 22px;border-radius:10px;background:#1c1c1e;color:#ffffff;"
           "font-size:16px;font-weight:600;text-decoration:none")
STYLE_SMALL = "margin:24px 0 0;font-size:13px;line-height:1.5;color:#6e6e73"


def block(code: str, body: str, button: str) -> str:
    text = html.escape(body).replace("{new_email}", "{{ .NewEmail }}")
    return (
        f'<div lang="{code}">\n'
        f'  <p style="{STYLE_P}">{text}</p>\n'
        f'  <p style="margin:0"><a href="{{{{ .ConfirmationURL }}}}" style="{STYLE_A}">{html.escape(button)}</a></p>\n'
        f'  <p style="{STYLE_SMALL}">{html.escape(IGNORE[code])}</p>\n'
        f"</div>\n"
    )


def template(name: str) -> str:
    texts = EMAILS[name]
    missing = [c for c in CODES if c not in texts or c not in IGNORE]
    if missing:
        raise SystemExit(f"{name}: no text for {', '.join(missing)} (add it here, languages.json lists it)")
    out = ['{{ $l := or .Data.ui_language "" }}']
    others = [c for c in CODES if c != FALLBACK]
    for i, code in enumerate(others):
        out.append(f'{{{{ {"if" if i == 0 else "else if"} eq $l "{code}" }}}}')
        out.append(block(code, *texts[code]).rstrip("\n"))
    out.append("{{ else }}")
    out.append(block(FALLBACK, *texts[FALLBACK]).rstrip("\n"))
    out.append("{{ end }}")
    return (
        '<div style="max-width:480px;margin:0 auto;padding:24px;font-family:-apple-system,'
        "'Hiragino Sans','PingFang TC','Apple SD Gothic Neo',sans-serif\">\n"
        '<p style="margin:0 0 24px;font-size:20px;font-weight:700;color:#1c1c1e">CatchWords</p>\n'
        + "\n".join(out)
        + "\n</div>\n"
    )


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for name in EMAILS:
        (OUT / f"{name}.html").write_text(template(name))
        print(f"wrote supabase/templates/{name}.html")


if __name__ == "__main__":
    main()
