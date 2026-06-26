-- Marketplace trust & safety features.
--
-- Adds four tables used by the buyer/seller flows:
--   * favorites    — a user's saved listings (wishlist).
--   * reviews      — buyer ratings of a seller (1..5 stars), one per pair.
--   * reports      — abuse reports against a listing or a seller.
--   * user_blocks  — users a person has blocked (their listings are hidden).
--
-- `listing_id` is stored as text (no FK) so this works whether listings.id is
-- a uuid or a bigint — the app already passes listing ids around as strings.
-- The user-identifying columns are the Supabase auth uid (uuid).
--
-- Idempotent: safe to re-run.

-- ════════════════════════════════════════════════════════════════════════════
-- Favorites (wishlist)
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists public.favorites (
  user_id    uuid not null references auth.users (id) on delete cascade,
  listing_id text not null,
  created_at timestamptz not null default now(),
  primary key (user_id, listing_id)
);

create index if not exists favorites_user_idx
  on public.favorites (user_id, created_at desc);

alter table public.favorites enable row level security;

-- A user may only see and manage their own favorites.
drop policy if exists "favorites_select_own" on public.favorites;
create policy "favorites_select_own"
  on public.favorites
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "favorites_insert_own" on public.favorites;
create policy "favorites_insert_own"
  on public.favorites
  for insert
  to authenticated
  with check (user_id = auth.uid());

drop policy if exists "favorites_delete_own" on public.favorites;
create policy "favorites_delete_own"
  on public.favorites
  for delete
  to authenticated
  using (user_id = auth.uid());

-- ════════════════════════════════════════════════════════════════════════════
-- Seller reviews
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists public.reviews (
  id          uuid primary key default gen_random_uuid(),
  seller_id   uuid not null references auth.users (id) on delete cascade,
  reviewer_id uuid not null references auth.users (id) on delete cascade,
  rating      int  not null check (rating between 1 and 5),
  comment     text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  -- One review per reviewer per seller (re-reviewing updates the row).
  unique (seller_id, reviewer_id),
  -- You cannot review yourself.
  check (seller_id <> reviewer_id)
);

create index if not exists reviews_seller_idx
  on public.reviews (seller_id, created_at desc);

alter table public.reviews enable row level security;

-- Reviews are public (shown on seller profiles / listings).
drop policy if exists "reviews_select_all" on public.reviews;
create policy "reviews_select_all"
  on public.reviews
  for select
  using (true);

-- A user may only post a review as themselves.
drop policy if exists "reviews_insert_own" on public.reviews;
create policy "reviews_insert_own"
  on public.reviews
  for insert
  to authenticated
  with check (reviewer_id = auth.uid());

-- A user may edit / delete only their own review.
drop policy if exists "reviews_update_own" on public.reviews;
create policy "reviews_update_own"
  on public.reviews
  for update
  to authenticated
  using (reviewer_id = auth.uid())
  with check (reviewer_id = auth.uid());

drop policy if exists "reviews_delete_own" on public.reviews;
create policy "reviews_delete_own"
  on public.reviews
  for delete
  to authenticated
  using (reviewer_id = auth.uid());

-- Convenience: per-seller rating aggregate for badges / trust score.
create or replace view public.seller_ratings as
  select
    seller_id,
    round(avg(rating)::numeric, 2) as avg_rating,
    count(*)                       as review_count
  from public.reviews
  group by seller_id;

-- ════════════════════════════════════════════════════════════════════════════
-- Abuse reports
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists public.reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users (id) on delete cascade,
  target_type text not null check (target_type in ('listing', 'seller')),
  listing_id  text,
  seller_id   uuid references auth.users (id) on delete cascade,
  reason      text not null,
  details     text,
  status      text not null default 'open' check (status in ('open', 'reviewed', 'dismissed')),
  created_at  timestamptz not null default now()
);

create index if not exists reports_status_idx
  on public.reports (status, created_at desc);

alter table public.reports enable row level security;

-- A reporter can see the reports they filed; admins see every report.
drop policy if exists "reports_select_own_or_admin" on public.reports;
create policy "reports_select_own_or_admin"
  on public.reports
  for select
  to authenticated
  using (
    reporter_id = auth.uid()
    or exists (select 1 from public.admins a where a.id = auth.uid())
  );

-- Any signed-in user may file a report as themselves.
drop policy if exists "reports_insert_own" on public.reports;
create policy "reports_insert_own"
  on public.reports
  for insert
  to authenticated
  with check (reporter_id = auth.uid());

-- Only admins may triage (change status).
drop policy if exists "reports_update_admin" on public.reports;
create policy "reports_update_admin"
  on public.reports
  for update
  to authenticated
  using (exists (select 1 from public.admins a where a.id = auth.uid()))
  with check (exists (select 1 from public.admins a where a.id = auth.uid()));

-- ════════════════════════════════════════════════════════════════════════════
-- User blocks
-- ════════════════════════════════════════════════════════════════════════════
create table if not exists public.user_blocks (
  blocker_id uuid not null references auth.users (id) on delete cascade,
  blocked_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create index if not exists user_blocks_blocker_idx
  on public.user_blocks (blocker_id);

alter table public.user_blocks enable row level security;

-- A user may only see and manage their own block list.
drop policy if exists "user_blocks_select_own" on public.user_blocks;
create policy "user_blocks_select_own"
  on public.user_blocks
  for select
  to authenticated
  using (blocker_id = auth.uid());

drop policy if exists "user_blocks_insert_own" on public.user_blocks;
create policy "user_blocks_insert_own"
  on public.user_blocks
  for insert
  to authenticated
  with check (blocker_id = auth.uid());

drop policy if exists "user_blocks_delete_own" on public.user_blocks;
create policy "user_blocks_delete_own"
  on public.user_blocks
  for delete
  to authenticated
  using (blocker_id = auth.uid());
