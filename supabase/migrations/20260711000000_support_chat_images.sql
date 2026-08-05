-- Support chat: let users attach pictures to their messages.
--
-- 1. `support_messages.image_url` stores the storage object PATH (not a URL)
--    of an attached picture, in the new private `support-chat` bucket at
--    `<user_id>/<millisecondsSinceEpoch>.<ext>`. Both the app and the admin
--    panel open it with a signed URL (same pattern as
--    `subscriptions.receipt_url` / the `payment-receipts` bucket).
-- 2. The body may now be empty when a picture is attached (image-only
--    messages); text-only messages still require a non-empty body.
-- 3. Bucket + RLS: a user may upload only into their own `<uid>/…` folder
--    and read back only their own pictures; admins may read every picture
--    (so they can see them from the admin panel) and may also upload into
--    any thread's folder for future admin-side replies.
--
-- Idempotent: safe to re-run.

-- ── 1. Column ───────────────────────────────────────────────────────────────
alter table public.support_messages
  add column if not exists image_url text;

-- ── 2. Allow image-only messages ────────────────────────────────────────────
alter table public.support_messages
  drop constraint if exists support_messages_body_check;

alter table public.support_messages
  add constraint support_messages_body_check
  check (
    char_length(btrim(body)) > 0
    or coalesce(btrim(image_url), '') <> ''
  );

-- ── 3. Private bucket (5 MB, images only) ───────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'support-chat', 'support-chat', false,
  5 * 1024 * 1024,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Upload: users into their own folder only; admins into any folder.
drop policy if exists "support_chat_upload" on storage.objects;
create policy "support_chat_upload"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'support-chat'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (select 1 from public.admins a where a.id = auth.uid())
    )
  );

-- Read: users their own folder only; admins everything.
drop policy if exists "support_chat_read" on storage.objects;
create policy "support_chat_read"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'support-chat'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (select 1 from public.admins a where a.id = auth.uid())
    )
  );
