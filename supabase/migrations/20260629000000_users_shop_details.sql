-- Adds the seller / shop-detail columns the mobile app writes to when a user
-- becomes a seller via the "Become a Seller" sheet on the profile page.
--
-- These are surfaced in the profile "Details" section. Without the columns the
-- update fails with PostgREST error PGRST204 ("Could not find the column").
-- Each column is added idempotently so the migration is safe to re-run.

alter table public.users
  add column if not exists is_seller boolean not null default false,
  add column if not exists business_name text,
  add column if not exists shop_category text,
  add column if not exists shop_description text,
  add column if not exists payment_number text;

-- Ask PostgREST to refresh its schema cache so the new columns are visible
-- immediately (otherwise the API may not see them until the next reload).
notify pgrst, 'reload schema';
