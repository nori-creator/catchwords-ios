-- Minimal stand-ins for the Supabase-managed schemas (auth / storage / realtime) and roles, so the
-- repository's migrations can be replayed on a plain local PostgreSQL to compute the final schema.
-- Only used by tools/replay-migrations.sh; never applied to the hosted project.
do $$ declare r text; begin
  foreach r in array array['anon','authenticated','service_role','supabase_auth_admin','supabase_storage_admin'] loop
    if not exists (select 1 from pg_roles where rolname = r) then execute format('create role %I nologin', r); end if;
  end loop;
end $$;
alter role service_role bypassrls;
create schema auth; create schema storage; create schema realtime; create schema extensions;
create table auth.users (
  instance_id uuid, id uuid primary key, aud varchar, role varchar, email varchar, encrypted_password varchar,
  email_confirmed_at timestamptz, last_sign_in_at timestamptz, raw_app_meta_data jsonb, raw_user_meta_data jsonb,
  is_super_admin boolean, created_at timestamptz, updated_at timestamptz, phone text, confirmed_at timestamptz,
  banned_until timestamptz, is_sso_user boolean default false, deleted_at timestamptz, is_anonymous boolean default false);
create table auth.identities (id uuid primary key default gen_random_uuid(), provider_id text, user_id uuid references auth.users(id),
  identity_data jsonb, provider text, last_sign_in_at timestamptz, created_at timestamptz, updated_at timestamptz, email text);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create function auth.role() returns text language sql stable as $$ select current_setting('request.jwt.claim.role', true) $$;
create function auth.jwt() returns jsonb language sql stable as $$ select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
create function auth.email() returns text language sql stable as $$ select auth.jwt()->>'email' $$;
create table storage.buckets (id text primary key, name text not null, owner uuid, created_at timestamptz default now(),
  updated_at timestamptz default now(), public boolean default false, avif_autodetection boolean default false,
  file_size_limit bigint, allowed_mime_types text[], owner_id text);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets(id), name text,
  owner uuid, created_at timestamptz default now(), updated_at timestamptz default now(), last_accessed_at timestamptz,
  metadata jsonb, path_tokens text[], version text, owner_id text, user_metadata jsonb);
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language plpgsql immutable as $$
declare _parts text[]; begin select string_to_array(name, '/') into _parts; return _parts[1:array_length(_parts,1)-1]; end $$;
create function storage.filename(name text) returns text language plpgsql immutable as $$
declare _parts text[]; begin select string_to_array(name, '/') into _parts; return _parts[array_length(_parts,1)]; end $$;
create function storage.extension(name text) returns text language plpgsql immutable as $$
declare _parts text[]; _filename text; begin select string_to_array(name, '/') into _parts; select _parts[array_length(_parts,1)] into _filename;
return reverse(split_part(reverse(_filename), '.', 1)); end $$;
create table realtime.messages (id bigserial primary key, topic text, extension text, payload jsonb, event text, private boolean,
  inserted_at timestamptz default now(), updated_at timestamptz default now());
create function realtime.topic() returns text language sql stable as $$ select current_setting('realtime.topic', true) $$;
create publication supabase_realtime;
grant usage on schema auth, storage, realtime, public to anon, authenticated, service_role;
-- The hosted project's default privileges (read from pg_default_acl): every table / sequence / function
-- created in public is granted to anon, authenticated and service_role unless a migration revokes it.
alter default privileges for role postgres in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges for role postgres in schema public grant execute on functions to anon, authenticated, service_role;
-- 20260705055652 seeds the owner's admin role; the row needs its auth.users parent locally.
insert into auth.users (id) values ('21b1c42a-9456-4a58-8624-46aa3abb632f');
