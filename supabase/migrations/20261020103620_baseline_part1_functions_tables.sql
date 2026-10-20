-- CatchWords: the whole database schema, part 1 of 3 (2026-10-20). Types, functions, tables.
--
-- This project moved off Lovable Cloud. The 71 migrations in nori-creator/Lovable-catch-words-app
-- (supabase/migrations at 761faf4) were replayed on a scratch PostgreSQL by
-- supabase/tools/replay-migrations.sh and the result dumped into these three files. On a fresh project there is nothing
-- to drop or rewrite, so the file only creates. Compared with production on 2026-10-20: identical except
-- three changes the repository had and production had not run yet (stickers.album_hidden,
-- model_shadow_predictions, the newer apply_main_example_label) and the unused realtime channel policy
-- (the app does not use Supabase Realtime).

-- Function bodies refer to tables created further down; check them at call time, not here.
SET check_function_bodies = false;

CREATE TYPE public.app_role AS ENUM (
    'admin',
    'user'
);

CREATE FUNCTION public.apply_main_example_label(p_word_id uuid, p_explain_lang text, p_l1 text, p_sentence text, p_scene text, p_chunks jsonb, p_stale_chunks jsonb, p_drop text[], p_recount boolean, p_translation text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_rows integer := 0;
begin
  if p_word_id is null or coalesce(p_explain_lang, '') = '' or coalesce(btrim(p_sentence), '') = '' then
    raise exception 'apply_main_example_label: missing argument' using errcode = '22004';
  end if;
  -- 語のメインの例文がまだこの文か（書き終えるまで変えさせない）。
  perform 1
    from public.words
    where id = p_word_id and btrim(coalesce(example_sentence, '')) = btrim(p_sentence)
    for share;
  if not found then
    return false;
  end if;

  if p_l1 is null then
    update public.words w
      set extras = public.main_example_label_patch(
        w.extras, btrim(p_sentence), p_scene, p_chunks, p_stale_chunks, p_drop, p_recount)
      where w.id = p_word_id
        and w.source is distinct from 'verified'
        and coalesce(nullif(btrim(w.extras ->> 'explain_lang'), ''), 'ja') = p_explain_lang
        and (p_scene is null or public.main_example_label_writable(w.extras, p_sentence))
        and public.main_example_label_patch(
          w.extras, btrim(p_sentence), p_scene, p_chunks, p_stale_chunks, p_drop, p_recount)
          is distinct from w.extras;
  else
    update public.word_explanations e
      set extras = public.main_example_label_patch(
            e.extras, btrim(p_sentence), p_scene, p_chunks, p_stale_chunks, p_drop, p_recount),
          example_translation = case
            when coalesce(btrim(e.example_translation), '') = '' and coalesce(btrim(p_translation), '') <> ''
              then p_translation
            else e.example_translation
          end,
          updated_at = now()
      where e.word_id = p_word_id
        and e.explain_lang = p_explain_lang
        and e.l1 = p_l1
        and e.source is distinct from 'verified'
        and (p_scene is null or public.main_example_label_writable(e.extras, p_sentence))
        and public.main_example_label_patch(
          e.extras, btrim(p_sentence), p_scene, p_chunks, p_stale_chunks, p_drop, p_recount)
          is distinct from e.extras;
  end if;
  get diagnostics v_rows = row_count;
  return v_rows > 0;
end;
$$;

CREATE FUNCTION public.are_mutual_followers(_a uuid, _b uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.follows f1
    JOIN public.follows f2
      ON f1.follower_id = f2.following_id AND f1.following_id = f2.follower_id
    WHERE f1.follower_id = _a AND f1.following_id = _b
  );
$$;

CREATE FUNCTION public.bump_post_comment_count() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.posts SET comment_count = comment_count + 1 WHERE id = NEW.post_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.posts SET comment_count = GREATEST(comment_count - 1, 0) WHERE id = OLD.post_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END; $$;

CREATE FUNCTION public.bump_post_like_count() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.posts SET like_count = like_count + 1 WHERE id = NEW.post_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.posts SET like_count = GREATEST(like_count - 1, 0) WHERE id = OLD.post_id;
    RETURN OLD;
  END IF;
  RETURN NULL;
END; $$;

CREATE FUNCTION public.can_see_post(_post_id uuid, _user uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.posts p
    WHERE p.id = _post_id AND (
      p.user_id = _user
      OR p.visibility = 'public'
      OR (p.visibility = 'friends' AND public.are_mutual_followers(_user, p.user_id))
    )
  );
$$;

CREATE FUNCTION public.create_review_for_new_sticker() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO public.reviews (user_id, sticker_id, due_at)
  VALUES (NEW.user_id, NEW.id, now() + interval '10 minutes')
  ON CONFLICT (user_id, sticker_id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE FUNCTION public.enforce_words_source() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  new.source := 'ai';
  new.created_by := coalesce(auth.uid(), new.created_by);
  return new;
end;
$$;

CREATE FUNCTION public.get_leaderboard(_limit integer DEFAULT 20) RETURNS TABLE(user_id uuid, display_name text, avatar_url text, sticker_count bigint, post_count bigint, xp bigint)
    LANGUAGE sql STABLE
    SET search_path TO 'public'
    AS $$
  SELECT
    p.id AS user_id,
    p.display_name,
    p.avatar_url,
    COALESCE(sc.cnt, 0) AS sticker_count,
    COALESCE(pc.cnt, 0) AS post_count,
    (COALESCE(sc.cnt, 0) * 10 + COALESCE(pc.cnt, 0) * 5)::bigint AS xp
  FROM public.profiles p
  LEFT JOIN (
    SELECT user_id, COUNT(*) AS cnt FROM public.stickers GROUP BY user_id
  ) sc ON sc.user_id = p.id
  LEFT JOIN (
    SELECT user_id, COUNT(*) AS cnt FROM public.posts GROUP BY user_id
  ) pc ON pc.user_id = p.id
  ORDER BY xp DESC NULLS LAST
  LIMIT GREATEST(_limit, 1);
$$;

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    display_name text,
    avatar_url text,
    native_language text DEFAULT 'ja'::text NOT NULL,
    ui_language text DEFAULT 'ja'::text NOT NULL,
    target_language text DEFAULT 'zh-TW'::text NOT NULL,
    level_goal text DEFAULT 'TOCFL-2'::text NOT NULL,
    pronunciation_strictness text DEFAULT 'normal'::text NOT NULL,
    onboarded boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    album_bg text DEFAULT 'paper'::text NOT NULL,
    review_mode text DEFAULT 'speaking'::text NOT NULL,
    plan text DEFAULT 'free'::text NOT NULL,
    current_level text,
    review_daily_limit integer DEFAULT 20 NOT NULL,
    review_stage_focus text DEFAULT 'all'::text NOT NULL,
    CONSTRAINT profiles_plan_check CHECK ((plan = ANY (ARRAY['free'::text, 'pro'::text]))),
    CONSTRAINT profiles_review_daily_limit_range CHECK (((review_daily_limit >= 0) AND (review_daily_limit <= 200))),
    CONSTRAINT profiles_review_mode_valid CHECK ((review_mode = ANY (ARRAY['speaking'::text, 'choice'::text, 'hybrid'::text]))),
    CONSTRAINT profiles_review_stage_focus_valid CHECK ((review_stage_focus = ANY (ARRAY['all'::text, 'weak'::text, 'new'::text])))
);

CREATE FUNCTION public.get_my_profile() RETURNS public.profiles
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  SELECT p.*
  FROM public.profiles AS p
  WHERE p.id = auth.uid()
  LIMIT 1
$$;

CREATE FUNCTION public.guard_profile_plan() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
begin
  -- ブラウザ（PostgREST の authenticated / anon）からは plan を変えさせない。
  -- 変えられるのはサーバ（service_role の Stripe webhook）と管理者の SQL だけ。
  if current_user in ('authenticated', 'anon') then
    if tg_op = 'INSERT' then
      if new.plan is distinct from 'free' then
        raise exception 'profiles.plan is managed by the server' using errcode = '42501';
      end if;
    elsif new.plan is distinct from old.plan then
      raise exception 'profiles.plan is managed by the server' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO public.profiles (id, display_name, avatar_url)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    NEW.raw_user_meta_data->>'avatar_url'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END; $$;

CREATE FUNCTION public.has_role(_user_id uuid, _role public.app_role) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists (
    select 1 from public.user_roles
    where user_id = _user_id and role = _role
  )
$$;

CREATE FUNCTION public.main_example_label_patch(p_extras jsonb, p_sentence text, p_scene text, p_chunks jsonb, p_stale_chunks jsonb, p_drop text[], p_recount boolean) RETURNS jsonb
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO 'public'
    AS $$
declare
  e jsonb := case when jsonb_typeof(p_extras) = 'object' then p_extras else '{}'::jsonb end;
  kept jsonb;
begin
  if p_scene is not null then
    e := e || jsonb_build_object('example_scene', p_scene, 'example_scene_for', p_sentence);
  end if;
  if p_chunks is not null then
    e := e || jsonb_build_object('example_chunks', p_chunks);
  elsif p_stale_chunks is not null and e -> 'example_chunks' = p_stale_chunks then
    e := e || jsonb_build_object('example_chunks', '[]'::jsonb);
  end if;
  if coalesce(array_length(p_drop, 1), 0) > 0 and jsonb_typeof(e -> 'examples_extra') = 'array' then
    select coalesce(jsonb_agg(x order by i), '[]'::jsonb)
      into kept
      from jsonb_array_elements(e -> 'examples_extra') with ordinality as t(x, i)
      where not (coalesce(x ->> 'zh', '') = any (p_drop));
    e := e || jsonb_build_object('examples_extra', kept);
  end if;
  if coalesce(p_recount, false) then
    e := e || jsonb_build_object(
      'example_pattern_count',
      1 + case when jsonb_typeof(e -> 'examples_extra') = 'array'
               then jsonb_array_length(e -> 'examples_extra') else 0 end
    );
  end if;
  return e;
end;
$$;

CREATE FUNCTION public.main_example_label_writable(p_extras jsonb, p_sentence text) RETURNS boolean
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  select coalesce(btrim(p_extras ->> 'example_scene'), '') = ''
    or (
      coalesce(btrim(p_extras ->> 'example_scene_for'), '') <> ''
      and btrim(p_extras ->> 'example_scene_for') <> btrim(p_sentence)
    );
$$;

CREATE FUNCTION public.notify_on_comment() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE target uuid;
BEGIN
  SELECT user_id INTO target FROM public.posts WHERE id = NEW.post_id;
  IF target IS NOT NULL AND target <> NEW.user_id THEN
    INSERT INTO public.notifications (user_id, actor_id, type, post_id)
    VALUES (target, NEW.user_id, 'comment', NEW.post_id);
  END IF;
  RETURN NEW;
END; $$;

CREATE FUNCTION public.notify_on_follow() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  INSERT INTO public.notifications (user_id, actor_id, type)
  VALUES (NEW.following_id, NEW.follower_id, 'follow');
  RETURN NEW;
END; $$;

CREATE FUNCTION public.notify_on_like() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
DECLARE target uuid;
BEGIN
  SELECT user_id INTO target FROM public.posts WHERE id = NEW.post_id;
  IF target IS NOT NULL AND target <> NEW.user_id THEN
    INSERT INTO public.notifications (user_id, actor_id, type, post_id)
    VALUES (target, NEW.user_id, 'like', NEW.post_id);
  END IF;
  RETURN NEW;
END; $$;

CREATE FUNCTION public.preserve_post_counters() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
BEGIN
  -- Allow service_role to bypass (triggers use SECURITY DEFINER as table owner)
  NEW.like_count := OLD.like_count;
  NEW.comment_count := OLD.comment_count;
  RETURN NEW;
END;
$$;

CREATE FUNCTION public.reserve_usage_event(p_user_id uuid, p_kind text, p_limit integer, p_since timestamp with time zone) RETURNS bigint
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_count integer;
  v_id bigint;
begin
  if p_user_id is null or p_kind is null or p_limit is null or p_since is null then
    raise exception 'reserve_usage_event: missing argument' using errcode = '22004';
  end if;
  if p_limit <= 0 then
    return null;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('usage_events:' || p_user_id::text || ':' || p_kind, 0));
  select count(*) into v_count
    from public.usage_events
    where user_id = p_user_id and kind = p_kind and created_at >= p_since;
  if v_count >= p_limit then
    return null;
  end if;
  insert into public.usage_events (user_id, kind)
    values (p_user_id, p_kind)
    returning id into v_id;
  return v_id;
