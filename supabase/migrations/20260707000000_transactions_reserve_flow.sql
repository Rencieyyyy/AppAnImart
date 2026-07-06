-- Transactions / reserve flow + marketplace hardening.
--
-- Implements Part 1 of docs/app_assessment_and_notification_plan.md:
--
-- 1. `transactions`: accepting an offer now creates a deal record
--    (status 'reserved'), auto-declines the listing's other pending offers,
--    and puts the listing into status 'reserved' so it can't double-sell.
--    Completing decrements stock (auto-'sold' at zero); cancelling restores
--    the listing. Counterparts are notified via personal announcements.
-- 2. Offers gain `quantity` + `note` so the deal has real terms.
-- 3. Reviews are gated on a completed transaction with that seller.
-- 4. `explore_listings()` RPC: paged + searchable browse feed that computes
--    seller distance server-side, and `my_location()` for the caller's own
--    coords — so the client no longer needs to read anyone's lat/lng.
-- 5. Column grants on `users` drop SELECT on latitude/longitude for
--    client roles (the coordinates privacy fix).
--
-- Idempotent: safe to re-run.

-- ── 1a. Listing status gains 'reserved' ─────────────────────────────────────
alter table public.listings
  drop constraint if exists listings_status_check;

alter table public.listings
  add constraint listings_status_check
  check (status in ('active', 'disabled', 'sold', 'reserved', 'pending', 'draft'));

-- ── 1b. Offer terms ──────────────────────────────────────────────────────────
alter table public.offers
  add column if not exists quantity int not null default 1 check (quantity > 0),
  add column if not exists note text;

