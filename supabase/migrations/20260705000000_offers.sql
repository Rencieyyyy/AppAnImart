-- Buyer offers on listings.
--
-- A buyer taps "Make Offer" on a listing (product_detail.dart) and the offer
-- lands here. Sellers review them in the profile page's Seller Dashboard →
-- "Offers" section (lib/offers_page.dart), grouped under each listing post.
--
-- `listing_id` is stored as text (no FK) so this works whether listings.id is
-- a uuid or a bigint — same convention as favorites/reports. Buyer names are
-- resolved app-side with a second `users` query (same as reviews) since the
-- FKs reference auth.users and can't be embedded via PostgREST.
--
-- Idempotent: safe to re-run.

create table if not exists public.offers (
  id         uuid primary key default gen_random_uuid(),
  listing_id text not null,
  seller_id  uuid not null references auth.users (id) on delete cascade,
  buyer_id   uuid not null references auth.users (id) on delete cascade,
  amount     numeric not null check (amount > 0),
  status     text not null default 'pending'
             check (status in ('pending', 'accepted', 'declined')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- One live offer per buyer per listing; re-offering updates the row.
  unique (listing_id, buyer_id),
  -- You cannot offer on your own listing.
  check (buyer_id <> seller_id)
);

create index if not exists offers_seller_idx
  on public.offers (seller_id, created_at desc);
create index if not exists offers_buyer_idx
  on public.offers (buyer_id, created_at desc);

alter table public.offers enable row level security;

-- Both sides of the offer may read it.
drop policy if exists "offers_select_involved" on public.offers;
create policy "offers_select_involved"
  on public.offers
  for select
  to authenticated
  using (buyer_id = auth.uid() or seller_id = auth.uid());

-- A buyer may only submit an offer as themselves.
drop policy if exists "offers_insert_own" on public.offers;
create policy "offers_insert_own"
  on public.offers
  for insert
  to authenticated
  with check (buyer_id = auth.uid());

-- The buyer may revise their offer; the seller may accept/decline it.
drop policy if exists "offers_update_involved" on public.offers;
create policy "offers_update_involved"
  on public.offers
  for update
  to authenticated
  using (buyer_id = auth.uid() or seller_id = auth.uid())
  with check (buyer_id = auth.uid() or seller_id = auth.uid());

-- The buyer may withdraw their own offer.
drop policy if exists "offers_delete_own" on public.offers;
create policy "offers_delete_own"
  on public.offers
  for delete
  to authenticated
  using (buyer_id = auth.uid());
