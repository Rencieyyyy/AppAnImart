-- Let a buyer purchase the same listing more than once.
--
-- The offers table was modelled as "one offer per buyer per listing, ever"
-- (unique(listing_id, buyer_id)), and submitOffer upserted on that key. But a
-- livestock listing has stock and relists after a completed sale, so the SAME
-- buyer can legitimately buy again. The upsert then OVERWROTE the buyer's
-- existing offer row — the one already tied to a completed transaction — and
-- accepting it a second time bound a second transaction to the same offer_id.
-- Every screen maps a transaction to its offer 1:1 (_txByOffer keyed by
-- offer_id), so the two deals collapsed into one and the buyer saw the wrong
-- (older) state.
--
-- Fix: an offer row is single-use. A repeat purchase is a NEW offer row.
--   * Drop the hard unique(listing_id, buyer_id).
--   * Keep at most one PENDING offer per (listing, buyer) via a partial unique
--     index, so revising an un-accepted offer still updates in place, but
--     accepted/declined/completed history no longer blocks a new purchase.
--   * Defence in depth: a trigger refuses to (re-)accept an offer that already
--     has a transaction, so no code path can ever bind two deals to one offer.
--
-- The app (submitOffer) is updated to reuse only a still-open row
-- (pending/declined, which never have a transaction) and otherwise insert a
-- fresh offer.
--
-- NOTE: pre-existing offer rows that already collapsed two deals (from test
-- data created before this fix) are not auto-repaired — complete/cancel those
-- to clear them.
--
-- Idempotent: safe to re-run.

-- ── 1. Drop the old "one offer per buyer per listing" unique constraint ──────
do $$
declare
  v_listing smallint;
  v_buyer   smallint;
  v_con     text;
begin
  select attnum into v_listing from pg_attribute
   where attrelid = 'public.offers'::regclass and attname = 'listing_id';
  select attnum into v_buyer from pg_attribute
   where attrelid = 'public.offers'::regclass and attname = 'buyer_id';

  select conname into v_con
    from pg_constraint
   where conrelid = 'public.offers'::regclass
     and contype = 'u'
     and conkey @> array[v_listing, v_buyer]
     and array_length(conkey, 1) = 2
   limit 1;

  if v_con is not null then
    execute format('alter table public.offers drop constraint %I', v_con);
  end if;
end $$;

-- ── 2. At most one PENDING offer per (listing, buyer) ───────────────────────
create unique index if not exists offers_one_pending_per_buyer
  on public.offers (listing_id, buyer_id)
  where status = 'pending';

-- ── 3. Never bind a second deal to an offer that already has one ────────────
create or replace function public.block_reaccept_with_deal()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'accepted'
     and new.status is distinct from old.status
     and exists (
       select 1 from public.transactions t where t.offer_id = new.id
     ) then
    raise exception
      'This offer already has a deal recorded. Ask the buyer to send a new offer.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_block_reaccept_with_deal on public.offers;
create trigger trg_block_reaccept_with_deal
  before update on public.offers
  for each row
  execute function public.block_reaccept_with_deal();