-- ── 1c. Transactions ─────────────────────────────────────────────────────────
create table if not exists public.transactions (
  id           uuid primary key default gen_random_uuid(),
  listing_id   text not null,
  offer_id     uuid references public.offers (id) on delete set null,
  seller_id    uuid not null references auth.users (id) on delete cascade,
  buyer_id     uuid not null references auth.users (id) on delete cascade,
  quantity     int not null default 1 check (quantity > 0),
  -- The accepted offer amount — the total agreed price for `quantity`.
  agreed_price numeric not null check (agreed_price >= 0),
  status       text not null default 'reserved'
               check (status in ('reserved', 'completed', 'cancelled')),
  cancelled_by uuid,
  cancel_reason text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists transactions_seller_idx
  on public.transactions (seller_id, created_at desc);
create index if not exists transactions_buyer_idx
  on public.transactions (buyer_id, created_at desc);
create index if not exists transactions_listing_idx
  on public.transactions (listing_id);

alter table public.transactions enable row level security;

-- Both parties can see their deals; all writes go through the SECURITY
-- DEFINER trigger/RPCs below, so no client insert/update/delete policies.
drop policy if exists "transactions_select_involved" on public.transactions;
create policy "transactions_select_involved"
  on public.transactions
  for select
  to authenticated
  using (buyer_id = auth.uid() or seller_id = auth.uid());

-- ── 1d. Accepting an offer reserves the listing ─────────────────────────────
create or replace function public.reserve_on_offer_accept()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status <> 'accepted' or new.status is not distinct from old.status then
    return new;
  end if;

  -- One live deal per listing: block a second accept while one is reserved.
  if exists (
    select 1 from public.transactions t
     where t.listing_id = new.listing_id and t.status = 'reserved'
  ) then
    raise exception 'This listing is already reserved for another buyer.';
  end if;

  insert into public.transactions
    (listing_id, offer_id, seller_id, buyer_id, quantity, agreed_price)
  values
    (new.listing_id, new.id, new.seller_id, new.buyer_id,
     coalesce(new.quantity, 1), new.amount);

  -- Losing bidders are auto-declined (each declined row fires
  -- notify_offer_response, so those buyers are told in-app).
  update public.offers
     set status = 'declined',
         updated_at = now()
   where listing_id = new.listing_id
     and id <> new.id
     and status = 'pending';

  -- The listing is spoken for until the deal completes or is cancelled.
  update public.listings
     set status = 'reserved'
   where id::text = new.listing_id
     and status = 'active';

  return new;
exception when others then
  -- Re-raise: the seller must know the accept failed (e.g. already reserved).
  raise;
end;
$$;

drop trigger if exists trg_reserve_on_offer_accept on public.offers;
create trigger trg_reserve_on_offer_accept
  after update on public.offers
  for each row
  execute function public.reserve_on_offer_accept();

-- ── 1e. Completing / cancelling a deal ──────────────────────────────────────
-- Seller marks the deal done: stock is decremented by the deal quantity;
-- the listing goes back online while stock remains, or to 'sold' at zero.
create or replace function public.complete_transaction(p_tx uuid)
returns text  -- null on success, else an error message
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tx   public.transactions%rowtype;
  v_left int;
begin
  select * into v_tx from public.transactions where id = p_tx;
  if not found then return 'Transaction not found.'; end if;
  if v_tx.seller_id <> auth.uid() then
    return 'Only the seller can complete this transaction.';
  end if;
  if v_tx.status <> 'reserved' then
    return 'This transaction is already ' || v_tx.status || '.';
  end if;

  update public.transactions
     set status = 'completed',
         completed_at = now(),
         updated_at = now()
   where id = p_tx;

  update public.listings
     set stock = greatest(coalesce(stock, 0) - v_tx.quantity, 0)
   where id::text = v_tx.listing_id
  returning coalesce(stock, 0) into v_left;

  update public.listings
     set status = case when coalesce(v_left, 0) > 0 then 'active' else 'sold' end
   where id::text = v_tx.listing_id
     and status = 'reserved';

  return null;
end;
$$;

-- Either party can cancel while reserved; the listing goes back online.
create or replace function public.cancel_transaction(p_tx uuid, p_reason text default null)
returns text  -- null on success, else an error message
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tx public.transactions%rowtype;
begin
  select * into v_tx from public.transactions where id = p_tx;
  if not found then return 'Transaction not found.'; end if;
  if auth.uid() not in (v_tx.buyer_id, v_tx.seller_id) then
    return 'Only the buyer or seller can cancel this transaction.';
  end if;
  if v_tx.status <> 'reserved' then
    return 'This transaction is already ' || v_tx.status || '.';
  end if;

  update public.transactions
     set status = 'cancelled',
         cancelled_by = auth.uid(),
         cancel_reason = nullif(trim(coalesce(p_reason, '')), ''),
         updated_at = now()
   where id = p_tx;

  update public.listings
     set status = 'active'
   where id::text = v_tx.listing_id
     and status = 'reserved';

  return null;
end;
$$;

grant execute on function public.complete_transaction(uuid) to authenticated;
grant execute on function public.cancel_transaction(uuid, text) to authenticated;

-- ── 1f. Transaction notifications (completed / cancelled) ───────────────────
create or replace function public.notify_transaction_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id      uuid;
  v_listing_title text;
  v_recipient     uuid;
  v_other_name    text;
  v_title         text;
  v_body          text;
  v_announcement  uuid;
begin
  if new.status not in ('completed', 'cancelled')
     or new.status is not distinct from old.status then
    return new;
  end if;

  v_admin_id := coalesce(
    public.current_admin_id(),
    (select id from public.admins limit 1)
  );
  if v_admin_id is null then return new; end if;

  select l.title into v_listing_title
    from public.listings l where l.id::text = new.listing_id;
  v_listing_title := coalesce(nullif(trim(v_listing_title), ''), 'the listing');

  if new.status = 'completed' then
    -- Tell the buyer; they can now rate the seller.
    v_recipient := new.buyer_id;
    select coalesce(nullif(trim(u.name), ''), 'The seller')
      into v_other_name from public.users u where u.id = new.seller_id;
    v_title := format('Purchase Completed — "%s"', v_listing_title);
    v_body :=
      'Dear Buyer,' || E'\n\n' ||
      format(
        'Your purchase of "%s" (₱%s) has been marked completed by %s.',
        v_listing_title, public.fmt_amount(new.agreed_price),
        coalesce(v_other_name, 'the seller')
      ) || E'\n\n' ||
      'You can now rate this seller from their profile — your review helps '
      || 'other buyers. Only you can see this notification.' || E'\n\n' ||
      'Thank you for buying on AniMart.' || E'\n' || '— The AniMart Team';
  else
    -- Tell the party who did NOT cancel.
    v_recipient := case when new.cancelled_by = new.buyer_id
                        then new.seller_id else new.buyer_id end;
    select coalesce(nullif(trim(u.name), ''), 'The other party')
      into v_other_name from public.users u where u.id = new.cancelled_by;
    v_title := format('Transaction Cancelled — "%s"', v_listing_title);
    v_body :=
      'Hello,' || E'\n\n' ||
      format(
        'The reserved transaction for "%s" (₱%s) was cancelled by %s.%s',
        v_listing_title, public.fmt_amount(new.agreed_price),
        coalesce(v_other_name, 'the other party'),
        case when new.cancel_reason is not null
             then E'\n\nReason: ' || new.cancel_reason else '' end
      ) || E'\n\n' ||
      'The listing is available again. Only you can see this notification.'
      || E'\n\n' || '— The AniMart Team';
  end if;

  insert into public.announcements (admin_id, title, body, status, audience, recipient_id)
  values (v_admin_id, v_title, v_body, 'Active',
          case when v_recipient = new.buyer_id then 'buyers' else 'sellers' end,
          v_recipient)
  returning id into v_announcement;

  insert into public.announcement_tags (announcement_id, tag)
  values (v_announcement, 'offer');

  return new;
exception when others then
  raise warning 'notify_transaction_event failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists trg_notify_transaction_event on public.transactions;
create trigger trg_notify_transaction_event
  after update on public.transactions
  for each row
  execute function public.notify_transaction_event();

-- ── 3. Reviews require a completed purchase ──────────────────────────────────
drop policy if exists "reviews_insert_own" on public.reviews;
create policy "reviews_insert_own"
  on public.reviews
  for insert
  to authenticated
  with check (
    reviewer_id = auth.uid()
    and exists (
      select 1 from public.transactions t
       where t.buyer_id = auth.uid()
         and t.seller_id = reviews.seller_id
         and t.status = 'completed'
    )
  );

drop policy if exists "reviews_update_own" on public.reviews;
create policy "reviews_update_own"
  on public.reviews
  for update
  to authenticated
  using (reviewer_id = auth.uid())
  with check (
    reviewer_id = auth.uid()
    and exists (
      select 1 from public.transactions t
       where t.buyer_id = auth.uid()
         and t.seller_id = reviews.seller_id
         and t.status = 'completed'
    )
  );

-- ── 4. Browse RPCs (privacy + pagination + server-side search) ──────────────
-- Explore feed: active listings, optional search, paged. Distance is
-- computed here from the CALLER's stored location to each seller's — raw
-- coordinates never leave the database.
create or replace function public.explore_listings(
  p_search text default null,
  p_limit  int  default 30,
  p_offset int  default 0
)
returns table (
  id          text,
  title       text,
  price       numeric,
  image_url   text,
  image_urls  jsonb,
  category    text,
  location    text,
  description text,
  condition   text,
  breed       text,
  age         text,
  weight      text,
  created_at  timestamptz,
  seller_id   uuid,
  status      text,
  seller_name text,
  distance_km double precision
)
language sql
security definer
set search_path = public
as $$
  with me as (
    select u.latitude as lat, u.longitude as lng
      from public.users u
     where u.id = auth.uid()
  )
  select
    l.id::text,
    l.title,
    l.price::numeric,
    l.image_url,
    to_jsonb(l.image_urls),
    l.category,
    l.location,
    l.description,
    l.condition,
    l.breed,
    l.age,
    l.weight,
    l.created_at,
    l.seller_id,
    l.status,
    coalesce(nullif(trim(u.name), ''), 'AniMart User'),
    case
      when me.lat is null or me.lng is null
        or u.latitude is null or u.longitude is null then null
      else round((
        2 * 6371 * asin(sqrt(
          power(sin(radians((u.latitude - me.lat) / 2)), 2)
          + cos(radians(me.lat)) * cos(radians(u.latitude))
          * power(sin(radians((u.longitude - me.lng) / 2)), 2)
        ))
      )::numeric, 1)::double precision
    end
  from public.listings l
  left join public.users u on u.id = l.seller_id
  cross join me
  where l.status = 'active'
    and (
      p_search is null or trim(p_search) = ''
      or l.title ilike '%' || trim(p_search) || '%'
      or l.category ilike '%' || trim(p_search) || '%'
      or l.breed ilike '%' || trim(p_search) || '%'
      or l.location ilike '%' || trim(p_search) || '%'
    )
  order by l.created_at desc
  limit greatest(p_limit, 1)
  offset greatest(p_offset, 0);
$$;

grant execute on function public.explore_listings(text, int, int) to authenticated;

-- The caller's own saved location (their row, so no privacy concern) — used
-- for the "near you" UI once direct column reads are revoked below.
create or replace function public.my_location()
returns table (location_name text, latitude double precision, longitude double precision)
language sql
security definer
set search_path = public
as $$
  select u.location_name, u.latitude::double precision, u.longitude::double precision
    from public.users u
   where u.id = auth.uid();
$$;

grant execute on function public.my_location() to authenticated;

-- ── 5. Coordinates privacy: column-level SELECT grants on users ─────────────
-- Replace the blanket SELECT grant with per-column grants that exclude
-- latitude/longitude, for both client roles. Future columns must be granted
-- explicitly (or added here); PostgREST `select=*` returns granted columns.
do $$
declare
  cols text;
begin
  select string_agg(quote_ident(column_name), ', ')
    into cols
    from information_schema.columns
   where table_schema = 'public'
     and table_name = 'users'
     and column_name not in ('latitude', 'longitude');

  execute 'revoke select on public.users from authenticated, anon';
  execute format('grant select (%s) on public.users to authenticated, anon', cols);
end $$;
