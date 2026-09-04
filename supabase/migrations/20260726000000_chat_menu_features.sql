-- Chat thread menu: mute, archive, and "view listing".

-- ── 1. Columns ──────────────────────────────────────────────────────────────

alter table public.conversations
  add column if not exists listing_id     text,
  add column if not exists a_muted        boolean not null default false,
  add column if not exists b_muted        boolean not null default false,
  add column if not exists a_archived_at  timestamptz,
  add column if not exists b_archived_at  timestamptz;

-- ── 2. start_conversation now remembers the listing ─────────────────────────
--
-- The old one-argument form is dropped so PostgREST doesn't keep both
-- overloads (an ambiguous RPC call fails with PGRST203).

drop function if exists public.start_conversation(uuid);

create or replace function public.start_conversation(
  other_user uuid,
  listing    text default null
)
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

  insert into public.conversations (user_a, user_b, listing_id)
  values (lo, hi, listing)
  on conflict (user_a, user_b) do nothing;

  select id into cid
    from public.conversations
   where user_a = lo and user_b = hi;

  -- Opened from a listing: remember the latest one they're discussing.
  if listing is not null and btrim(listing) <> '' then
    update public.conversations set listing_id = listing where id = cid;
  end if;

  return cid;
end;
$fn$;

grant execute on function public.start_conversation(uuid, text) to authenticated;

-- ── 3. Mute / unmute (this user's side only) ────────────────────────────────

create or replace function public.set_conversation_muted(
  conv  uuid,
  muted boolean
)
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
     set a_muted = case when user_a = me then muted else a_muted end,
         b_muted = case when user_b = me then muted else b_muted end
   where id = conv
     and (user_a = me or user_b = me);
end;
$fn$;

grant execute on function public.set_conversation_muted(uuid, boolean)
  to authenticated;

-- ── 4. Archive / unarchive (this user's side only) ──────────────────────────

create or replace function public.set_conversation_archived(
  conv     uuid,
  archived boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $fn$
declare
  me uuid := auth.uid();
  stamp timestamptz := case when archived then now() else null end;
begin
  if me is null then
    raise exception 'Not signed in';
  end if;

  update public.conversations
     set a_archived_at = case when user_a = me then stamp else a_archived_at end,
         b_archived_at = case when user_b = me then stamp else b_archived_at end
   where id = conv
     and (user_a = me or user_b = me);
end;
$fn$;

grant execute on function public.set_conversation_archived(uuid, boolean)
  to authenticated;

-- ── 5. The Chats list, now split into inbox and archive ─────────────────────
--
-- Dropped rather than replaced: the return type gains columns, which
-- `create or replace function` refuses.

drop function if exists public.my_conversations();
drop function if exists public.my_conversations(boolean);

create or replace function public.my_conversations(
  archived_only boolean default false
)
returns table (
  id              uuid,
  other_id        uuid,
  other_name      text,
  other_avatar    text,
  other_is_seller boolean,
  listing_id      text,
  muted           boolean,
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
             as my_read_at,
           case when c.user_a = me.uid then c.a_muted else c.b_muted end
             as my_muted,
           case when c.user_a = me.uid then c.a_archived_at else c.b_archived_at end
             as my_archived_at
      from public.conversations c, me
     where me.uid is not null
       and (c.user_a = me.uid or c.user_b = me.uid)
  )
  select m.id,
         m.other_uid,
         coalesce(u.name, 'AniMart User'),
         u.avatar_url,
         coalesce(u.is_seller, false),
         m.listing_id,
         m.my_muted,
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
     -- Archived only counts while nothing newer has arrived; a fresh message
     -- pulls the thread back into the inbox on its own.
     and case
           when archived_only then
             m.my_archived_at is not null
             and m.last_message_at <= m.my_archived_at
           else
             m.my_archived_at is null
             or m.last_message_at > m.my_archived_at
         end
   order by m.last_message_at desc;
$fn$;

grant execute on function public.my_conversations(boolean) to authenticated;

-- Badge on the Chats icon: inbox only, and muted threads stay silent.
create or replace function public.my_unread_chat_count()
returns bigint
language sql
security definer
set search_path = public
as $fn$
  select coalesce(sum(unread_count), 0)::bigint
    from public.my_conversations(false)
   where not muted;
$fn$;

grant execute on function public.my_unread_chat_count() to authenticated;

notify pgrst, 'reload schema';
