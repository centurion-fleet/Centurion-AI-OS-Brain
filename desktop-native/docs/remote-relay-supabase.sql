-- Centurion Remote "Chat from anywhere" — Supabase schema (v1)
-- Apply in the Centurion Supabase project used by the sales site / remote relay.
-- Relay carries opaque E2E Crypto Chat blobs; SessionDB stays on the Brain.

create extension if not exists "pgcrypto";

create table if not exists remote_brain_installs (
  id uuid primary key default gen_random_uuid(),
  install_id text not null unique,
  display_name text,
  relay_enabled boolean not null default false,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz
);

create table if not exists remote_pair_tokens (
  id uuid primary key default gen_random_uuid(),
  brain_id uuid not null references remote_brain_installs (id) on delete cascade,
  token_hash text not null unique,
  device_label text,
  fingerprint text,
  revoked boolean not null default false,
  created_at timestamptz not null default now(),
  last_used_at timestamptz
);

create index if not exists remote_pair_tokens_brain_idx
  on remote_pair_tokens (brain_id)
  where revoked = false;

create table if not exists remote_brain_presence (
  brain_id uuid primary key references remote_brain_installs (id) on delete cascade,
  online boolean not null default false,
  conn_epoch text,
  updated_at timestamptz not null default now()
);

-- Realtime: clients subscribe to private channel brain:{install_id}
alter table remote_brain_installs enable row level security;
alter table remote_pair_tokens enable row level security;
alter table remote_brain_presence enable row level security;

-- Service role (Vercel) bypasses RLS for mint/revoke/enable.

-- Phone JWTs: claim app_metadata.brain_install_id must match to read presence.
drop policy if exists remote_presence_select_paired on remote_brain_presence;
create policy remote_presence_select_paired
  on remote_brain_presence
  for select
  to authenticated
  using (
    brain_id in (
      select i.id
      from remote_brain_installs i
      join remote_pair_tokens t on t.brain_id = i.id
      where t.revoked = false
        and i.install_id = coalesce(
          auth.jwt() -> 'app_metadata' ->> 'brain_install_id',
          auth.jwt() -> 'user_metadata' ->> 'brain_install_id'
        )
    )
  );

drop policy if exists remote_installs_select_paired on remote_brain_installs;
create policy remote_installs_select_paired
  on remote_brain_installs
  for select
  to authenticated
  using (
    install_id = coalesce(
      auth.jwt() -> 'app_metadata' ->> 'brain_install_id',
      auth.jwt() -> 'user_metadata' ->> 'brain_install_id'
    )
  );

-- Pair tokens: never readable by authenticated phones (hash-only server side).
drop policy if exists remote_pair_tokens_deny_all on remote_pair_tokens;
create policy remote_pair_tokens_deny_all
  on remote_pair_tokens
  for all
  to authenticated
  using (false)
  with check (false);

-- Presence writes are service-role only (Brain via Vercel or service credential).
drop policy if exists remote_presence_no_write on remote_brain_presence;
create policy remote_presence_no_write
  on remote_brain_presence
  for insert
  to authenticated
  with check (false);

comment on table remote_brain_installs is
  'Centurion Brain installs enrolled for Chat from anywhere (Supabase Realtime).';
comment on table remote_pair_tokens is
  'Hashed pair tokens for App Store iPhone; plaintext shown once at mint.';
comment on table remote_brain_presence is
  'Brain outbound presence + conn_epoch (re-KX on change).';
