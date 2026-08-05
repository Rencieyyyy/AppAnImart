-- Price drop on a favorited listing → notify the favoriters (Part 3.4 of
-- docs/app_assessment_and_notification_plan.md — the re-engagement hook).
--
-- When a seller lowers the price of an active listing, everyone who has it
-- in their favorites gets a personal announcement (and, via
-- queue_announcement_push(), a phone push).
--
-- Spam cap: at most one price-drop notice per listing per 20 hours, tracked
-- in public.price_drop_notices — five edits in an hour fire one notice, and
-- the notice always advertises the latest (lowest) price because it is
-- composed at edit time.
--
-- Idempotent: safe to re-run.

-- ── Per-listing cooldown ─────────────────────────────────────────────────────
create table if not exists public.price_drop_notices (
  listing_id       text primary key,
  last_notified_at timestamptz not null default now()
);

alter table public.price_drop_notices enable row level security;
-- No client policies on purpose: only the SECURITY DEFINER trigger below
-- reads/writes this table.

-- ── The trigger ──────────────────────────────────────────────────────────────
create or replace function public.notify_price_drop()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_old        numeric;
  v_new        numeric;
  v_admin_id   uuid;
  v_title      text;
  v_body       text;
  v_headline   text;
  v_favoriter  uuid;
  v_announcement uuid;
  v_notified   int := 0;
begin
  -- Only live listings whose price actually went down.
  if lower(coalesce(new.status, '')) <> 'active' then
    return new;
  end if;
  begin
    v_old := old.price::numeric;
    v_new := new.price::numeric;
  exception when others then
    return new;  -- unparseable price value; nothing to compare
  end;
  if v_old is null or v_new is null or v_new <= 0 or v_new >= v_old then
    return new;
  end if;

  -- Cooldown: one notice per listing per 20 hours.
  if exists (
    select 1 from public.price_drop_notices n
     where n.listing_id = new.id::text
       and n.last_notified_at > now() - interval '20 hours'
  ) then
    return new;
  end if;

  -- The announcements table needs an admin author for the app's author card.
  v_admin_id := coalesce(
    public.current_admin_id(),
    (select id from public.admins limit 1)
  );
  if v_admin_id is null then
    return new;
  end if;

  v_headline := coalesce(nullif(trim(new.title), ''), 'A listing you favorited');
  v_title := format('Price Drop — "%s" is now ₱%s',
                    v_headline, public.fmt_amount(v_new));
  v_body :=
    'Hello,' || E'\n\n' ||
    format(
      'Good news! "%s", a listing you saved to your favorites, just dropped '
      || 'in price from ₱%s to ₱%s.',
      v_headline, public.fmt_amount(v_old), public.fmt_amount(v_new)
    ) || E'\n\n' ||
    'Open the app to view the listing and make an offer before someone else '
    || 'does. Only you can see this notification.' || E'\n\n' ||
    'Thank you for using AniMart.' || E'\n' ||
    '— The AniMart Team';

  -- One personal announcement per favoriter (each queues its own push).
  for v_favoriter in
    select f.user_id
      from public.favorites f
     where f.listing_id = new.id::text
       and f.user_id <> new.seller_id
  loop
    insert into public.announcements (admin_id, title, body, status, audience, recipient_id)
    values (v_admin_id, v_title, v_body, 'Active', 'buyers', v_favoriter)
    returning id into v_announcement;

    insert into public.announcement_tags (announcement_id, tag)
    values (v_announcement, 'promo');

    v_notified := v_notified + 1;
  end loop;

  -- Start the cooldown only when someone was actually notified, so a listing
  -- with no favoriters doesn't burn its window on a solo price edit.
  if v_notified > 0 then
    insert into public.price_drop_notices (listing_id, last_notified_at)
    values (new.id::text, now())
    on conflict (listing_id) do update set last_notified_at = now();
  end if;

  return new;
exception when others then
  -- Never block the seller's price edit because notifying failed.
  raise warning 'notify_price_drop failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists trg_notify_price_drop on public.listings;
create trigger trg_notify_price_drop
  after update on public.listings
  for each row
  when (old.price is distinct from new.price)
  execute function public.notify_price_drop();
