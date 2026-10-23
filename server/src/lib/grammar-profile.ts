/**
 * 英語の**文法項目と級**（CEFR-J Grammar Profile）。
 *
 * オーナーが取得して渡してくれた（2026-08-25）。東京外大 投野研の成果物で、
 * **商用可・出典明記が条件**。出典は設定の「出典」の頁に出す。
 *
 * ## なぜ要るのか — 語彙だけでは級が決まらない
 * `dictionary_entries` の級は**語**の難しさ。だが例文や添削で問題になるのは
 * **文型**の難しさで、これは別物。`a/an` は A1.1 の最初に出てくるが、
 * `having been+過去分詞` は B2.2。同じ語を使った文でも、型が違えば
 * 読める人が変わる。
 *
 * CEFR-J Text Profile（文章の難しさを測る表）は入手できなかったので
 * （オーナー 2026-08-25「text profile はダウンロードできなかったから、なしで」）、
 * **その役目をここが部分的に肩代わりする** — B2 の型を使った例文を
 * A2 の人に出さない、という判断ができる。
 *
 * ## 級が範囲のものは、やさしいほうを採る
 * CEFR-J は `A1.1-A1.2` のように幅で示す項目がある（256項目のうち **104項目**）。
 * この app は段を1つしか持てないので、**やさしいほう**を採る。
 * 語彙で `alarm clock` を取りこぼしたのと同じ理由 — 難しいほうを採ると、
 * その項目が学習者の範囲から外れて一度も出てこなくなる。
 *
 * ## 段は4つまで
 * CEFR-J は A1〜B2 しか扱わない。C1/C2 の項目は**無い**。
 * `grammarAbove(4)` が空になるのはそのため（数え間違いではない）。
 *
 * ## 英語名は元データのまま（大文字）
 * `INDEFINITE ARTICLES` のような書き方は CEFR-J の表記そのもの。
 * **直さない** — 直すと出典と突き合わせられなくなる。
 *
 * 外の世界に触れるものをここに入れないこと。
 */

import { LEVEL_INDEXES, type LevelIndex } from "./level-scale";

export type GrammarItem = {
  /** CEFR-J の項目ID。出典と突き合わせるためにそのまま持つ。 */
  id: string;
  /** 平易な日本語名（`a/an+名詞`）。画面と解説に出す。 */
  ja: string;
  /** 英語名（CEFR-J の表記のまま）。 */
  en: string;
  /** 段（1=A1 / 2=A2 / 3=B1 / 4=B2）。範囲のものはやさしいほう。 */
  step: LevelIndex;
};

/**
 * CEFR-J の級の書き方（`A1.1` / `A1.1-A1.2`）から段を読む。
 *
 * **範囲はやさしいほう。** 上の注に理由がある。
 * 読めない書き方は `null`（でっち上げない）。
 */
export function grammarStepOf(level: string | null | undefined): LevelIndex | null {
  const first = (level ?? "").split("-")[0].trim().toUpperCase();
  const m = first.match(/^([AB])([12])/);
  if (!m) return null;
  const band = m[1] === "A" ? 0 : 1;
  return (band * 2 + Number(m[2])) as LevelIndex;
}

