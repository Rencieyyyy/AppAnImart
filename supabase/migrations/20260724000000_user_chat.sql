-- Real-time 1:1 chat between two app users (buyer ⇄ seller).

-- ── 1. Conversations ────────────────────────────────────────────────────────

create table if not exists public.conversations (
  id              uuid primary key default gen_random_uuid(),
  -- Ordered pair: user_a is always the lexicographically smaller uuid.
  user_a          uuid not null references auth.users (id) on delete cascade,
  user_b          uuid not null references auth.users (id) on delete cascade,
  -- Denormalised preview for the Chats list (kept fresh by the trigger below).
  last_message    text,
  last_sender_id  uuid references auth.users (id) on delete set null,
  last_message_at timestamptz,
  -- Per-user "delete on my screen only" watermark.
  a_cleared_at    timestamptz,
  b_cleared_at    timestamptz,
  -- Per-user read watermark, for the unread badge / bold row.
  a_read_at       timestamptz,
  b_read_at       timestamptz,
  created_at      timestamptz not null default now(),
  check (user_a < user_b)
);

create unique index if not exists conversations_pair_idx
  on public.conversations (user_a, user_b);

create index if not exists conversations_user_a_idx
  on public.conversations (user_a, last_message_at desc);
create index if not exists conversations_user_b_idx
  on public.conversations (user_b, last_message_at desc);

alter table public.conversations enable row level security;

-- Only the two participants can see (or touch) the thread.
drop policy if exists "conversations_select_participant" on public.conversations;
create policy "conversations_select_participant"
  on public.conversations
  for select
  to authenticated
  using (auth.uid() = user_a or auth.uid() = user_b);

-- Writes go through the SECURITY DEFINER helpers below, but a participant may
-- also update their own watermarks directly. The WITH CHECK repeats the
-- membership test so a row can never be handed to somebody else.
drop policy if exists "conversations_update_participant" on public.conversations;
create policy "conversations_update_participant"
  on public.conversations
  for update
  to authenticated
  using (auth.uid() = user_a or auth.uid() = user_b)
  with check (auth.uid() = user_a or auth.uid() = user_b);

-- ── 2. Messages ─────────────────────────────────────────────────────────────

create table if not exists public.chat_messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null
                    references public.conversations (id) on delete cascade,
  sender_id       uuid not null references auth.users (id) on delete cascade,
  body            text not null default '',
  -- Storage object PATH in the private `user-chat` bucket (same pattern as
  -- support chat), rendered through a signed URL.
  image_url       text,
  created_at      timestamptz not null default now(),
  check (
    char_length(btrim(body)) > 0
    or coalesce(btrim(image_url), '') <> ''
  )
);

create index if not exists chat_messages_conversation_idx
  on public.chat_messages (conversation_id, created_at);

alter table public.chat_messages enable row level security;

-- Read: participants of the parent conversation only.
drop policy if exists "chat_messages_select_participant" on public.chat_messages;
create policy "chat_messages_select_participant"
  on public.chat_messages
  for select
  to authenticated
  using (
    exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and (c.user_a = auth.uid() or c.user_b = auth.uid())
    )
  );

-- Write: a participant, posting as themselves, and only while neither side
-- has blocked the other.
drop policy if exists "chat_messages_insert_participant" on public.chat_messages;
create policy "chat_messages_insert_participant"
  on public.chat_messages
  for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and (c.user_a = auth.uid() or c.user_b = auth.uid())
        and not exists (
          select 1 from public.user_blocks b
          where (b.blocker_id = c.user_a and b.blocked_id = c.user_b)
             or (b.blocker_id = c.user_b and b.blocked_id = c.user_a)
        )
    )
  );

-- No UPDATE / DELETE policies: messages are immutable once sent, and
-- "deleting a chat" never removes anybody else's copy (see the watermark
-- design note at the top).

-- ── 3. Keep the conversation preview fresh ──────────────────────────────────

