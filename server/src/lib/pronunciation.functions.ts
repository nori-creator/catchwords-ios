import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";
import {
  GetNativeProsodyInput,
  SaveNativeProsodyInput,
  nativeAudioPath,
  toRecordings,
  type NativeProsodyRecording,
  type NativeProsodyRow,
} from "./pronunciation";

/**
 * 発音コーチの「ネイティブの範囲」（数え方と約束は `pronunciation.ts`、設計は `docs/pronunciation-coach.md`）。
 *
 * - `getNativeProsody`: サインインした人なら誰でも。その語の録音と、同じ声調の並びの別の語の録音の**数値だけ**。
 *   表がまだ無い環境では失敗し、アプリは AI 音声を分析した仮の範囲を使う。
 * - `adminSaveNativeProsody` / `adminListNativeProsody`: 開発者だけ（ネイティブの録音を集める画面）。
 */

const TABLE = "native_prosody";
const BUCKET = "native-audio";
const COLUMNS = "speaker, headword, range_low, range_high, take";

async function requireAdmin(context: { supabase: unknown; userId: string }) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data, error } = await (context.supabase as any).rpc("has_role", {
    _user_id: context.userId,
    _role: "admin",
  });
  if (error) throw new Error(error.message);
  if (!data) throw new Error("Forbidden: admin role required");
}

export const getNativeProsody = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => GetNativeProsodyInput.parse(input ?? {}))
  .handler(async ({ data }): Promise<{ word: NativeProsodyRecording[]; pattern: NativeProsodyRecording[] }> => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const db = supabaseAdmin as any;
    const own = await db
      .from(TABLE)
      .select(COLUMNS)
      .eq("headword", data.headword)
      .eq("syllables", data.syllables)
      .order("created_at", { ascending: false })
      .limit(40);
    if (own.error) throw new Error(own.error.message);
    let same: { data: NativeProsodyRow[] | null; error: { message: string } | null } = { data: [], error: null };
    if (data.pattern) {
      same = await db
        .from(TABLE)
        .select(COLUMNS)
        .eq("pattern", data.pattern)
        .eq("syllables", data.syllables)
        .neq("headword", data.headword)
        .order("created_at", { ascending: false })
        .limit(60);
      if (same.error) throw new Error(same.error.message);
    }
    return {
      word: toRecordings(own.data as NativeProsodyRow[], data.syllables),
      pattern: toRecordings(same.data, data.syllables),
    };
  });

export const adminSaveNativeProsody = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => SaveNativeProsodyInput.parse(input))
  .handler(async ({ context, data }): Promise<{ ok: true; id: string }> => {
    await requireAdmin(context);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const db = supabaseAdmin as any;
    const id = crypto.randomUUID();
    let audioPath: string | null = null;
    if (data.audio_wav_base64) {
      const bytes = Uint8Array.from(atob(data.audio_wav_base64), (c) => c.charCodeAt(0));
      const path = nativeAudioPath(data.speaker, id);
      let { error } = await supabaseAdmin.storage.from(BUCKET).upload(path, bytes, { contentType: "audio/wav" });
      // バケットは移行で作るが、まだの環境ではここで作ってやり直す（非公開）。
      if (error && /not found|does not exist|bucket/i.test(error.message)) {
        await supabaseAdmin.storage.createBucket(BUCKET, { public: false }).catch(() => {});
        ({ error } = await supabaseAdmin.storage.from(BUCKET).upload(path, bytes, { contentType: "audio/wav" }));
      }
      if (error) throw new Error(error.message);
      audioPath = path;
    }
    const { error } = await db.from(TABLE).insert({
      id,
      speaker: data.speaker,
      gender: data.gender,
      headword: data.headword,
      zhuyin: data.zhuyin ?? null,
      pattern: data.pattern ?? null,
      syllables: data.take.syllables.length,
      range_low: data.range.low,
      range_high: data.range.high,
      take: data.take,
      audio_path: audioPath,
      consent_at: new Date().toISOString(),
      recorded_by: context.userId,
    });
    if (error) {
      if (audioPath) await supabaseAdmin.storage.from(BUCKET).remove([audioPath]).catch(() => {});
      throw new Error(error.message);
    }
    return { ok: true, id };
  });

const ListInput = z.object({ speaker: z.string().max(16).optional() });

/** 録音の数（語ごと・話者ごと）。録音する画面が「あと何人分」を出すため。 */
export const adminListNativeProsody = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .inputValidator((input: unknown) => ListInput.parse(input ?? {}))
  .handler(async ({ context }): Promise<{ counts: Array<{ headword: string; speaker: string; count: number }> }> => {
    await requireAdmin(context);
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const db = supabaseAdmin as any;
    const { data, error } = await db.from(TABLE).select("headword, speaker").limit(20_000);
    if (error) throw new Error(error.message);
    const counts = new Map<string, { headword: string; speaker: string; count: number }>();
    for (const r of (data ?? []) as Array<{ headword: string; speaker: string }>) {
      const key = `${r.headword}\u0000${r.speaker}`;
      const c = counts.get(key) ?? { headword: r.headword, speaker: r.speaker, count: 0 };
      c.count += 1;
      counts.set(key, c);
    }
    return { counts: [...counts.values()] };
  });
