-- Widen the `listings.status` CHECK constraint to allow 'disabled'.
--
-- The app lets a seller hide a listing from buyers by setting
-- status = 'disabled' (Profile → My Listings multi-select, and the single
-- listing's "Disable Listing" action in Product Detail). The original table
-- was created with a check constraint (`listings_status_check`) that predates
-- that value, so those updates failed with:
--   new row for relation "listings" violates check constraint
--   "listings_status_check" (SQLSTATE 23514)
--
-- This migration replaces the constraint with the full set of statuses the
-- app and admin website use. Browse pages still filter to status = 'active',
-- so anything else stays hidden from buyers.
--
-- Idempotent: drops the constraint first so it can be re-run safely.

alter table public.listings
  drop constraint if exists listings_status_check;

alter table public.listings
  add constraint listings_status_check
  check (status in ('active', 'disabled', 'sold', 'pending', 'draft'));
