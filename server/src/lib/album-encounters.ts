import type { StickerWithWord } from "./stickers.functions";

/**
 * **再会の写真もホームのアルバムに貼る。**（オーナー指示 2026-09-23「再度同じ
 * 画像を撮った時も…ホームのアルバムにも追加して」）
 *
 * 再会の写真は `stickers` ではなく `encounters` の1行（1回の再会 = 1枚）。
 * アルバムは札を日ごとに並べるので、再会の1枚を**その日の札の写し**として
 * 足す（写真・時刻・場所だけ差し替える）。
 *
 * 写しの id は `元の札の id ~enc~ 再会の id`。押したら元の札の詳細を開き
 * （`baseStickerId`）、指で動かした置き方は保存しない（`isEncounterAlbumId`）—
 * 置き方の列は `stickers` の行にしか無いので、写しの id で書くと失敗する。
 */
export type AlbumEncounter = {
  id: string;
  sticker_id: string;
  created_at: string;
  location_name: string | null;
  lat: number | null;
  lng: number | null;
  image_url: string;
  thumb_url: string | null;
};

const SEP = "~enc~";

export function encounterAlbumId(stickerId: string, encounterId: string): string {
  return `${stickerId}${SEP}${encounterId}`;
}

export function isEncounterAlbumId(id: string): boolean {
  return id.includes(SEP);
}

export function baseStickerId(id: string): string {
  const i = id.indexOf(SEP);
  return i < 0 ? id : id.slice(0, i);
}

/** 札の一覧に、再会の写真の写しを足す（元の札が一覧に無い再会は足さない）。 */
export function mergeAlbumEncounters(
  items: readonly StickerWithWord[],
  encounters: readonly AlbumEncounter[] | undefined,
): StickerWithWord[] {
  if (!encounters?.length) return [...items];
  const byId = new Map(items.map((s) => [s.id, s]));
  const extra: StickerWithWord[] = [];
  for (const e of encounters) {
    const s = byId.get(e.sticker_id);
    if (!s || !e.image_url) continue;
    extra.push({
      ...s,
      id: encounterAlbumId(s.id, e.id),
      created_at: e.created_at,
      taken_at: e.created_at,
      object_url: e.image_url,
      object_thumb_url: e.thumb_url,
      cutout_url: null,
      cutout_thumb_url: null,
      selfie_url: null,
      // 再会の写真を主役にする（元の札で自撮りを主役に選んでいても）。
      hero_role: "object",
      caption: null,
      location_name: e.location_name,
      lat: e.lat,
      lng: e.lng,
      album_order: null,
      album_size: null,
      album_x: null,
      album_y: null,
      album_scale: null,
      album_rot: null,
    });
  }
  return [...items, ...extra];
}
