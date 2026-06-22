-- Row Level Security policies for the `avatar` storage bucket.
--
-- Profile pictures are uploaded to:  avatar/users/<auth-uid>/avatar.<ext>
-- (see _AvatarEditPage in lib/profile.dart, upsert: true).
--
-- Storage RLS is always enabled on storage.objects, so without these policies
-- the upload fails with: "new row violates row-level security policy (403)".
--
-- These scope writes to each user's own folder: the 2nd path segment must
-- equal their auth uid. Reads stay public (the bucket is public and uses
-- getPublicUrl), so no SELECT policy is needed here.
--
-- Idempotent: drops each policy first so it can be re-run safely.

-- ── Upload (insert) own avatar ───────────────────────────────────────────────
drop policy if exists "avatar_insert_own" on storage.objects;
create policy "avatar_insert_own"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'avatar'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

-- ── Overwrite (update) own avatar — needed because upload uses upsert ─────────
drop policy if exists "avatar_update_own" on storage.objects;
create policy "avatar_update_own"
  on storage.objects
  for update
  to authenticated
  using (
    bucket_id = 'avatar'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  )
  with check (
    bucket_id = 'avatar'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

-- ── Delete own avatar ────────────────────────────────────────────────────────
drop policy if exists "avatar_delete_own" on storage.objects;
create policy "avatar_delete_own"
  on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'avatar'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  );
