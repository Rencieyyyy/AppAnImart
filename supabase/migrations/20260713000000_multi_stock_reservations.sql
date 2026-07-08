-- Multi-buyer reservations for stocked listings.
--
-- A listing on AniMart is livestock with a real `stock` quantity (e.g. 30
-- head), so a single accepted offer for 2–3 animals should NOT lock the whole
-- listing or auto-decline everyone else. The original reserve flow
-- (20260707000000) assumed one buyer per listing: accepting an offer declined
-- all other pending offers and flipped the listing to 'reserved', starving the
-- remaining stock of buyers.
--
-- New model — availability is driven by stock, not by "is there any deal":
--
--   available = listings.stock − Σ(quantity of that listing's RESERVED deals)
--
--   * Accepting an offer reserves that offer's quantity, as long as it fits in
--     the currently-available stock. Other pending offers are left untouched,
--     so the seller can keep accepting buyers until stock runs out.
--   * A listing stays 'active' (browsable, offerable) while available > 0,
--     becomes 'reserved' only when every remaining unit is spoken for, and
--     'sold' when stock hits 0.
--   * Completing a deal permanently removes its units from stock; cancelling
--     frees the reserved units back to available.
--
-- Idempotent: safe to re-run. Replaces the bodies of reserve_on_offer_accept,
-- complete_transaction and cancel_transaction from 20260707000000.

-- ── Shared helper: recompute a listing's sale status from stock + deals ──────
-- Never touches seller-controlled non-sale states (disabled/draft/pending).
create or replace function public.refresh_listing_availability(p_listing_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stock     int;
  v_status    text;
  v_committed int;
begin
  select coalesce(stock, 0), status
    into v_stock, v_status
    from public.listings
   where id::text = p_listing_id
   for update;
  if not found then return; end if;

  -- Leave states the seller set by hand alone.
  if v_status in ('disabled', 'draft', 'pending') then
    return;
  end if;

  select coalesce(sum(quantity), 0)
    into v_committed
    from public.transactions
   where listing_id = p_listing_id
     and status = 'reserved';

  update public.listings
     set status = case
                    when v_stock <= 0                 then 'sold'
                    when v_stock - v_committed <= 0   then 'reserved'
                    else                                   'active'
                  end
   where id::text = p_listing_id;
end;
$$;

revoke all on function public.refresh_listing_availability(text) from public;

-- ── Accepting an offer reserves its quantity (not the whole listing) ─────────
create or replace function public.reserve_on_offer_accept()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stock     int;
  v_committed int;
  v_available int;
  v_qty       int := coalesce(new.quantity, 1);
begin
  if new.status <> 'accepted' or new.status is not distinct from old.status then
    return new;
  end if;

  -- Lock the listing row so two concurrent accepts can't over-commit stock.
  select coalesce(stock, 0)
    into v_stock
    from public.listings
   where id::text = new.listing_id
   for update;
  if not found then
    -- Listing row not found (legacy id mismatch) — fall back to single unit.
    v_stock := v_qty;
  end if;

  select coalesce(sum(quantity), 0)
    into v_committed
    from public.transactions
   where listing_id = new.listing_id
     and status = 'reserved';

  v_available := v_stock - v_committed;

  if v_qty > v_available then
    raise exception
      'Not enough stock: % unit(s) still available, but this offer is for %.',
      greatest(v_available, 0), v_qty;
  end if;

  insert into public.transactions
    (listing_id, offer_id, seller_id, buyer_id, quantity, agreed_price)
  values
    (new.listing_id, new.id, new.seller_id, new.buyer_id, v_qty, new.amount);

  -- Other pending offers are deliberately LEFT ALONE so remaining stock can
  -- still be sold to them. Only recompute whether the listing is now full.
  perform public.refresh_listing_availability(new.listing_id);

  return new;
end;
$$;

-- Trigger definition unchanged; recreate for a clean re-run.
drop trigger if exists trg_reserve_on_offer_accept on public.offers;
create trigger trg_reserve_on_offer_accept
  after update on public.offers
  for each row
  execute function public.reserve_on_offer_accept();

-- ── Completing a deal removes its units from stock for good ──────────────────
create or replace function public.complete_transaction(p_tx uuid)
returns text  -- null on success, else an error message
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tx    public.transactions%rowtype;
  v_stock int;
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
  returning coalesce(stock, 0) into v_stock;

  -- If that sale emptied the stock, no remaining pending offer can ever be
  -- filled — decline them so those buyers aren't left waiting forever.
  if coalesce(v_stock, 0) <= 0 then
    update public.offers
       set status = 'declined',
           updated_at = now()
     where listing_id = v_tx.listing_id
       and status = 'pending';
  end if;

  perform public.refresh_listing_availability(v_tx.listing_id);
  return null;
end;
$$;

-- ── Cancelling a deal frees its reserved units back to available ─────────────
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

  perform public.refresh_listing_availability(v_tx.listing_id);
  return null;
end;
$$;

grant execute on function public.complete_transaction(uuid) to authenticated;
grant execute on function public.cancel_transaction(uuid, text) to authenticated;
