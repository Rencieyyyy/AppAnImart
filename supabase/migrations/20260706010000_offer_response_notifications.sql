-- Buyer-facing offer response notifications.
--
-- When a seller accepts or declines an offer, post a personal announcement
-- addressed to the buyer (recipient_id-targeted, 'offer'-tagged) so they
-- learn the outcome in the app. This complements notify_new_offer(), which
-- handles the seller-facing "new offer" notice and deliberately skips
-- status-change updates.
--
-- No app changes needed: the announcements feed, RLS recipient policy,
-- bell red-dot and the 'Offers' filter chip already handle personal
-- announcements.
--
-- Idempotent: safe to re-run.

-- SECURITY DEFINER: the announcements RLS only allows admin inserts, but
-- this fires as the seller responding to the offer.
create or replace function public.notify_offer_response()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id      uuid;
  v_seller_name   text;
  v_listing_title text;
  v_amount_text   text;
  v_accepted      boolean;
  v_title         text;
  v_body          text;
  v_announcement  uuid;
begin
  -- Only when the offer is newly resolved. A buyer re-offer resets status to
  -- 'pending' and is announced to the seller by notify_new_offer() instead.
  if new.status not in ('accepted', 'declined')
     or new.status is not distinct from old.status then
    return new;
  end if;
  v_accepted := new.status = 'accepted';

  -- The announcements table needs an admin author for the app's author card;
  -- attribute the notice to any admin (same convention as notify_new_offer).
  v_admin_id := coalesce(
    public.current_admin_id(),
    (select id from public.admins limit 1)
  );
  if v_admin_id is null then
    return new;
  end if;

  select coalesce(nullif(trim(u.name), ''), 'The seller')
    into v_seller_name
    from public.users u
   where u.id = new.seller_id;
  v_seller_name := coalesce(v_seller_name, 'The seller');

  -- listing_id is text by convention; listings.id may be uuid or bigint.
  select l.title
    into v_listing_title
    from public.listings l
   where l.id::text = new.listing_id;
  v_listing_title := coalesce(nullif(trim(v_listing_title), ''), 'the listing');

  v_amount_text := public.fmt_amount(new.amount);

  if v_accepted then
    v_title := format('Offer Accepted — ₱%s for "%s"',
                      v_amount_text, v_listing_title);
    v_body :=
      'Dear Buyer,' || E'\n\n' ||
      format(
        'Good news! %s has accepted your offer of ₱%s on the listing "%s".',
        v_seller_name, v_amount_text, v_listing_title
      ) || E'\n\n' ||
      'The seller may reach out to you directly, or you can open the listing '
      || 'in the app and tap "Message Seller on Messenger" to arrange the '
      || 'sale. Only you can see this notification.' || E'\n\n' ||
      'Thank you for buying on AniMart.' || E'\n' ||
      '— The AniMart Team';
  else
    v_title := format('Offer Declined — ₱%s for "%s"',
                      v_amount_text, v_listing_title);
    v_body :=
      'Dear Buyer,' || E'\n\n' ||
      format(
        'We would like to inform you that %s has declined your offer of ₱%s '
        || 'on the listing "%s".',
        v_seller_name, v_amount_text, v_listing_title
      ) || E'\n\n' ||
      'You are welcome to make a new offer on the listing or explore other '
      || 'listings in the app. Only you can see this notification.' || E'\n\n' ||
      'Thank you for using AniMart.' || E'\n' ||
      '— The AniMart Team';
  end if;

  insert into public.announcements (admin_id, title, body, status, audience, recipient_id)
  values (v_admin_id, v_title, v_body, 'Active', 'buyers', new.buyer_id)
  returning id into v_announcement;

  insert into public.announcement_tags (announcement_id, tag)
  values (v_announcement, 'offer');

  return new;
exception when others then
  -- Never block the seller's accept/decline because notifying failed.
  raise warning 'notify_offer_response failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists trg_notify_offer_response on public.offers;
create trigger trg_notify_offer_response
  after update on public.offers
  for each row
  execute function public.notify_offer_response();