/** CEFR-J Grammar Profile の256項目（やさしい順）。 */
export const GRAMMAR_ITEMS: readonly GrammarItem[] = [
  { id: "1", ja: "I am ... (疑問文・否定文含む)", en: "I am", step: 1 },
  { id: "10", ja: "It is ... (疑問文・否定文含む)", en: "It is", step: 1 },
  { id: "101", ja: "動詞+to不定詞", en: "VERB to DO", step: 1 },
  { id: "103", ja: "動詞+目的語+to不定詞", en: "VERB OBJECT to DO", step: 1 },
  { id: "105", ja: "動詞-ing", en: "V-ING (not preceded by 'not')", step: 1 },
  { id: "11", ja: "this/that+名詞", en: "This/That N", step: 1 },
  { id: "110", ja: "前置詞+動詞-ing", en: "PREP+V-ING", step: 1 },
  { id: "112", ja: "動詞+動詞-ing", en: "VERB V-ING", step: 1 },
  {
    id: "117",
    ja: "肯定命令文 (一般動詞)",
    en: "IMPERATIVE: AFFIRMATIVE (lexical verbs)",
    step: 1,
  },
  {
    id: "117-1",
    ja: "否定命令文: Don't+一般動詞",
    en: "IMPERATIVE: AFFIRMATIVE (lexical verbs)",
    step: 1,
  },
  { id: "119", ja: "Please+動詞 (命令文)", en: "Please+INFINITIVE", step: 1 },
  { id: "119-1", ja: "Please+don't+動詞", en: "Please+don't/never+INFINITIVE", step: 1 },
  { id: "12", ja: "these/those+名詞", en: "These/Those N", step: 1 },
  { id: "120", ja: "let's+動詞", en: "let's (not followed by 'not')", step: 1 },
  { id: "122", ja: "助動詞: be going to", en: "MODAL/AUX: be going to", step: 1 },
  { id: "123", ja: "助動詞: can", en: "MODAL/AUX: can", step: 1 },
  { id: "13", ja: "a/an+名詞", en: "INDEFINITE ARTICLES", step: 1 },
  { id: "14", ja: "the+名詞", en: "DEFINITE ARTICLES", step: 1 },
  { id: "141", ja: "助動詞: will", en: "MODAL/AUX: will", step: 1 },
  { id: "142", ja: "助動詞: would", en: "MODAL/AUX: would", step: 1 },
  { id: "146", ja: "There is/are ...", en: "there+be", step: 1 },
  { id: "149", ja: "Here is/are ...", en: "here is/are", step: 1 },
  { id: "15", ja: "some/any+名詞", en: "DETERMINERS: some/any", step: 1 },
  { id: "150", ja: "and, but, or", en: "COORDINATING CONJUNCTIONS", step: 1 },
  { id: "152", ja: "動詞+that節", en: "V+that+CLAUSE", step: 1 },
  { id: "155", ja: "副詞節: when ...", en: "ADVERBIAL CLAUSE: when", step: 1 },
  { id: "156", ja: "副詞節: if", en: "ADVERBIAL CLAUSE: if", step: 1 },
  { id: "16", ja: "no+名詞", en: "DETERMINER: no", step: 1 },
  {
    id: "161",
    ja: "従属節(that/whether/when/if以外の主な従属接続詞)",
    en: "SUBORDINATE CLAUSE: after/albeit/although/because/before/despite/except/for/lest/like/once/since/so/than/though/till/unless/until/where/whereas/wheresoever/whether/while/whilst tagged as IN",
    step: 1,
  },
  {
    id: "162",
    ja: "従属接続詞thatの省略(hope・know・think)",
    en: "hope/know/think+CLAUSE (without 'that')",
    step: 1,
  },
  { id: "167", ja: "疑問詞+to不定詞", en: "WH-+to+INFINITIVE", step: 1 },
  { id: "168", ja: "現在分詞+名詞 (前置修飾)", en: "PREMODIFYING PRESENT PARTICIPLE", step: 1 },
  { id: "169", ja: "名詞+現在分詞 (後置修飾)", en: "POSTMODIFYING PRESENT PARTICIPLE", step: 1 },
  { id: "17", ja: "another+名詞", en: "DETERMINER: another", step: 1 },
  { id: "170", ja: "過去分詞+名詞 (前置修飾)", en: "PREMODIFYING PAST PARTICIPLE", step: 1 },
  { id: "171", ja: "名詞+過去分詞 (後置修飾)", en: "POSTMODIFYING PAST PARTICIPLE", step: 1 },
  {
    id: "172",
    ja: "関係代名詞: 主格(who/which/that)",
    en: "NOMINATIVE RELATIVE PRONOUN: who",
    step: 1,
  },
  {
    id: "173",
    ja: "関係代名詞: 主格(who/which/that)",
    en: "NOMINATIVE RELATIVE PRONOUN: which",
    step: 1,
  },
  {
    id: "174",
    ja: "関係代名詞: 主格(who/which/that)",
    en: "NOMINATIVE RELATIVE PRONOUN: that",
    step: 1,
  },
  {
    id: "179",
    ja: "関係代名詞: 目的格の省略",
    en: "ELLIPTICAL ACCUSATIVE RELATIVE PRONOUN",
    step: 1,
  },
  { id: "18", ja: "much+名詞", en: "much UNCOUNTABLE NOUN", step: 1 },
  { id: "183", ja: "関係代名詞: what", en: "COMPOUND RELATIVE PRONOUN: what", step: 1 },
  { id: "194", ja: "文型: 主語+動詞", en: "SENTENCE PATTERN: SUBJECT+V", step: 1 },
  { id: "196", ja: "文型: 主語+動詞+目的語", en: "SENTENCE PATTERN: SUBJECT+V+OBJECT", step: 1 },
  {
    id: "197",
    ja: "主語+動詞(give/pass/send/show/teach/tell)+間接目的語+直接目的語",
    en: "SENTENCE PATTERN: SUBJECT+GIVE/PASS/SEND/SHOW/TEACH/TELL+INDIRECT OBJECT+DIRECT OBJECT",
    step: 1,
  },
  {
    id: "198",
    ja: "主語+動詞(give/pass/send/show/teach/tell)+直接目的語+to+間接目的語",
    en: "SENTENCE PATTERN: SUBJECT+GIVE/PASS/SEND/SHOW/TEACH/TELL+DIRECT OBJECT+to+INDIRECT OBJECT",
    step: 1,
  },
  { id: "2", ja: "You are ... (疑問文・否定文含む)", en: "You are", step: 1 },
  {
    id: "200",
    ja: "間接話法(say/explain/report)",
    en: "INDIRECT SPEECH: SAY/EXPLAIN/REPORT",
    step: 1,
  },
  {
    id: "202",
    ja: "間接疑問(decide/explain/know/learn/see/understand/wonder)",
    en: "INDIRECT QUESTION: DECIDE/EXPLAIN/KNOW/LEARN/SEE/UNDERSTAND/WONDER",
    step: 1,
  },
  { id: "21", ja: "前置詞", en: "PREPOSITIONS", step: 1 },
  {
    id: "22",
    ja: "mine/ours/yours/his/hers/theirs",
    en: "POSSESSIVE PRONOUNS (except for 'his' and 'its')",
    step: 1,
  },
  { id: "235", ja: "WH-疑問文: Why ...?", en: "WH- QUESTION: Why ...?", step: 1 },
  { id: "236", ja: "WH-疑問文: When ...?", en: "WH- QUESTION: When ...?", step: 1 },
  { id: "237", ja: "WH-疑問文: Who ...?", en: "WH- QUESTION: Who ...?", step: 1 },
  { id: "239", ja: "WH-疑問文: What ...?", en: "WH- QUESTION: What ...?", step: 1 },
  {
    id: "24",
    ja: "something/anything/someone/anyone/somebody/anybody",
    en: "INDEFINITE PRONOUNS",
    step: 1,
  },
  { id: "240", ja: "WH-疑問文: What+名詞 ...?", en: "WH- QUESTION: What N ...?", step: 1 },
  { id: "241", ja: "WH-疑問文: Which ...?", en: "WH- QUESTION: Which ...?", step: 1 },
  { id: "242", ja: "WH-疑問文: Which+名詞 ...?", en: "WH- QUESTION: Which N ...?", step: 1 },
  { id: "245", ja: "WH-疑問文: Where ...?", en: "WH- QUESTION: Where ...?", step: 1 },
  { id: "246", ja: "WH-疑問文: How ...?", en: "WH- QUESTION: How ...?", step: 1 },
  {
    id: "247",
    ja: "WH-疑問文: How+形容詞/副詞 ...?",
    en: "WH- QUESTION: How ADJ/ADV ...?",
    step: 1,
  },
  { id: "249", ja: "Can you ...?", en: "FUNCTIONAL QUESTION: Can you ...?", step: 1 },
  {
    id: "25",
    ja: "one/ones",
    en: "INDEFINITE PRONOUN/PROP-WORDS: ones (except for 'one')",
    step: 1,
  },
  { id: "252", ja: "Would you ...?", en: "FUNCTIONAL QUESTION: Would you ...?", step: 1 },
  { id: "253", ja: "Can I ...?", en: "FUNCTIONAL QUESTION: Can I ...?", step: 1 },
  { id: "262", ja: "How about ...?", en: "FUNCTIONAL QUESTION: How about ...?", step: 1 },
  { id: "263", ja: "What about ...?", en: "FUNCTIONAL QUESTION: What about ...?", step: 1 },
  { id: "3", ja: "He/She is ... (疑問文・否定文含む)", en: "he/she is", step: 1 },
  {
    id: "32",
    ja: "always/usually/often/sometimes/hardly/never",
    en: "ADVERBS OF FREQUENCY: always/usually/often/frequently/occasionally/sometimes/rarely",
    step: 1,
  },
  {
    id: "33",
    ja: "very/really/absolutely/completely/extremely/rather/pretty/quite/slightly/a bit/etc.",
    en: "ADVERBS: INTENSIFIERS: extremely/greatly/really/so/terribly/too/unbelievably/very",
    step: 1,
  },
  { id: "35", ja: "never/hardly/seldom/scarcely", en: "ADVERBS OF NEGATION: never", step: 1 },
  {
    id: "38",
    ja: "形容詞・副詞-er than ...",
    en: "COMPARATIVE OF SUPERIORITY: -er and irregular forms",
    step: 1,
  },
  { id: "4", ja: "We are ... (疑問文・否定文含む)", en: "we are", step: 1 },
  {
    id: "40",
    ja: "形容詞・副詞+-est",
    en: "SUPERLATIVE OF SUPERIORITY: -est and irregular forms",
    step: 1,
  },
  { id: "5", ja: "They are ... (疑問文・否定文含む)", en: "they are", step: 1 },
  { id: "55", ja: "句動詞", en: "PHRASAL VERBS (V+PARTICLE)", step: 1 },
  {
    id: "57",
    ja: "句動詞: 動詞+パーティクル+前置詞+目的語",
    en: "PHRASAL VERBS (V+PARTICLE+PREP+NP)",
    step: 1,
  },
  { id: "58", ja: "現在時制 (be動詞)", en: "TENSE/ASPECT: PRESENT (BE)", step: 1 },
  { id: "59", ja: "現在時制 (一般動詞)", en: "TENSE/ASPECT: PRESENT (lexical verbs)", step: 1 },
  {
    id: "6",
    ja: "my/our/your/his/her/its/their+名詞",
    en: "my/our/your/her/their (except for 'his' and 'its')",
    step: 1,
  },
  {
    id: "60",
    ja: "現在時制 (一般動詞・3人称単数)",
    en: "TENSE/ASPECT: PRESENT (lexical verbs; third person & singular)",
    step: 1,
  },
  { id: "61", ja: "現在進行形", en: "TENSE/ASPECT: PRESENT PROGRESSIVE", step: 1 },
  { id: "64", ja: "過去形 (be動詞)", en: "TENSE/ASPECT: PAST (BE)", step: 1 },
  { id: "65", ja: "過去形 (一般動詞)", en: "TENSE/ASPECT: PRESENT (lexical verbs)", step: 1 },
  { id: "69", ja: "未来形", en: "TENSE/ASPECT: FUTURE", step: 1 },
  {
    id: "7",
    ja: "me/you/us/him/her/them",
    en: "me/us/him/her/them (except for 'you' and 'it')",
    step: 1,
  },
  { id: "73", ja: "受動態 (現在形)", en: "PASSIVE: PRESENT", step: 1 },
  { id: "76", ja: "受動態 (過去形)", en: "PASSIVE: PAST", step: 1 },
  { id: "8", ja: "This/That is ... (疑問文・否定文含む)", en: "This/That is", step: 1 },
  { id: "87", ja: "get+過去分詞", en: "GET+PAST PARTICIPLE", step: 1 },
  {
    id: "88",
    ja: "to+動詞の原形 (不定詞)",
    en: "TO-INFINITIVE: to DO (not preceded by 'not')",
    step: 1,
  },
  { id: "9", ja: "These/Those are ... (疑問文・否定文含む)", en: "These/Those are", step: 1 },
  { id: "114", ja: "動詞+目的語+-ing", en: "VERB OBJECT V-ING", step: 2 },
  { id: "118", ja: "Do+命令文", en: "Do+IMPERATIVE", step: 2 },
  { id: "120-1", ja: "let's not+動詞", en: "let's not", step: 2 },
  { id: "121", ja: "助動詞: be able to", en: "MODAL/AUX: be able to", step: 2 },
  { id: "124", ja: "助動詞: could", en: "MODAL/AUX: could", step: 2 },
  { id: "127", ja: "助動詞: have to", en: "MODAL/AUX: have to", step: 2 },
  { id: "132", ja: "助動詞: might", en: "MODAL/AUX: might", step: 2 },
  { id: "135", ja: "助動詞: must", en: "MODAL/AUX: must", step: 2 },
  { id: "136", ja: "助動詞: need (to)", en: "MODAL/AUX: need (to)", step: 2 },
  { id: "138", ja: "助動詞: shall", en: "MODAL/AUX: shall", step: 2 },
  { id: "139", ja: "助動詞: should", en: "MODAL/AUX: should", step: 2 },
  { id: "144", ja: "助動詞+be 動詞ing", en: "AUX+PROGRESSIVE", step: 2 },
  { id: "148", ja: "There+助動詞+be ...", en: "there+AUX+be", step: 2 },
  {
    id: "153",
    ja: "know/wonder+WH-(節) (whetherは除く)",
    en: "know/wonder+WH-(CLAUSE) (except for 'whether')",
    step: 2,
  },
  { id: "157", ja: "副詞節: as ...", en: "ADVERBIAL CLAUSE: as", step: 2 },
  { id: "158", ja: "副詞節: as soon as ...", en: "ADVERBIAL CLAUSE: as soon as", step: 2 },
  { id: "163", ja: "形式主語it+to不定詞", en: "it+BE(+ADV)+ADJ(+for+NP)+to+INFINITIVE", step: 2 },
  {
    id: "175",
    ja: "関係代名詞: 目的格(who/whom/which)",
    en: "ACCUSATIVE RELATIVE PRONOUN: who",
    step: 2,
  },
  {
    id: "176",
    ja: "関係代名詞: 目的格(who/whom/which)",
    en: "ACCUSATIVE RELATIVE PRONOUN: whom",
    step: 2,
  },
  {
    id: "177",
    ja: "関係代名詞: 目的格(who/whom/which)",
    en: "ACCUSATIVE RELATIVE PRONOUN: which",
    step: 2,
  },
  {
    id: "178",
    ja: "関係代名詞: 目的格(who/whom/which)",
    en: "ACCUSATIVE RELATIVE PRONOUN: that",
    step: 2,
  },
  { id: "185", ja: "関係副詞 (先行詞あり)", en: "RELATIVE ADVERB: WITH ANTECEDENT", step: 2 },
  { id: "19", ja: "(a) little+名詞", en: "little UNCOUNTABLE NOUN", step: 2 },
  { id: "190", ja: "感嘆文: How+形容詞・副詞 ...!", en: "EXCLAMATION: How ADJ/ADV ...!", step: 2 },
  { id: "192", ja: "感嘆文: What+名詞 ...!", en: "EXCLAMATION: What ...!", step: 2 },
  {
    id: "195",
    ja: "主語+動詞(become/feel/go/look/seem/sound)+補語(形容詞)",
    en: "SENTENCE PATTERN: SUBJECT+BECOME/FEEL/GO/LOOK/SEEM/SOUND+COMPLEMENT (ADJ)",
    step: 2,
  },
  {
    id: "199",
    ja: "主語+動詞(make)+目的語+補語(形容詞)",
    en: "SENTENCE PATTERN: SUBJECT+MAKE+OBJECT+COMPLEMENT (ADJ)",
    step: 2,
  },
  { id: "20", ja: "(a) few+名詞", en: "few PLURAL NOUN", step: 2 },
  { id: "201", ja: "間接話法(tell)", en: "INDIRECT SPEECH: TELL", step: 2 },
  {
    id: "203",
    ja: "間接疑問(ask/remind/show/teach/tell)",
    en: "INDIRECT QUESTION: ASK/REMIND/SHOW/TEACH/TELL",
    step: 2,
  },
  { id: "206", ja: "使役構文(make/have/let)", en: "HAVE/LET/MAKE+NP+INFINITIVE", step: 2 },
  { id: "209", ja: "ask/tell+目的語+to+動詞", en: "ASK/TELL+NP+to+INFINITIVE", step: 2 },
  {
    id: "23",
    ja: "myself/yourself/himself/herself/ourselves/themselves",
    en: "REFLEXIVE PRONOUNS",
    step: 2,
  },
  { id: "243", ja: "WH-疑問文: Whose ...?", en: "WH- QUESTION: Whose ...?", step: 2 },
  { id: "244", ja: "WH-疑問文: Whose 名詞 ...?", en: "WH- QUESTION: Whose N ...?", step: 2 },
  {
    id: "248",
    ja: "WH-疑問文: 前置詞+what/which/whom/whose ...?",
    en: "WH- QUESTION: PREP what/which/whom/whose ...?",
    step: 2,
  },
  { id: "249-1", ja: "Can't you ...?", en: "FUNCTIONAL QUESTION: Can't you ...?", step: 2 },
  { id: "250", ja: "Could you ...?", en: "FUNCTIONAL QUESTION: Could you ...?", step: 2 },
  { id: "251", ja: "Will you ...?", en: "FUNCTIONAL QUESTION: Will you ...?", step: 2 },
  { id: "251-1", ja: "Won't you ...?", en: "FUNCTIONAL QUESTION: Won't you ...?", step: 2 },
  { id: "254", ja: "Could I ...?", en: "FUNCTIONAL QUESTION: Could I ...?", step: 2 },
  { id: "256", ja: "Shall I ...?", en: "FUNCTIONAL QUESTION: Shall I ...?", step: 2 },
  { id: "257", ja: "Shall we ...?", en: "FUNCTIONAL QUESTION: Shall we ...?", step: 2 },
  { id: "258", ja: "Should I ...?", en: "FUNCTIONAL QUESTION: Should I ...?", step: 2 },
  { id: "259", ja: "Why don't you ...?", en: "FUNCTIONAL QUESTION: Why don't you ...?", step: 2 },
  { id: "26", ja: "none", en: "INDEFINITE PRONOUN: none", step: 2 },
  { id: "260", ja: "Why don't we ...?", en: "FUNCTIONAL QUESTION: Why don't we ...?", step: 2 },
  { id: "261", ja: "Why not ...?", en: "FUNCTIONAL QUESTION: Why not ...?", step: 2 },
  { id: "31", ja: "something+形容詞", en: "-thing ADJ", step: 2 },
  {
    id: "34",
    ja: "fortunately/unfortunately/clearly/frankly/hopefully/obviously/surprisingly/apparently/etc.",
    en: "ADVERBS OF ATTITUDES: apparently/clearly/fortunately/frankly/unfortunately",
    step: 2,
  },
  { id: "37", ja: "as ... as (肯定文・疑問文)", en: "COMPARISON OF EQUALITY: as ... as", step: 2 },
  {
    id: "37-1",
    ja: "not as ... as (否定文)",
    en: "COMPARISON OF EQUALITY: not as/so ... as",
    step: 2,
  },
  {
    id: "39",
    ja: "more+形容詞・副詞 than ...",
    en: "COMPARATIVE OF SUPERIORITY: more+ADJ/ADV",
    step: 2,
  },
  { id: "41", ja: "most+形容詞・副詞", en: "SUPERLATIVE OF SUPERIORITY: most+ADJ/ADV", step: 2 },
  {
    id: "56",
    ja: "句動詞: 動詞+目的語+パーティクル)",
    en: "PHRASAL VERBS (V+NP+PARTICLE)",
    step: 2,
  },
  { id: "62", ja: "現在完了形", en: "TENSE/ASPECT: PRESENT PERFECT", step: 2 },
  { id: "66", ja: "過去進行形", en: "TENSE/ASPECT: PAST PROGRESSIVE", step: 2 },
  { id: "70", ja: "未来進行形", en: "TENSE/ASPECT: FUTURE PROGRESSIVE", step: 2 },
  {
    id: "93",
    ja: "for 名詞 to+動詞の原形(意味上の主語)",
    en: "TO-INFINITIVE: WITH NOTIONAL SUBJECT",
    step: 2,
  },
  { id: "102", ja: "動詞 not to不定詞", en: "VERB not to DO", step: 3 },
  { id: "108", ja: "being + 過去分詞", en: "being+PAST PARTICIPLE", step: 3 },
  { id: "116", ja: "命令文 (BE)", en: "IMPERATIVE (BE)", step: 3 },
  { id: "126", ja: "助動詞: had better", en: "MODAL/AUX: had better", step: 3 },
  { id: "128", ja: "助動詞: (have) got to", en: "MODAL/AUX: (have) got to", step: 3 },
  { id: "129", ja: "助動詞: may", en: "MODAL/AUX: may", step: 3 },
  { id: "133", ja: "助動詞: might as well", en: "MODAL/AUX: might as well", step: 3 },
  { id: "137", ja: "助動詞: ought to", en: "MODAL/AUX: ought to", step: 3 },
  { id: "140", ja: "助動詞: used to", en: "MODAL/AUX: used to", step: 3 },
  { id: "143", ja: "助動詞: would rather", en: "MODAL/AUX: would rather", step: 3 },
  { id: "145", ja: "助動詞 + have + 過去分詞", en: "AUX+PERFECT", step: 3 },
  { id: "147", ja: "There have+過去分詞", en: "there+have/has+been", step: 3 },
  { id: "151", ja: "the fact(s) that節", en: "the fact(s) that+CLAUSE", step: 3 },
  { id: "154", ja: "whether節", en: "whether", step: 3 },
  { id: "159", ja: "副詞節: by the time ...", en: "ADVERBIAL CLAUSE: by the time", step: 3 },
  { id: "160", ja: "副詞節: so that ...", en: "ADVERBIAL CLAUSE: so that", step: 3 },
  { id: "164", ja: "形式目的語 it + to不定詞", en: "V+it+ADJ(+for+NP)+to+INFINITIVE", step: 3 },
  { id: "165", ja: "形式主語it + that節", en: "it+BE(+ADV)+ADJ+that+CLAUSE", step: 3 },
  { id: "166", ja: "形式目的語 it + that節", en: "V+it+ADJ(+for+NP)+that+CLAUSE", step: 3 },
  { id: "180", ja: "関係代名詞　所有格(whose)", en: "GENITIVE RELATIVE PRONOUN", step: 3 },
  { id: "181", ja: "関係代名詞　非制限用法", en: "RELATIVE PRONOUN: NONRESTRICTIVE", step: 3 },
  { id: "184", ja: "前置詞+関係代名詞", en: "PREP+RELATIVE PRONOUN", step: 3 },
  { id: "186", ja: "関係副詞(先行詞なし)", en: "RELATIVE ADVERB: WITHOUT ANTECEDENT", step: 3 },
  { id: "187", ja: "関係副詞(非制限用法)", en: "RELATIVE ADVERB: NONRESTRICTIVE", step: 3 },
  { id: "188", ja: "whatever/whoever/wherever/however", en: "WH-EVER", step: 3 },
  { id: "189", ja: "関係節の前置詞残留", en: "PREPOSITION STRANDING", step: 3 },
  {
    id: "193",
    ja: "付加疑問(肯定文に続くもの)",
    en: "TAG QUESTION: FOLLOWING AFFIRMATIVE SENTENCE",
    step: 3,
  },
  {
    id: "193-1",
    ja: "付加疑問(否定文に続くもの)",
    en: "TAG QUESTION: FOLLOWING NEGATIVE SENTENCE",
    step: 3,
  },
  { id: "207", ja: "have/get + 目的語 + 過去分詞", en: "HAVE/GET+NP+PAST PARTICIPLE", step: 3 },
  { id: "208", ja: "get + 目的語 + 現在分詞", en: "GET+NP+PRESENT PARTICIPLE", step: 3 },
  { id: "210", ja: "see/hear/etc.+目的語+原形不定詞", en: "FEEL/HEAR/SEE+NP+INFINITIVE", step: 3 },
  {
    id: "211",
    ja: "see/hear/etc.+目的語+現在分詞",
    en: "FEEL/HEAR/SEE+NP+PRESENT PARTICIPLE",
    step: 3,
  },
  {
    id: "213",
    ja: "分詞構文(現在分詞・文頭)",
    en: "PARTICIPIAL CONSTRUCTION: PRESENT PARTICIPLE",
    step: 3,
  },
  { id: "215", ja: "仮定法過去(if節内動詞が過去)", en: "CONDITIONAL: SECOND", step: 3 },
  { id: "216", ja: "仮定法過去完了(if節内動詞が過去完了)", en: "CONDITIONAL: THIRD", step: 3 },
  {
    id: "217",
    ja: "仮定法現在(that節内動詞が原形不定詞)",
    en: "DEMAND/INSIST/ORDER/PROPOSE/RECOMMEND/REQUIRE/SUGGEST+NP+INFINITIVE",
    step: 3,
  },
  { id: "218", ja: "wish+仮定法過去", en: "WISH+SECOND CONDITIONAL", step: 3 },
  { id: "220", ja: "as if/as though + 仮定法過去", en: "AS IF/THOUGH+SECOND CONDITIONAL", step: 3 },
  {
    id: "232",
    ja: "倒置(so + be/have/do/助動詞 +人称代名詞)",
    en: "INVERSION: so+BE/HAVE/DO/AUX+PERSONAL PRON",
    step: 3,
  },
  {
    id: "233",
    ja: "倒置(neither/nor + be/have/do/助動詞 + 人称代名詞)",
    en: "INVERSION: neither/nor+BE/HAVE/DO/AUX+PERSONAL PRON",
    step: 3,
  },
  {
    id: "234",
    ja: "倒置(Never/No sooner/Hardly/Little/Scarcely/Seldom ....)",
    en: "INVERSION: Hardly/Little/Never/No sooner/Scarcely/Seldom ....",
    step: 3,
  },
  { id: "250-1", ja: "Couldn't you ...?", en: "FUNCTIONAL QUESTION: Couldn't you ...?", step: 3 },
  { id: "252-1", ja: "Wouldn't you ...?", en: "FUNCTIONAL QUESTION: Wouldn't you ...?", step: 3 },
  { id: "255", ja: "May I ...?", en: "FUNCTIONAL QUESTION: May I ...?", step: 3 },
  { id: "27", ja: "each other", en: "RECIPROCAL PRONOUN: each other", step: 3 },
  { id: "28", ja: "one another", en: "RECIPROCAL PRONOUN: one another", step: 3 },
  { id: "29", ja: "others", en: "PRONOUN: others (excluding 'the others')", step: 3 },
  { id: "30", ja: "the other/the others", en: "PRONOUNS: the other/others", step: 3 },
  { id: "42", ja: "less+形容詞・副詞", en: "COMPARATIVE/SUPERLATIVE OF INFERIORITY", step: 3 },
  { id: "43", ja: "形容詞・副詞+enough", en: "ADJ/ADV enough (except for 'not enough')", step: 3 },
  { id: "44", ja: "too 形容詞・副詞 to 動詞", en: "too ADJ/ADV to+INFINITIVE", step: 3 },
  { id: "45", ja: "so 形容詞・副詞+(that)節", en: "so ADJ/ADV (that) CLAUSE", step: 3 },
  { id: "46", ja: "such (a/an) 形容詞+名詞", en: "such (a/an) ADJ NOUN", step: 3 },
  {
    id: "49",
    ja: "比較級 and 比較級",
    en: "COMPARATIVE and COMPARATIVE (the same adjective)",
    step: 3,
  },
  {
    id: "51",
    ja: "even/much/far+比較級",
    en: "INTENSIFIED COMPARATIVES: a lot/by far/even/far/much/still",
    step: 3,
  },
  { id: "53", ja: "do/does+動詞原形", en: "do/does DO", step: 3 },
  { id: "54", ja: "did+動詞原形", en: "did DO", step: 3 },
  { id: "63", ja: "現在完了進行形", en: "TENSE/ASPECT: PRESENT PERFECT PROGRESSIVE", step: 3 },
  { id: "67", ja: "過去完了形", en: "TENSE/ASPECT: PAST PERFECT", step: 3 },
  { id: "68", ja: "had been 動詞ing", en: "TENSE/ASPECT: PAST PERFECT PROGRESSIVE", step: 3 },
  { id: "71", ja: "will have 過去分詞", en: "TENSE/ASPECT: FUTURE PERFECT", step: 3 },
  {
    id: "74",
    ja: "受動態(現在進行形): is being+過去分詞",
    en: "PASSIVE: PRESENT PROGRESSIVE",
    step: 3,
  },
  { id: "79", ja: "受動態(未来形)", en: "PASSIVE: FUTURE", step: 3 },
  { id: "82", ja: "受動態(助動詞+受動態)", en: "PASSIVE: AUX", step: 3 },
  { id: "89", ja: "not to不定詞", en: "TO-INFINITIVE: not to DO", step: 3 },
  { id: "95", ja: "in order to不定詞", en: "in order to DO", step: 3 },
  { id: "99", ja: "be to不定詞", en: "be to DO", step: 3 },
  { id: "100", ja: "be about to不定詞", en: "be about to DO", step: 4 },
  { id: "104", ja: "動詞 + 目的語 not to不定詞", en: "VERB OBJECT not to DO", step: 4 },
  { id: "106", ja: "not+ -ing (be going to は除く)", en: "not+V-ING", step: 4 },
  { id: "107", ja: "having + 過去分詞", en: "having+PAST PARTICIPLE", step: 4 },
  { id: "109", ja: "having been+過去分詞", en: "having been+PAST PARTICIPLE", step: 4 },
  {
    id: "111",
    ja: "所有格+ 動詞-ing",
    en: "V-ING: WITH NOTIONAL SUBJECT (expressed as possessive pronouns)",
    step: 4,
  },
  { id: "113", ja: "動詞+ not+ 動詞-ing", en: "VERB not V-ING", step: 4 },
  { id: "125", ja: "助動詞: dare (to)", en: "MODAL/AUX: dare (to)", step: 4 },
  { id: "131", ja: "助動詞: may well", en: "MODAL/AUX: may well", step: 4 },
  { id: "134", ja: "助動詞: might well", en: "MODAL/AUX: might well", step: 4 },
  { id: "182", ja: "疑似関係代名詞(as)", en: "PSEUDO RELATIVE PRONOUN: as", step: 4 },
  {
    id: "204",
    ja: "強調構文(前置詞句・副詞強調)",
    en: "CLEFT SENTENCE FOCUSING ON PREPOSITIONAL PHRASE/ADVERB",
    step: 4,
  },
  { id: "205", ja: "強調構文(whatを用いた疑似分裂文)", en: "PSEUDO-CLEFT SENTENCE: WHAT", step: 4 },
  {
    id: "212",
    ja: "see/hear/etc.+目的語+過去分詞",
    en: "FEEL/HEAR/SEE+NP+PAST PARTICIPLE",
    step: 4,
  },
  {
    id: "214",
    ja: "分詞構文(過去分詞・文頭)",
    en: "PARTICIPIAL CONSTRUCTION: PAST PARTICIPLE",
    step: 4,
  },
  { id: "219", ja: "wish+仮定法過去完了", en: "WISH+THIRD CONDITIONAL", step: 4 },
  {
    id: "221",
    ja: "as if/as though + 仮定法過去完了",
    en: "AS IF/THOUGH+THIRD CONDITIONAL",
    step: 4,
  },
  { id: "222", ja: "if only+仮定法過去", en: "IF ONLY+SECOND CONDITIONAL", step: 4 },
  { id: "223", ja: "if only+仮定法過去完了", en: "IF ONLY+THIRD CONDITIONAL", step: 4 },
  { id: "224", ja: "if節内のshould", en: "IF+SHOULD (e.g. if it should rain tomorrow)", step: 4 },
  { id: "228", ja: "if it were not for ...", en: "if it were not for ...", step: 4 },
  { id: "229", ja: "were it not for ...", en: "were it not for ...", step: 4 },
  { id: "230", ja: "if it hadn't been for ...", en: "if it hadn't been for ...", step: 4 },
  { id: "231", ja: "had it not been for ...", en: "had it not been for ...", step: 4 },
  {
    id: "50",
    ja: "the+比較級 (...), the+比較級",
    en: "the COMPARATIVE (...), the COMPARATIVE",
    step: 4,
  },
  { id: "72", ja: "未来完了進行形", en: "TENSE/ASPECT: FUTURE PERFECT PROGRESSIVE", step: 4 },
  {
    id: "75",
    ja: "受動態(現在完了形): have been+過去分詞",
    en: "PASSIVE: PRESENT PERFECT",
    step: 4,
  },
  {
    id: "77",
    ja: "受動態(過去進行形): was being+過去分詞",
    en: "PASSIVE: PAST PROGRESSIVE",
    step: 4,
  },
  { id: "78", ja: "受動態(過去完了形): had been+過去分詞", en: "PASSIVE: PAST PERFECT", step: 4 },
  {
    id: "81",
    ja: "受動態(未来完了形): will have been+過去分詞",
    en: "PASSIVE: FUTURE PERFECT",
    step: 4,
  },
  { id: "84", ja: "受動態(助動詞+完了形)", en: "PASSIVE: AUX+PERFECT", step: 4 },
  {
    id: "85",
    ja: "間接目的語 is given/passed/sent/showed/taught/told 直接目的語",
    en: "PASSIVE: INDIRECT OBJECTS OF GIVE/PASS/SEND/SHOW/TEACH/TELL AS SUBJECTS",
    step: 4,
  },
  {
    id: "86",
    ja: "直接目的語 is given/passed/sent/showed/taught/told to 間接目的語",
    en: "PASSIVE: DIRECT OBJECTS OF GIVE/PASS/SEND/SHOW/TEACH/TELL AS SUBJECTS",
    step: 4,
  },
  { id: "90", ja: "to have+過去分詞", en: "TO-INFINITIVE: to have DONE", step: 4 },
  { id: "91", ja: "to be+過去分詞", en: "TO-INFINITIVE: to be DONE", step: 4 },
  { id: "92", ja: "to have been+過去分詞", en: "TO-INFINITIVE: to have been DONE", step: 4 },
  { id: "97", ja: "so as to不定詞", en: "so as to DO", step: 4 },
];

/**
 * その級までに出てよい文法項目。
 *
 * 例文を作るとき・添削するときに「この人が読める型」を渡すのに使う。
 */
export function grammarAtOrBelow(step: number): GrammarItem[] {
  return GRAMMAR_ITEMS.filter((g) => g.step <= step);
}

/**
 * その級にはまだ早い文法項目。
 *
 * 日記の添削で「背伸びして使えている所」を見つけるのに使う。
 * **上の級の型を使っていたら直すのではなく、そこを認める。**
 *
 * CEFR-J は B2 までしか無いので、`grammarAbove(4)` は空。
 */
export function grammarAbove(step: number): GrammarItem[] {
  return GRAMMAR_ITEMS.filter((g) => g.step > step);
}

/** 段ごとの項目数。画面に「この級で何が増えるか」を出すのに使う。 */
export function grammarCountByStep(): Record<number, number> {
  const out: Record<number, number> = {};
  for (const i of LEVEL_INDEXES) out[i] = 0;
  for (const g of GRAMMAR_ITEMS) out[g.step] = (out[g.step] ?? 0) + 1;
  return out;
}
