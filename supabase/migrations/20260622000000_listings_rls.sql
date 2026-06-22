-- Row Level Security for the `listings` table.
--
-- Enforces ownership in the database so the app's "owner-only" UI checks
-- cannot be bypassed by a crafted client request:
--   * Anyone may READ listings (public marketplace browsing).
--   * A user may only INSERT a listing as themselves.
--   * A user may only UPDATE / DELETE their own listings (matched on seller_id).
--
-- Idempotent: drops each policy first so it can be re-run safely.
-- NOTE: review your existing policies in the Supabase dashboard before applying.

alter table public.listings enable row level security;

-- ── Read ────────────────────────────────────────────────────────────────────
-- Listings are public data shown in the browse pages, so allow reads to all.
-- (Browse pages further filter to status = 'active' in their queries.)
drop policy if exists "listings_select_all" on public.listings;
create policy "listings_select_all"
  on public.listings
  for select
  using (true);

-- NOTE: `seller_id` is compared via ::text so this works whether the column
-- is a `uuid` or `text` (the app stores the auth uid as a string).

-- ── Insert ──────────────────────────────────────────────────────────────────
-- A user can only create listings owned by themselves.
drop policy if exists "listings_insert_own" on public.listings;
create policy "listings_insert_own"
  on public.listings
  for insert
  to authenticated
  with check (auth.uid()::text = seller_id::text);

-- ── Update ──────────────────────────────────────────────────────────────────
-- A user can only edit their own listings (covers disable / enable).
drop policy if exists "listings_update_own" on public.listings;
create policy "listings_update_own"
  on public.listings
  for update
  to authenticated
  using (auth.uid()::text = seller_id::text)
  with check (auth.uid()::text = seller_id::text);

-- ── Delete ──────────────────────────────────────────────────────────────────
-- A user can only delete their own listings.
drop policy if exists "listings_delete_own" on public.listings;
create policy "listings_delete_own"
  on public.listings
  for delete
  to authenticated
  using (auth.uid()::text = seller_id::text);
