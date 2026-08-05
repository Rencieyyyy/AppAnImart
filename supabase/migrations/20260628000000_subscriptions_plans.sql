-- Unify subscription plan values with the mobile app.
--
-- The app and admin website now share exactly three tiers:
--   'Free', 'Premium', 'Super Premium'   (the Basic tier is retired).
--
-- This migration rewrites the legacy admin keys stored in
-- `subscriptions.plan` (free / basic / pro / elite) to those labels, locks the
-- column down to the three allowed values, and (re)creates the RLS policies the
-- app's request flow depends on. Existing Basic rows fold into Premium.
--
-- It also normalises `users.plan` if that column exists.
--
-- Idempotent: safe to re-run. Wrapped in a single transaction.

begin;

-- ════════════════════════════════════════════════════════════════════════════
-- 1. Drop any existing CHECK constraint on subscriptions.plan
--    (so the data rewrite below can't be blocked by an old allow-list).
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare
  r record;
begin
  for r in
    select conname
    from pg_constraint
    where conrelid = 'public.subscriptions'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%plan%'
  loop
    execute format(
      'alter table public.subscriptions drop constraint %I', r.conname);
  end loop;
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- 2. (Optional) Align prices for retired Basic rows to the Premium price.
--    Only touches rows still carrying the old Basic price (₱299); any custom /
--    admin-set price is left untouched. Run before the rename so it can key off
--    the old plan value.
-- ════════════════════════════════════════════════════════════════════════════
update public.subscriptions
set price = 699
where lower(trim(plan)) = 'basic'
  and price = 299;

-- ════════════════════════════════════════════════════════════════════════════
-- 3. Rewrite plan values to the app's labels (case-insensitive match).
--    free → Free, basic/pro → Premium, elite → Super Premium.
--    Anything null/empty/unknown becomes Free.
-- ════════════════════════════════════════════════════════════════════════════
update public.subscriptions
set plan = case lower(trim(coalesce(plan, '')))
  when 'free'          then 'Free'
  when 'basic'         then 'Premium'   -- Basic retired → Premium
  when 'pro'           then 'Premium'
  when 'premium'       then 'Premium'
  when 'elite'         then 'Super Premium'
  when 'super premium' then 'Super Premium'
  else 'Free'
end
where plan is null
   or plan not in ('Free', 'Premium', 'Super Premium');

-- ════════════════════════════════════════════════════════════════════════════
-- 4. Lock the column to the three allowed values + default to Free.
-- ════════════════════════════════════════════════════════════════════════════
alter table public.subscriptions
  alter column plan set default 'Free';

alter table public.subscriptions
  drop constraint if exists subscriptions_plan_check;

alter table public.subscriptions
  add constraint subscriptions_plan_check
  check (plan in ('Free', 'Premium', 'Super Premium'));

-- ════════════════════════════════════════════════════════════════════════════
-- 5. Mirror the rename onto users.plan, if that column exists.
--    Like the subscriptions column above, drop any legacy CHECK constraint
--    (e.g. free/basic/pro/elite) *before* the rewrite, otherwise setting the
--    new labels (Free/Premium/Super Premium) violates the old allow-list, then
--    re-lock the column to the three allowed values.
-- ════════════════════════════════════════════════════════════════════════════
do $$
declare
  r record;
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'users'
      and column_name = 'plan'
  ) then
    -- Drop any existing CHECK constraint on users.plan so the rewrite can't be
    -- blocked by the legacy allow-list.
    for r in
      select conname
      from pg_constraint
      where conrelid = 'public.users'::regclass
        and contype = 'c'
        and pg_get_constraintdef(oid) ilike '%plan%'
    loop
      execute format('alter table public.users drop constraint %I', r.conname);
    end loop;

    update public.users
    set plan = case lower(trim(coalesce(plan, '')))
      when 'free'          then 'Free'
      when 'basic'         then 'Premium'
      when 'pro'           then 'Premium'
      when 'premium'       then 'Premium'
      when 'elite'         then 'Super Premium'
      when 'super premium' then 'Super Premium'
      else 'Free'
    end
    where plan is null
       or plan not in ('Free', 'Premium', 'Super Premium');

    execute 'alter table public.users alter column plan set default ''Free''';

    execute 'alter table public.users
      add constraint users_plan_check
      check (plan in (''Free'', ''Premium'', ''Super Premium''))';
  end if;
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- 6. Row Level Security for the request flow.
--    Users insert/read their own rows; admins manage everything. Without these
--    policies the app's SubscriptionService.requestPlan insert is rejected.
-- ════════════════════════════════════════════════════════════════════════════
alter table public.subscriptions enable row level security;

-- A user may read only their own subscriptions; admins read all.
drop policy if exists "subscriptions_select_own_or_admin" on public.subscriptions;
create policy "subscriptions_select_own_or_admin"
  on public.subscriptions
  for select
  to authenticated
  using (
    user_id = auth.uid()
    or exists (select 1 from public.admins a where a.id = auth.uid())
  );

-- A user may submit a request only as themselves.
drop policy if exists "subscriptions_insert_own" on public.subscriptions;
create policy "subscriptions_insert_own"
  on public.subscriptions
  for insert
  to authenticated
  with check (user_id = auth.uid());

-- Only admins may approve/reject/expire (update) requests.
drop policy if exists "subscriptions_update_admin" on public.subscriptions;
create policy "subscriptions_update_admin"
  on public.subscriptions
  for update
  to authenticated
  using (exists (select 1 from public.admins a where a.id = auth.uid()))
  with check (exists (select 1 from public.admins a where a.id = auth.uid()));

-- Only admins may delete subscription rows.
drop policy if exists "subscriptions_delete_admin" on public.subscriptions;
create policy "subscriptions_delete_admin"
  on public.subscriptions
  for delete
  to authenticated
  using (exists (select 1 from public.admins a where a.id = auth.uid()));

commit;

-- ════════════════════════════════════════════════════════════════════════════
-- Verification (run separately after applying):
--   select plan, count(*) from public.subscriptions group by plan;
--   select plan, count(*) from public.users group by plan;  -- if column exists
-- Expect only: Free, Premium, Super Premium.
-- ════════════════════════════════════════════════════════════════════════════
