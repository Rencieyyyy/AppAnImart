-- Offer notifications, red-dot badge watermarks, and shop category rename.
--
-- 1. `announcements.recipient_id`: personal announcements. When a buyer makes
--    (or revises) an offer, the trigger below composes a formal notification
--    announcement addressed to the listing's seller only. A RESTRICTIVE RLS
--    policy hides recipient-targeted rows from everyone but that recipient
--    (admins keep full visibility for the admin panel).
-- 2. `users.announcements_seen_at` / `users.offers_seen_at`: watermarks for
--    the app's red-dot indicators — the announcements bell icon shows a dot
--    while announcements newer than the first watermark exist, and the Seller
--    Dashboard "Offers" action shows one while pending offers newer than the
--    second exist. The app stamps them when the respective page is opened.
-- 3. `users.shop_category`: 'Aquatics' renamed to 'Aquaculture' to match the
--    updated picker (which also gained 'Ornamental Fish' and
--    'Hatching & Breeding Products').
--
-- Idempotent: safe to re-run.

-- ── 1a. Personal announcements ──────────────────────────────────────────────
alter table public.announcements
  add column if not exists recipient_id uuid references auth.users (id) on delete cascade;

create index if not exists announcements_recipient_idx
  on public.announcements (recipient_id)
  where recipient_id is not null;

-- Restrictive: ANDs with the existing permissive select policy, so public
-- announcements stay public while recipient-targeted ones are only readable
-- by their recipient (or an admin panel session).
drop policy if exists "announcements_recipient_only" on public.announcements;
create policy "announcements_recipient_only"
  on public.announcements
  as restrictive
  for select
  using (
    recipient_id is null
    or recipient_id = auth.uid()
    or public.current_admin_id() is not null
  );

-- ── 1b. The offer → announcement trigger ────────────────────────────────────
-- SECURITY DEFINER: the announcements RLS only allows admin inserts, but this
-- fires as the buyer who placed the offer.
create or replace function public.notify_new_offer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id      uuid;
  v_buyer_name    text;
  v_listing_title text;
  v_amount_text   text;
  v_title         text;
  v_body          text;
  v_announcement  uuid;
begin
  -- Announce fresh offers only: every insert, plus updates where the buyer
  -- revised the amount (a re-offer resets status to 'pending'). The seller's
  -- own accept/decline updates must not notify.
  if tg_op = 'UPDATE' then
    if new.amount is not distinct from old.amount
       or new.status <> 'pending' then
      return new;
    end if;
  end if;

  -- The announcements table needs an admin author for the app's author card;
  -- attribute the notice to any admin (same convention as announce_plan_sale).
  v_admin_id := coalesce(
    public.current_admin_id(),
    (select id from public.admins limit 1)
  );
  if v_admin_id is null then
    return new;
  end if;

  select coalesce(nullif(trim(u.name), ''), 'A buyer')
    into v_buyer_name
    from public.users u
   where u.id = new.buyer_id;
  v_buyer_name := coalesce(v_buyer_name, 'A buyer');

  -- listing_id is text by convention; listings.id may be uuid or bigint.
  select l.title
    into v_listing_title
    from public.listings l
   where l.id::text = new.listing_id;
  v_listing_title := coalesce(nullif(trim(v_listing_title), ''), 'your listing');

  v_amount_text := public.fmt_amount(new.amount);

  v_title := format('New Offer Received — ₱%s for "%s"',
                    v_amount_text, v_listing_title);

  v_body :=
    'Dear Seller,' || E'\n\n' ||
    format(
      'We would like to inform you that %s has made an offer of ₱%s on your '
      || 'listing "%s".',
      v_buyer_name, v_amount_text, v_listing_title
    ) || E'\n\n' ||
    'To review this offer, please open the app and go to Profile → Seller '
    || 'Dashboard → Offers, where you may accept or decline it. Only you can '
    || 'see this notification.' || E'\n\n' ||
    'Thank you for selling on AniMart.' || E'\n' ||
    '— The AniMart Team';

  insert into public.announcements (admin_id, title, body, status, audience, recipient_id)
  values (v_admin_id, v_title, v_body, 'Active', 'sellers', new.seller_id)
  returning id into v_announcement;

  insert into public.announcement_tags (announcement_id, tag)
  values (v_announcement, 'offer');

  return new;
exception when others then
  -- Never block the buyer's offer because notifying failed.
  raise warning 'notify_new_offer failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists trg_notify_new_offer on public.offers;
create trigger trg_notify_new_offer
  after insert or update on public.offers
  for each row
  execute function public.notify_new_offer();

-- ── 2. Red-dot watermarks ───────────────────────────────────────────────────
alter table public.users
  add column if not exists announcements_seen_at timestamptz,
  add column if not exists offers_seen_at timestamptz;

-- ── 3. Shop category rename ─────────────────────────────────────────────────
update public.users
   set shop_category = 'Aquaculture'
 where shop_category = 'Aquatics';
