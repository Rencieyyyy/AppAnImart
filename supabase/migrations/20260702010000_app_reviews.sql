-- App "Rate us" ratings — the table behind the profile page's "Rate Our App"
-- sheet, surfaced on the admin website's Reviews page.
--
-- This is deliberately separate from public.reviews: that table holds
-- marketplace reviews OF A SELLER (unique per buyer/seller pair, seller_id
-- not null), so app ratings cannot live there without polluting seller
-- ratings. One row per user; re-submitting updates the existing rating.

create table if not exists public.app_reviews (
  id          uuid primary key default gen_random_uuid(),
  reviewer_id uuid not null unique references public.users (id) on delete cascade,
  rating      int  not null check (rating between 1 and 5),
  comment     text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.app_reviews enable row level security;

-- Users can read their own rating (so the app could prefill it). Admin read
-- access is granted below only when the admin website's is_admin() helper
-- exists in this database, so this migration never depends on it.
drop policy if exists "app_reviews_select_own" on public.app_reviews;
create policy "app_reviews_select_own"
  on public.app_reviews
  for select
  to authenticated
  using (reviewer_id = auth.uid());

drop policy if exists "app_reviews_insert_own" on public.app_reviews;
create policy "app_reviews_insert_own"
  on public.app_reviews
  for insert
  to authenticated
  with check (reviewer_id = auth.uid());

drop policy if exists "app_reviews_update_own" on public.app_reviews;
create policy "app_reviews_update_own"
  on public.app_reviews
  for update
  to authenticated
  using (reviewer_id = auth.uid())
  with check (reviewer_id = auth.uid());

-- Admin portal read access (public.is_admin() is created by the admin
-- website's announcements_rls.sql; skip gracefully when it doesn't exist).
do $$
begin
  if exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'is_admin'
  ) then
    execute 'drop policy if exists "app_reviews_select_admin" on public.app_reviews';
    execute 'create policy "app_reviews_select_admin" '
         || 'on public.app_reviews for select to authenticated '
         || 'using (public.is_admin())';
  end if;
end $$;

notify pgrst, 'reload schema';