end;
$$;

CREATE FUNCTION public.save_album_layout(p_items jsonb) RETURNS integer
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_count integer;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '42501';
  end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then
    raise exception 'p_items must be a json array' using errcode = '22023';
  end if;
  if jsonb_array_length(p_items) > 500 then
    raise exception 'too many items' using errcode = '22023';
  end if;

  update public.stickers s
     set album_order = i.album_order,
         album_size = i.album_size,
         album_x = i.album_x,
         album_y = i.album_y,
         album_scale = i.album_scale,
         album_rot = i.album_rot
    from jsonb_to_recordset(p_items) as i(
      sticker_id uuid,
      album_order bigint,
      album_size text,
      album_x double precision,
      album_y double precision,
      album_scale double precision,
      album_rot double precision
    )
   where s.id = i.sticker_id
     and s.user_id = v_uid;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO 'public'
    AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE TABLE public.ai_consents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    version integer NOT NULL,
    agreed_at timestamp with time zone DEFAULT now() NOT NULL,
    revoked_at timestamp with time zone,
    source text DEFAULT 'web'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT ai_consents_source_check CHECK ((source = ANY (ARRAY['web'::text, 'ios'::text, 'guest'::text]))),
    CONSTRAINT ai_consents_version_check CHECK ((version >= 1))
);