create or replace function public.chat_touch_conversation()
returns trigger
language plpgsql
security definer
set search_path = public
as $fn$
begin
  update public.conversations
     set last_message = case
                          when coalesce(btrim(new.body), '') <> ''
                            then left(btrim(new.body), 160)
                          else 'Photo'
                        end,
         last_sender_id  = new.sender_id,
         last_message_at = new.created_at,
         -- The sender has, by definition, read their own message.
         a_read_at = case when user_a = new.sender_id
                          then new.created_at else a_read_at end,
         b_read_at = case when user_b = new.sender_id
                          then new.created_at else b_read_at end
   where id = new.conversation_id;
  return new;
end;
$fn$;

drop trigger if exists chat_messages_touch_conversation on public.chat_messages;
create trigger chat_messages_touch_conversation
  after insert on public.chat_messages
  for each row execute function public.chat_touch_conversation();

-- ── 4. Open (or find) a thread with another user ────────────────────────────
--
-- SECURITY DEFINER because creating the row needs to read/write the pair
-- regardless of which side calls it; the body still refuses anything that
-- isn't "the caller and somebody else".

create or replace function public.start_conversation(other_user uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $fn$
declare
  me  uuid := auth.uid();
  lo  uuid;
  hi  uuid;
  cid uuid;
begin
  if me is null then
    raise exception 'Not signed in';
  end if;
  if other_user is null or other_user = me then
    raise exception 'Pick somebody else to chat with';
  end if;
  if not exists (select 1 from auth.users u where u.id = other_user) then
    raise exception 'That user no longer exists';
  end if;
  if exists (
       select 1 from public.user_blocks b
       where (b.blocker_id = me and b.blocked_id = other_user)
          or (b.blocker_id = other_user and b.blocked_id = me)
     ) then
    raise exception 'You cannot message this user';
  end if;

  lo := least(me, other_user);
  hi := greatest(me, other_user);

  insert into public.conversations (user_a, user_b)
  values (lo, hi)
  on conflict (user_a, user_b) do nothing;

  select id into cid
    from public.conversations
   where user_a = lo and user_b = hi;

  return cid;
end;
$fn$;

grant execute on function public.start_conversation(uuid) to authenticated;

-- ── 5. "Delete this chat — on my screen only" ───────────────────────────────

create or replace function public.clear_conversation(conv uuid)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  me uuid := auth.uid();
begin
  if me is null then
    raise exception 'Not signed in';
  end if;

  update public.conversations
     set a_cleared_at = case when user_a = me then now() else a_cleared_at end,
         b_cleared_at = case when user_b = me then now() else b_cleared_at end
   where id = conv
     and (user_a = me or user_b = me);
end;
$fn$;

grant execute on function public.clear_conversation(uuid) to authenticated;

-- ── 6. Mark a thread read ───────────────────────────────────────────────────

create or replace function public.mark_conversation_read(conv uuid)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  me uuid := auth.uid();
begin
  if me is null then
    return;
  end if;

  update public.conversations
     set a_read_at = case when user_a = me then now() else a_read_at end,
         b_read_at = case when user_b = me then now() else b_read_at end
   where id = conv
     and (user_a = me or user_b = me);
end;
$fn$;

grant execute on function public.mark_conversation_read(uuid) to authenticated;

-- ── 7. The Chats list ───────────────────────────────────────────────────────
--
-- Returns the caller's threads with the OTHER person's profile fields joined
-- in, already filtered by their own "cleared" watermark and with the unread
-- count computed. Rows the caller deleted stay hidden until the other person
-- sends something new (last_message_at > cleared_at).

create or replace function public.my_conversations()
returns table (
  id              uuid,
  other_id        uuid,
  other_name      text,
  other_avatar    text,
  other_is_seller boolean,
  last_message    text,
  last_sender_id  uuid,
  last_message_at timestamptz,
  unread_count    bigint
)
language sql
security definer
set search_path = public
as $fn$
  with me as (select auth.uid() as uid),
  mine as (
    select c.*,
           case when c.user_a = me.uid then c.user_b else c.user_a end
             as other_uid,
           case when c.user_a = me.uid then c.a_cleared_at else c.b_cleared_at end
             as my_cleared_at,
           case when c.user_a = me.uid then c.a_read_at else c.b_read_at end
             as my_read_at
      from public.conversations c, me
     where me.uid is not null
       and (c.user_a = me.uid or c.user_b = me.uid)
  )
  select m.id,
         m.other_uid,
         coalesce(u.name, 'AniMart User'),
         u.avatar_url,
         coalesce(u.is_seller, false),
         m.last_message,
         m.last_sender_id,
         m.last_message_at,
         (select count(*)
            from public.chat_messages msg
           where msg.conversation_id = m.id
             and msg.sender_id <> (select uid from me)
             and msg.created_at > coalesce(m.my_read_at, 'epoch'::timestamptz)
             and msg.created_at > coalesce(m.my_cleared_at, 'epoch'::timestamptz))
    from mine m
    left join public.users u on u.id = m.other_uid
   where m.last_message_at is not null
     and (m.my_cleared_at is null or m.last_message_at > m.my_cleared_at)
   order by m.last_message_at desc;
$fn$;

grant execute on function public.my_conversations() to authenticated;

-- Total unread across every thread — feeds the badge on the Chats icon.
create or replace function public.my_unread_chat_count()
returns bigint
language sql
security definer
set search_path = public
as $fn$
  select coalesce(sum(unread_count), 0)::bigint from public.my_conversations();
$fn$;

grant execute on function public.my_unread_chat_count() to authenticated;

-- ── 8. Messages a user is allowed to see in a thread ────────────────────────
--
-- Same as selecting from chat_messages, but drops everything sent before the
-- caller last deleted the thread — so a deleted chat comes back empty and
-- only refills with what arrives afterwards.

create or replace function public.conversation_messages(conv uuid)
returns setof public.chat_messages
language sql
security definer
set search_path = public
as $fn$
  select msg.*
    from public.chat_messages msg
    join public.conversations c on c.id = msg.conversation_id
   where msg.conversation_id = conv
     and (c.user_a = auth.uid() or c.user_b = auth.uid())
     and msg.created_at > coalesce(
           case when c.user_a = auth.uid() then c.a_cleared_at
                else c.b_cleared_at end,
           'epoch'::timestamptz)
   order by msg.created_at;
$fn$;

grant execute on function public.conversation_messages(uuid) to authenticated;

-- ── 9. Private bucket for chat pictures (5 MB, images only) ─────────────────

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'user-chat', 'user-chat', false,
  5 * 1024 * 1024,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
  set public             = false,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- Objects live at `<conversation_id>/<uid>/<ms>.<ext>`; a participant may
-- upload into their own folder inside a thread they belong to, and read any
-- picture in a thread they belong to.
drop policy if exists "user_chat_insert_participant" on storage.objects;
create policy "user_chat_insert_participant"
  on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'user-chat'
    and (storage.foldername(name))[2] = auth.uid()::text
    and exists (
      select 1 from public.conversations c
      where c.id::text = (storage.foldername(name))[1]
        and (c.user_a = auth.uid() or c.user_b = auth.uid())
    )
  );

drop policy if exists "user_chat_select_participant" on storage.objects;
create policy "user_chat_select_participant"
  on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'user-chat'
    and exists (
      select 1 from public.conversations c
      where c.id::text = (storage.foldername(name))[1]
        and (c.user_a = auth.uid() or c.user_b = auth.uid())
    )
  );

-- ── 10. Realtime ────────────────────────────────────────────────────────────
-- The Flutter `.stream()` API needs these tables in the realtime publication.
--
-- `replica identity full` on conversations: the Chats list listens for UPDATE
-- events (the preview/last_message_at columns change on every new message),
-- and Realtime needs the whole old row to authorise those against RLS.
alter table public.conversations replica identity full;

do $do$
begin
  alter publication supabase_realtime add table public.chat_messages;
exception
  when duplicate_object then null;  -- already added
end $do$;

do $do$
begin
  alter publication supabase_realtime add table public.conversations;
exception
  when duplicate_object then null;  -- already added
end $do$;

notify pgrst, 'reload schema';
