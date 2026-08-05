-- Expose "available" stock to buyers.
--
-- A listing's true availability is stock minus what's already reserved in
-- active deals (available = stock − Σ reserved-deal quantities). But a buyer
-- can't compute that client-side: transactions RLS only lets a user see deals
-- they're a party to, so the quantities other buyers have reserved are
-- invisible to them. Previously the product page showed RAW stock, so a buyer
-- could try to buy units that were already spoken for and only find out when
-- the seller's accept failed with "Not enough stock".
--
-- This SECURITY DEFINER function returns only the aggregate reserved COUNT
-- (never who reserved what) alongside the listing's public stock/price/status,
-- so the app can show "N available" and cap the quantity picker correctly.
--
-- Idempotent: safe to re-run.

create or replace function public.listing_stock(p_listing_id text)
returns table (stock int, reserved int, price numeric, status text)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce(l.stock, 0)::int,
    coalesce((
      select sum(t.quantity)::int
        from public.transactions t
       where t.listing_id = p_listing_id
         and t.status = 'reserved'
    ), 0),
    l.price::numeric,
    l.status
  from public.listings l
  where l.id::text = p_listing_id;
$$;

revoke all on function public.listing_stock(text) from public;
grant execute on function public.listing_stock(text) to anon, authenticated;