CREATE TABLE public.ai_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    loop text NOT NULL,
    iterations integer DEFAULT 1 NOT NULL,
    accepted integer DEFAULT 0 NOT NULL,
    tokens_in integer,
    tokens_out integer,
    meta jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.app_config (
    key text NOT NULL,
    value jsonb DEFAULT '{}'::jsonb NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid
);

CREATE TABLE public.apple_tokens (
    user_id uuid NOT NULL,
    token text NOT NULL,
    token_type text DEFAULT 'refresh_token'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    client_id text,
    CONSTRAINT apple_tokens_type_check CHECK ((token_type = ANY (ARRAY['refresh_token'::text, 'access_token'::text])))
);

ALTER TABLE ONLY public.apple_tokens FORCE ROW LEVEL SECURITY;

CREATE TABLE public.categories (
    key text NOT NULL,
    label_ja text NOT NULL,
    icon_emoji text DEFAULT '📦'::text NOT NULL,
    sort_order integer DEFAULT 100 NOT NULL
);

CREATE TABLE public.corpus_pairs (
    word_a text NOT NULL,
    word_b text NOT NULL,
    day date NOT NULL,
    source text DEFAULT 'news'::text NOT NULL,
    count integer DEFAULT 0 NOT NULL
);

CREATE TABLE public.corpus_stats (
    word text NOT NULL,
    day date NOT NULL,
    source text DEFAULT 'news'::text NOT NULL,
    count integer DEFAULT 0 NOT NULL
);

