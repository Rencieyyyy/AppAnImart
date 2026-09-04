-- Client-side error log.
--
-- Users never see technical errors any more (see lib/friendly_error.dart) —
-- they get a plain sentence. When the app cannot explain a failure it shows a
-- short reference code ("Ref: A7K2QF") and writes the real error here, so a
-- developer can look up exactly what happened on a stranger's phone.
--
-- Only unexplained errors are logged. Expected ones (wrong password, offline,
-- "listing already reserved") show their own clear message and are never
-- written here, which keeps this table small and signal-heavy.
--
-- Writes are fire-and-forget from the client: a failure to log must never
-- surface to the user or mask the original error.

-- ── Table ─────────────────────────────────────────────────────────────────
create table if not exists public.client_errors (
  id          uuid primary key default gen_random_uuid(),
  -- Short code shown to the user; how a support report maps to this row.
  ref         text not null,
  -- NULL when the failure happened before login (e.g. the login call itself).
  user_id     uuid references public.users (id) on delete set null,
  -- What the user was doing: 'save_profile', 'publish_listing', …
  action      text not null default 'unknown',
  -- The plain sentence the user actually saw.
  shown       text,
  -- The real error, truncated by the trigger below.
  detail      text,
  -- PostgREST/Postgres code when there was one ('PGRST116', '23505', …).
  error_code  text,
  platform    text,
  app_version text,
  created_at  timestamptz not null default now()
);

-- Reconcile a hand-made dashboard table with the shape this migration expects.
alter table public.client_errors
  add column if not exists ref         text,
  add column if not exists user_id     uuid,
  add column if not exists action      text,
  add column if not exists shown       text,
  add column if not exists detail      text,
  add column if not exists error_code  text,
  add column if not exists platform    text,
  add column if not exists app_version text,
  add column if not exists created_at  timestamptz not null default now();

-- Codes are generated client-side from a 32-character alphabet, so collisions
-- are possible in principle. The index is deliberately NOT unique: a duplicate
-- ref must never cost a user their error report. Two rows sharing a code is a
-- lookup inconvenience; a rejected insert is lost evidence.
create index if not exists client_errors_ref_idx on public.client_errors (ref);

-- The admin feed reads newest-first, optionally filtered to one user.
create index if not exists client_errors_created_at_idx
  on public.client_errors (created_at desc);
create index if not exists client_errors_user_id_idx
  on public.client_errors (user_id, created_at desc);

-- ── Sanitising + rate limiting ────────────────────────────────────────────
-- A client can send anything, so the server decides what actually lands:
-- fields are clamped to sane lengths, user_id is forced to the caller, and a
-- flood of rows from one account is rejected.
create or replace function public.client_errors_guard()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recent int;
begin
  -- A row may only ever be attributed to the caller (or to nobody).
  if auth.uid() is null then
    new.user_id := null;
  else
    new.user_id := auth.uid();
  end if;

  new.ref         := upper(left(coalesce(nullif(trim(new.ref), ''), 'UNKNOWN'), 12));
  new.action      := left(coalesce(nullif(trim(new.action), ''), 'unknown'), 64);
  new.shown       := left(new.shown, 300);
  new.detail      := left(new.detail, 2000);
  new.error_code  := left(new.error_code, 32);
  new.platform    := left(new.platform, 32);
  new.app_version := left(new.app_version, 32);
  new.created_at  := now();

  -- Rate limit per signed-in account: a retry loop or a broken screen must not
  -- be able to fill the table. 40/hour is far above what a real user produces.
  if new.user_id is not null then
    select count(*) into recent
      from public.client_errors
     where user_id = new.user_id
       and created_at > now() - interval '1 hour';
    if recent >= 40 then
      return null; -- silently drop; the app never learns and never shows this
    end if;
  else
    -- Signed-out inserts can't be attributed, so they share one global budget.
    select count(*) into recent
      from public.client_errors
     where user_id is null
       and created_at > now() - interval '1 hour';
    if recent >= 200 then
      return null;
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists client_errors_guard on public.client_errors;
create trigger client_errors_guard
  before insert on public.client_errors
  for each row
  execute function public.client_errors_guard();

-- ── Housekeeping ──────────────────────────────────────────────────────────
-- Old errors have no value once the release that caused them is gone. Run
-- from the admin site, psql, or a pg_cron job:
--   select public.prune_client_errors();
create or replace function public.prune_client_errors(p_keep_days int default 60)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  removed int;
begin
  delete from public.client_errors
   where created_at < now() - make_interval(days => greatest(p_keep_days, 1));
  get diagnostics removed = row_count;
  return removed;
end;
$$;

-- SECURITY DEFINER + "delete rows" means this must never be callable by an
-- ordinary session. Only the service role (admin backend) and the pg_cron job
-- owner can run it.
revoke all on function public.prune_client_errors(int) from public, anon, authenticated;
grant execute on function public.prune_client_errors(int) to service_role;

-- Schedule the prune nightly when pg_cron is installed; skip silently if not.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    begin
      perform cron.unschedule('prune_client_errors');
    exception when others then
      null; -- no existing job
    end;
    perform cron.schedule(
      'prune_client_errors', '30 3 * * *',
      $cron$select public.prune_client_errors();$cron$
    );
  end if;
end $$;

-- ── Row Level Security ────────────────────────────────────────────────────
alter table public.client_errors enable row level security;

-- Anyone using the app may report an error, including before login (a failed
-- login is exactly the case worth logging). The trigger above overwrites
-- user_id, so a client cannot pin its errors on somebody else.
drop policy if exists "client_errors_insert" on public.client_errors;
create policy "client_errors_insert"
  on public.client_errors
  for insert
  to anon, authenticated
  with check (true);

-- Deliberately no SELECT policy for users: error detail is developer data, and
-- a row can carry another user's id or a server message. Reading is admin-only
-- (public.is_admin() is created by the admin website; skip gracefully when it
-- doesn't exist so this migration never depends on it).
do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'is_admin'
  ) then
    execute 'drop policy if exists "client_errors_select_admin" on public.client_errors';
    execute 'create policy "client_errors_select_admin" '
         || 'on public.client_errors for select to authenticated '
         || 'using (public.is_admin())';

    execute 'drop policy if exists "client_errors_delete_admin" on public.client_errors';
    execute 'create policy "client_errors_delete_admin" '
         || 'on public.client_errors for delete to authenticated '
         || 'using (public.is_admin())';
  end if;
end $$;

notify pgrst, 'reload schema';
