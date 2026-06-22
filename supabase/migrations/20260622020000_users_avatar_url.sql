-- Adds the profile-picture column the mobile app writes to.
--
-- The user profile page stores the uploaded Cloudinary image URL in
-- `users.avatar_url`. Without this column the update fails with
-- PostgREST error PGRST204 ("Could not find the 'avatar_url' column").

alter table public.users
  add column if not exists avatar_url text;

-- Ask PostgREST to refresh its schema cache so the new column is visible
-- immediately (otherwise the API may not see it until the next reload).
notify pgrst, 'reload schema';