CREATE TABLE public.daily_quests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    quest_date date DEFAULT ((now() AT TIME ZONE 'Asia/Taipei'::text))::date NOT NULL,
    category_key text,
    target_word text NOT NULL,
    hint_ja text NOT NULL,
    reward_xp integer DEFAULT 20 NOT NULL,
    completed_at timestamp with time zone,
    sticker_id uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.dictionary_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    headword text NOT NULL,
    language text DEFAULT 'zh-TW'::text NOT NULL,
    zhuyin text,
    pinyin text,
    meaning_ja text,
    pos text,
    tocfl_level integer,
    taiwan_usage text,
    audio_path text,
    source text DEFAULT 'verified'::text NOT NULL,
    entry_type text DEFAULT 'word'::text NOT NULL,
    scene_tags text[],
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    reading_primary text,
    reading_alt text,
    meanings jsonb DEFAULT '{}'::jsonb NOT NULL,
    level_step integer,
    forms jsonb,
    freq_rank integer,
    exam_tags text[],
    usage_register text,
    CONSTRAINT dictionary_entries_entry_type_check CHECK ((entry_type = ANY (ARRAY['word'::text, 'phrase'::text]))),
    CONSTRAINT dictionary_entries_level_step_valid CHECK (((level_step IS NULL) OR ((level_step >= 1) AND (level_step <= 6)))),
    CONSTRAINT dictionary_entries_source_check CHECK ((source = ANY (ARRAY['verified'::text, 'ai'::text, 'dict'::text]))),
    CONSTRAINT dictionary_entries_taiwan_usage_check CHECK ((taiwan_usage = ANY (ARRAY['common'::text, 'written'::text, 'spoken'::text, 'rare'::text]))),
    CONSTRAINT dictionary_entries_usage_register_valid CHECK (((usage_register IS NULL) OR (usage_register = ANY (ARRAY['common'::text, 'written'::text, 'spoken'::text, 'rare'::text]))))
);

CREATE TABLE public.encounters (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    sticker_id uuid NOT NULL,
    user_id uuid NOT NULL,
    recalled boolean,
    lat double precision,
    lng double precision,
    location_name text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    image_path text,
    cutout_path text
);

CREATE TABLE public.entry_reports (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    headword text NOT NULL,
    kind text NOT NULL,
    note text DEFAULT ''::text NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    word_id uuid,
    item text,
    reporter_lang text,
    outcome text,
    outcome_at timestamp with time zone,
    notified_at timestamp with time zone,
    CONSTRAINT entry_reports_kind_check CHECK ((kind = ANY (ARRAY['pronunciation'::text, 'meaning'::text, 'pos'::text, 'other'::text]))),
    CONSTRAINT entry_reports_status_check CHECK ((status = ANY (ARRAY['open'::text, 'fixed'::text, 'needs_review'::text, 'resolved'::text, 'dismissed'::text])))
);

