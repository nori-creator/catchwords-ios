/**
 * 学ぶ目的・好きなことの選択肢（値だけ）。
 *
 * **zod を読まない所に置く**（2026-10-03 最初の読み込みの監査）。ウェルカム画面の route は
 * `first-catch-images.ts` を最初に読み、それがこの一覧を使う。`learning-preferences.ts` は
 * 読み込んだ時点で zod の形を作るので、そこから読むと最初の画面が zod（約 25KB gz）まで
 * 読むことになっていた。形（`LearningPreferencesSchema`）は今までどおり
 * `learning-preferences.ts` にあり、この一覧を出し直している。
 */
export const FIRST_CATCH_GOALS = [
  "conversation",
  "travel",
  "work",
  "exams",
  "culture",
  "other",
] as const;
export const FIRST_CATCH_INTERESTS = [
  "food",
  "travel",
  "animals",
  "nature",
  "city",
  "fashion",
  "business",
  "music",
  "sports",
] as const;
