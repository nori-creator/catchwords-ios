/**
 * **打った語が何語か**を、手元で安く見分ける（オーナー指示 2026-10-08「文字検索したときは…
 * ユーザーが検索したものが学習言語ならそのままシールをはがす場面に…母語で一対一の関係では
 * なく、複数の単語の候補がある場合は単語の候補を表示して」）。
 *
 * - `target` … 学習言語の語として打たれた（例: 台湾華語を学ぶ人が打った「貓」「麵包」）。
 *   候補を並べず、その語のまま剥がす札へ進む。
 * - `native` … 母語（日本語）や別の言語で打たれた。学習言語の語に直す（候補が割れたら選ばせる）。
 * - `ambiguous` … 漢字だけで、どちらとも言えない（「電車」「蓮藕」「猫」…）。判定は語を引く AI
 *   （`suggestWordCandidates` の `query_is_target`）に任せる。
 *
 * ## 台湾華語（`zh*`）の見分け方
 * 1. かなが1つでも在れば日本語。
 * 2. 漢字が1つも無ければ、学習言語ではない（英語などで打った）。
 * 3. **台湾の字にしか無い形**（「貓」「國」「麵」…日本の新字体とも簡体字とも違う）が在れば学習言語。
 * 4. **日本の新字体にしか無い形**（「駅」「気」「鉄」「猫」…）が在れば日本語。
 * 5. どちらも無ければ `ambiguous`。
 *
 * 字の表は `opencc-js`（台湾正体 ↔ 日本の新字体 ↔ 簡体）で作り、台湾でもふつうに使う字
 * （「台」「衛」「研」「真」…）を手で外した。表は判定の手がかりで、外れても AI が引き直す
 * （「target」と出た語でも、学習言語の見出しとして通らなければ使わない）。
 *
 * 外の世界に触れない（文字を見るだけ）。
 */
import { isTargetHeadword } from "./target-language";
import { JA_ONLY } from "./kanji-forms";

export type QueryLang = "target" | "native" | "ambiguous";

/** 台湾の字にしか無い形（新字体・簡体字のどちらとも違う）。 */
const TW_ONLY = new Set(
  "亂亙亞來俠傳僞價儉兒內兩剎劍劑勞勳勵勸勻區卻卽參吳啞啟單噓嚙嚴囑國圍圓圖團堯墮壓壘壞壯壽奧奬妝媯嫻孃學寢實寫寬寶將專對屆屬峽嶽巖帶廁廢廣廳彈彌彎彥徑從徵恆悅惡惱慘應懷戀戰戲戶挾搖摑擇擊擔據擴攝攪敘數斷晉晝曆曉會條棧榮樂樓樞樣橫檜檢櫻權歐歡歲歷歸殘殼毆氣汙沒洩淚淨淺溈溫溼滯滿潀潑潛澀澤濕濟濤濱濾瀧瀨灣燈燒營爐爭爲牀犧狀狹獎獨獵獸獻產畫當疊癡發盜盡眞眾睪礪祕祿禪禮禰禱稅稱穎穩竈竊簷糉絕絲經綠緣縣縱總繡繩繪繫繼續纔纖缽羣聯聰聲聽肅脣脫腦腳膽臟臺與舉舊艷莊莖菸萊萬蒍蔣蔥藝藥蘆處虛號螢蟬蟲蠟蠶蠻裝裡覺覽觀觸說謠證譯譽讀變讓豐貓貳賣賴贊贗踐踴輕輛轉辭辯遙遞遲邊鄉鄰醫醬醱釀釋針銳鋪錄錢鍊鎭鐵鑄閱關隨險隱雙雜雞靈靜韁顎顏顯餘騷驅驗驛體髮鬥鯰鱉鷄鷗鹼鹽麥麪麴麵黃點黨齊齋齒齡龍龜",
);

const KANA = /[\u3040-\u309f\u30a0-\u30ff\u31f0-\u31ff\uff66-\uff9f]/u;
const HAN = /\p{Script=Han}/u;

/** 打った語が何語か（`QueryLang` の注）。 */
export function detectQueryLang(raw: string, targetLanguage: string): QueryLang {
  const text = (raw ?? "").trim();
  if (!text) return "native";
  if (!targetLanguage.startsWith("zh")) {
    // 英語などを学ぶ人: かな・漢字が在れば母語、学習言語の見出しとして通ればそのまま。
    if (KANA.test(text) || HAN.test(text)) return "native";
    return isTargetHeadword(text, targetLanguage) ? "target" : "ambiguous";
  }
  if (KANA.test(text)) return "native";
  if (!HAN.test(text) || !isTargetHeadword(text, targetLanguage)) return "native";
  let tw = false;
  let ja = false;
  for (const ch of text) {
    if (TW_ONLY.has(ch)) tw = true;
    else if (JA_ONLY.has(ch)) ja = true;
  }
  // 両方在る（「台湾の猫」を混ぜて打った等）は決めない。
  if (tw && !ja) return "target";
  if (ja && !tw) return "native";
  return "ambiguous";
}
