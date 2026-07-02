-- Adds the location columns behind the Explore page's "near you" feature.
--
-- Each user picks their city/municipality in the app; its coordinates are
-- stored here. Listing distance is then computed client-side between the
-- signed-in buyer's coordinates and the seller's coordinates (the seller's
-- location travels with the `listings -> users` join).
--
-- Columns are added idempotently so the migration is safe to re-run.

alter table public.users
  add column if not exists location_name text,
  add column if not exists latitude double precision,
  add column if not exists longitude double precision;

-- Ask PostgREST to refresh its schema cache so the new columns are visible
-- immediately (otherwise the API may not see them until the next reload).
notify pgrst, 'reload schema';
