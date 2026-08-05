-- Customer-support live chat.
--
-- A single 1:1 thread per user, identified by `user_id`. The mobile customer
-- writes rows with sender = 'user'; an admin (from the admin panel) replies
-- with sender = 'admin'. Realtime delivers each side's messages to the other.
--
-- Idempotent: safe to re-run.

create table if not exists public.support_messages (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  sender     text not null check (sender in ('user', 'admin')),
  body       text not null check (char_length(btrim(body)) > 0),
  admin_id   uuid references public.admins (id),
  read       boolean not null default false,
  created_at timestamptz not null default now()
);

-- Fast lookup / ordering of a user's thread.
create index if not exists support_messages_user_created_idx
  on public.support_messages (user_id, created_at);

alter table public.support_messages enable row level security;

-- ── Read ──────────────────────────────────────────────────────────────────
-- A user sees only their own thread; admins see every thread.
drop policy if exists "support_select_own_or_admin" on public.support_messages;
create policy "support_select_own_or_admin"
  on public.support_messages
  for select
  to authenticated
  using (
    user_id = auth.uid()
    or exists (select 1 from public.admins a where a.id = auth.uid())
  );

-- ── Insert (customer) ─────────────────────────────────────────────────────
-- A user may post into their own thread, and only as the 'user' side.
drop policy if exists "support_insert_user" on public.support_messages;
create policy "support_insert_user"
  on public.support_messages
  for insert
  to authenticated
  with check (user_id = auth.uid() and sender = 'user');

-- ── Insert (admin) ────────────────────────────────────────────────────────
-- An admin may reply into any thread, and only as the 'admin' side.
drop policy if exists "support_insert_admin" on public.support_messages;
create policy "support_insert_admin"
  on public.support_messages
  for insert
  to authenticated
  with check (
    sender = 'admin'
    and exists (select 1 from public.admins a where a.id = auth.uid())
  );

-- ── Update (read receipts) ────────────────────────────────────────────────
-- Either side may flip the `read` flag on messages in a thread they can see.
drop policy if exists "support_update_read" on public.support_messages;
create policy "support_update_read"
  on public.support_messages
  for update
  to authenticated
  using (
    user_id = auth.uid()
    or exists (select 1 from public.admins a where a.id = auth.uid())
  )
  with check (
    user_id = auth.uid()
    or exists (select 1 from public.admins a where a.id = auth.uid())
  );

-- ── Realtime ──────────────────────────────────────────────────────────────
-- The Flutter `.stream()` API needs this table in the realtime publication.
do $$
begin
  alter publication supabase_realtime add table public.support_messages;
exception
  when duplicate_object then null;  -- already added
end $$;
