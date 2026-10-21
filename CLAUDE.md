# CatchWords — オーナーの決定（作業する Claude へ）

作業を始める前に読む。ここに書いた決定は、オーナーが会話の中で決めたもの。変える時はオーナーに確かめる。

## iOS 版

- **品詞は出さない**（2026-10-20「品詞の欄消していいわ。このアプリ内の単語はすべて名詞だから」）。単語の頁の品詞の札と、
  報告の「品詞」の項目は外した（ブランチ `claude/ios-catchwords-bugs-nsaei3` の 9ea71fa）。品詞の訳・表示を足し直さない。
- **共通の表記は訳さない**（2026-10-20「TOCFLやnew, No.などはどの言語でも共通でいい」）: TOCFL・CEFR・JLPT と
  「TOCFL Level n」、「NEW」、番号の「No.」。言語の混ざりの点検で数えない（`docs/language-rules.md` の R25）。
- **手書き風のフォントは使わない**（2026-10-20）。どの言語もシステムのフォント。
- 表示言語は `ios/Localization/languages.json` の一覧だけが正（足し方は `docs/adding-a-display-language.md`）。
- **言語を混ぜない**（2026-10-20「決して言語が混ざらないようにして」）: 規則は `docs/language-rules.md`。共有の単語の行の
  意味・訳・解説は、その行の言語の印（`explain_lang`）の読者にだけ出す（R23）。