CREATE TABLE public.follows (
    follower_id uuid NOT NULL,
    following_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT follows_check CHECK ((follower_id <> following_id))
);

CREATE TABLE public.generated_cards (
    language text NOT NULL,
    headword text NOT NULL,
    explain_lang text DEFAULT ''::text NOT NULL,
    l1 text DEFAULT ''::text NOT NULL,
    kind text DEFAULT 'card'::text NOT NULL,
    card jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT generated_cards_kind_check CHECK ((kind = ANY (ARRAY['card'::text, 'candidate'::text])))
);

CREATE TABLE public.journal_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    entry_date date DEFAULT ((now() AT TIME ZONE 'Asia/Taipei'::text))::date NOT NULL,
    body_zh text,
    body_ja text,
    used_sticker_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL,
    model text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    user_draft text,
    correction text,
    feedback_ja text,
    native_phrases jsonb
);

CREATE TABLE public.lexicon_audits (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    entry_id uuid,
    headword text NOT NULL,
    source text NOT NULL,
    ok boolean NOT NULL,
    confidence real,
    suggestion jsonb,
    applied boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.model_shadow_predictions (
    id bigint NOT NULL,
    user_id uuid NOT NULL,
    sticker_id uuid,
    task text NOT NULL,
    model text NOT NULL,
    predicted real NOT NULL,
    baseline real,
    outcome boolean,
    meta jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT model_shadow_predictions_baseline_check CHECK (((baseline IS NULL) OR ((baseline >= (0)::double precision) AND (baseline <= (1)::double precision)))),
    CONSTRAINT model_shadow_predictions_predicted_check CHECK (((predicted >= (0)::double precision) AND (predicted <= (1)::double precision)))
);

ALTER TABLE public.model_shadow_predictions ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.model_shadow_predictions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);

CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    actor_id uuid,
    type text NOT NULL,
    post_id uuid,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT notifications_type_check CHECK ((type = ANY (ARRAY['like'::text, 'comment'::text, 'follow'::text])))
);

ALTER TABLE ONLY public.notifications REPLICA IDENTITY FULL;

CREATE TABLE public.post_comments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    post_id uuid NOT NULL,
    user_id uuid NOT NULL,
    body text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT post_comments_body_check CHECK (((length(body) >= 1) AND (length(body) <= 500)))
);

CREATE TABLE public.post_likes (
    post_id uuid NOT NULL,
    user_id uuid NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.posts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    sticker_id uuid,
    caption text,
    visibility text DEFAULT 'public'::text NOT NULL,
    like_count integer DEFAULT 0 NOT NULL,
    comment_count integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT posts_visibility_check CHECK ((visibility = ANY (ARRAY['private'::text, 'friends'::text, 'public'::text])))
);

CREATE TABLE public.review_choices (
    word_id uuid NOT NULL,
    distractors text[] DEFAULT '{}'::text[] NOT NULL,
    generated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.review_history (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    review_id uuid NOT NULL,
    sticker_id uuid NOT NULL,
    reviewed_at timestamp with time zone DEFAULT now() NOT NULL,
    score integer NOT NULL,
    correct boolean NOT NULL,
    blur_seen boolean DEFAULT false NOT NULL,
    response_ms integer DEFAULT 0 NOT NULL,
    interval_days_after integer NOT NULL,
    ease_after numeric NOT NULL,
    repetitions_after integer NOT NULL
);

CREATE TABLE public.reviews (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    sticker_id uuid NOT NULL,
    ease real DEFAULT 2.5 NOT NULL,
    interval_days integer DEFAULT 0 NOT NULL,
    repetitions integer DEFAULT 0 NOT NULL,
    last_score smallint,
    blur_seen boolean DEFAULT false NOT NULL,
    due_at timestamp with time zone DEFAULT now() NOT NULL,
    last_reviewed_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

CREATE TABLE public.scan_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    headword text NOT NULL,
    meaning_ja text,
    kind text NOT NULL,
    confidence numeric,
    tapped boolean DEFAULT false NOT NULL,
    caught boolean DEFAULT false NOT NULL,
    lat numeric,
    lng numeric,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    detect_ms integer,
    tap_to_audio_ms integer,
    CONSTRAINT scan_events_kind_check CHECK ((kind = ANY (ARRAY['object'::text, 'text'::text])))
);

CREATE TABLE public.self_improve_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    step text NOT NULL,
    ok boolean NOT NULL,
    detail jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

