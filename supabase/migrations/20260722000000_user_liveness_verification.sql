-- Liveness (selfie) verification captured at sign-up.
--
-- The sign-up flow runs a 4-pose liveness check (center / right / left / down),
-- uploads each pose to Cloudinary, and carries the resulting URLs in the Auth
-- user's metadata as `verification_photos` = {center,right,left,down}. No
-- session exists at sign-up when email confirmation is on, so — exactly like
-- `valid_id_url` (see 20260709000000_signup_metadata_and_support_contacts.sql)
-- — the client cannot write to this table directly. Instead an AFTER INSERT
-- trigger on public.users reads that metadata and creates the row server-side,
-- so an admin can review the poses BEFORE the applicant's first login (login is
-- gated on is_verified).
--
-- Idempotent: safe to run whether the table was already created by hand in the
-- Supabase dashboard or not.

-- ── Table ─────────────────────────────────────────────────────────────────
create table if not exists public.user_liveness_verification (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references public.users (id) on delete cascade,
  center_image_url    text,
  right_image_url     text,
  left_image_url      text,
  down_image_url      text,
  verification_status text not null default 'pending',
  verified_by         uuid,
  remarks             text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- Reconcile a hand-made dashboard table with the shape this migration expects.
alter table public.user_liveness_verification
  add column if not exists center_image_url    text,
  add column if not exists right_image_url     text,
  add column if not exists left_image_url      text,
  add column if not exists down_image_url      text,
  add column if not exists verification_status text,
  add column if not exists verified_by         uuid,
  add column if not exists remarks             text,
  add column if not exists created_at          timestamptz not null default now(),
  add column if not exists updated_at          timestamptz not null default now();

-- A partial capture (e.g. one Cloudinary upload failed) must still record a
-- reviewable row instead of failing the whole sign-up, so the pose columns are
-- nullable even if the dashboard created them NOT NULL.
alter table public.user_liveness_verification
  alter column center_image_url drop not null,
  alter column right_image_url  drop not null,
  alter column left_image_url   drop not null,
  alter column down_image_url   drop not null;

-- Status is always present and defaults to 'pending'.
alter table public.user_liveness_verification
  alter column verification_status set default 'pending';
update public.user_liveness_verification
  set verification_status = 'pending'
  where verification_status is null;
alter table public.user_liveness_verification
  alter column verification_status set not null;

-- One liveness record per user; also lets the trigger below use ON CONFLICT.
create unique index if not exists user_liveness_verification_user_id_key
  on public.user_liveness_verification (user_id);

-- ── updated_at housekeeping ───────────────────────────────────────────────
create or replace function public.user_liveness_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists user_liveness_touch_updated_at on public.user_liveness_verification;
create trigger user_liveness_touch_updated_at
  before update on public.user_liveness_verification
  for each row
  execute function public.user_liveness_touch_updated_at();

-- ── Create the row from sign-up metadata ──────────────────────────────────
create or replace function public.create_liveness_from_metadata()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meta   jsonb;
  photos jsonb;
  c text;
  r text;
  l text;
  d text;
begin
  select raw_user_meta_data into meta from auth.users where id = new.id;
  if meta is null then
    return new;
  end if;

  photos := meta->'verification_photos';
  if photos is null or jsonb_typeof(photos) <> 'object' then
    return new;
  end if;

  c := nullif(photos->>'center', '');
  r := nullif(photos->>'right', '');
  l := nullif(photos->>'left', '');
  d := nullif(photos->>'down', '');

  -- Nothing was captured — don't create an empty verification row.
  if c is null and r is null and l is null and d is null then
    return new;
  end if;

  begin
    insert into public.user_liveness_verification
      (user_id, center_image_url, right_image_url, left_image_url,
       down_image_url, verification_status)
    values
      (new.id, c, r, l, d, 'pending')
    on conflict (user_id) do nothing;
  exception when others then
    -- Liveness bookkeeping must never block account creation.
    null;
  end;

  return new;
end;
$$;

drop trigger if exists create_liveness_from_metadata on public.users;
create trigger create_liveness_from_metadata
  after insert on public.users
  for each row
  execute function public.create_liveness_from_metadata();

-- ── Row Level Security ────────────────────────────────────────────────────
alter table public.user_liveness_verification enable row level security;

-- Users may read their own liveness record (e.g. to show a "verification
-- pending" state). Rows are created only by the SECURITY DEFINER trigger above
-- and edited only from the admin portal, so there is deliberately no client
-- INSERT/UPDATE policy.
drop policy if exists "user_liveness_select_own" on public.user_liveness_verification;
create policy "user_liveness_select_own"
  on public.user_liveness_verification
  for select
  to authenticated
  using (user_id = auth.uid());

-- Admin portal access (public.is_admin() is created by the admin website;
-- skip gracefully when it doesn't exist so this migration never depends on it).
do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'is_admin'
  ) then
    execute 'drop policy if exists "user_liveness_select_admin" on public.user_liveness_verification';
    execute 'create policy "user_liveness_select_admin" '
         || 'on public.user_liveness_verification for select to authenticated '
         || 'using (public.is_admin())';

    execute 'drop policy if exists "user_liveness_update_admin" on public.user_liveness_verification';
    execute 'create policy "user_liveness_update_admin" '
         || 'on public.user_liveness_verification for update to authenticated '
         || 'using (public.is_admin()) with check (public.is_admin())';
  end if;
end $$;

notify pgrst, 'reload schema';
