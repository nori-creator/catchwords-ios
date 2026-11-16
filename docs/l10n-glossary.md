# 表示言語の用語集（2026-11-16 の見直し）

オーナー 2026-11-16:「一からそれぞれの言語翻訳が自然かどうかもう一度チェックして、直訳ではなくて最も自然な訳を表示したい」
（スペイン語を話す友人に「ところどころ翻訳が変」と言われた）。

## 見直しの決まり
- **直訳しない**。その言語のアプリで普通に使う言い方にする。
- **丁寧さ（話し方）をそろえる**。
  - es: tú。中立のスペイン語で、地域の俗語は使わない。
  - ko: 해요체。
  - vi: bạn。
  - zh-TW: 台湾の言い方（影片・軟體・訊息・帳號・網路）。
  - en: 米国のつづり。
- 次の 2 つは訳さない。
  - 共通の表記（`docs/language-rules.md` の R25）
  - `{n}` の差し込み
- 文字や差し込みの点検は `scripts/check_l10n.py` が行う。
- 新しい文を足す時は、下の訳語を使う。

## 訳語

| 日本語 | en | zh-TW | es | ko | vi |
|---|---|---|---|---|---|
| 使い方（単語の頁の見出し） | Usage | 用法 | Cómo se usa | 용법 | Cách dùng |
| チャンク（使い方の型） | pattern | 搭配 | expresión | 표현 | cụm từ |
| 例文 | Examples | 例句 | Ejemplos | 예문 | Câu ví dụ |
| 意味 | Meaning | 意思 | Significado | 뜻 | Nghĩa |
| 量詞 | Measure words | 量詞 | Clasificadores | 양사 | Lượng từ |
| 図鑑 | Collection | 圖鑑 | Colección | 도감 | Bộ sưu tập |
| 切り抜き / 切り抜く | cut-out / cut out | 去背圖 / 去背 | recorte / recortar | 컷아웃 / 오려내다 | ảnh tách nền / tách nền |
| ステッカー | sticker | 貼紙 | sticker | 스티커 | nhãn dán |
| 復習 | review | 複習 | repaso | 복습 | ôn tập |
| 忘却曲線 | forgetting curve | 遺忘曲線 | curva del olvido | 망각 곡선 | đường cong lãng quên |
| キャッチ（撮って集める） | catch | 捕捉 | atrapar | 캐치 | bắt |
| 表示言語 | app language | 顯示語言 | idioma de la app | 앱 언어 | ngôn ngữ ứng dụng |
| 目標レベル | target level | 目標等級 | nivel objetivo | 목표 레벨 | trình độ mục tiêu |
| 囲んで切り抜き直す | Circle to cut out | 圈選重新去背 | Rodear para recortar de nuevo | 둘러서 다시 오려내기 | Khoanh để tách nền lại |
| 元の写真のまま | Use original photo | 使用原始照片 | Usar la foto original | 원본 사진 그대로 | Dùng ảnh gốc |
| ログイン / 新規登録 | Sign in / Sign up | 登入 / 註冊 | Iniciar sesión / Registrarse | 로그인 / 회원가입 | Đăng nhập / Đăng ký |
