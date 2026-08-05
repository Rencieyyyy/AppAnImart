-- Keep a listing's stock and sale status honest.
--
-- Two problems this closes, both around editing a listing's stock directly
-- (product_detail.dart "Edit Listing"), which bypassed the reservation
-- accounting added in 20260713000000:
--
--   1. OVERSELL: a seller could set stock below the quantity already reserved
--      in active deals. When those deals complete, stock floors at 0 and a
--      reserved buyer can no longer be honored. Now rejected outright.
--
--   2. STALE STATUS / SILENT RELIST: a manual stock edit didn't recompute the
--      listing's sale status, so a "Sold" listing could sit on leftover stock,
--      and a fully-'reserved' listing wouldn't reopen after a restock. Now,
--      whenever stock changes WITHOUT the same update also setting status
--      explicitly, the status is recomputed from stock vs. committed. Edits
--      that don't touch stock never change status (so fixing a typo on a Sold
--      listing can't silently put it back on the market).
--
-- Implemented as a BEFORE UPDATE trigger so it also guards any future writer,
-- not just the app. Concurrent accept vs. stock-edit serialize on the listing
-- row lock the accept trigger already takes.
--
-- Idempotent: safe to re-run.

create or replace function public.guard_listing_stock()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_committed int;
begin
  -- Only relevant when stock actually changes.
  if new.stock is not distinct from old.stock then
    return new;
  end if;

  select coalesce(sum(quantity), 0)
    into v_committed
    from public.transactions
   where listing_id = new.id::text
     and status = 'reserved';

  -- Never let stock drop below what's already promised to buyers.
  if coalesce(new.stock, 0) < v_committed then
    raise exception
      'You have % unit(s) reserved in active deals; stock can''t be set below that. '
      'Complete or cancel those deals first.',
      v_committed;
  end if;

  -- If this same update didn't explicitly set a status, keep it consistent
  -- with the new availability. Seller-controlled non-sale states are left be.
  if new.status is not distinct from old.status
     and old.status not in ('disabled', 'draft', 'pending') then
    new.status := case
                    when coalesce(new.stock, 0) <= 0        then 'sold'
                    when new.stock - v_committed <= 0        then 'reserved'
                    else                                          'active'
                  end;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_guard_listing_stock on public.listings;
create trigger trg_guard_listing_stock
  before update on public.listings
  for each row
  execute function public.guard_listing_stock();
