-- Seller-only deal metrics in cancellation_stats() for the trust formula.
--
-- cancellation_stats().completed_total counts deals where the user was EITHER
-- the buyer or the seller (t.buyer_id = u OR t.seller_id = u). The seller
-- profile used that for its "Sales" stat and the earned "Trusted Seller"
-- badge, so a user's own purchases inflated their seller sales (e.g. showed
-- 5 sales when only 2 were actually sold). This adds seller-scoped metrics:
--   * completed_as_seller — deals the seller actually fulfilled (real sales)
--   * cancelled_as_seller — deals the seller backed out of (their own
--       cancellations), for the reliability term of the seller trust score
--       (SellerRating.trustPercent).
--
-- The return signature changes, so the function must be dropped and recreated
-- (create-or-replace can't alter output columns). Idempotent.

drop function if exists public.cancellation_stats(uuid[]);

create or replace function public.cancellation_stats(p_users uuid[])
returns table (
  user_id             uuid,
  cancelled_90d       int,
  completed_total     int,
  completed_as_seller int,
  cancelled_as_seller int
)
language sql
stable
security definer
set search_path = public
as $$
  select
    u.uid,
    (select count(*) from public.transactions t
      where t.cancelled_by = u.uid
        and t.status = 'cancelled'
        and t.updated_at > now() - interval '90 days')::int,
    (select count(*) from public.transactions t
      where t.status = 'completed'
        and (t.buyer_id = u.uid or t.seller_id = u.uid))::int,
    -- Deals this user completed specifically AS THE SELLER (real sales record).
    (select count(*) from public.transactions t
      where t.status = 'completed'
        and t.seller_id = u.uid)::int,
    -- Deals where this user was the seller and THEY cancelled — the seller
    -- reliability signal (buyer-cancelled deals don't count against them).
    (select count(*) from public.transactions t
      where t.status = 'cancelled'
        and t.seller_id = u.uid
        and t.cancelled_by = u.uid)::int
  from unnest(p_users[1:100]) as u(uid)
  where u.uid is not null;
$$;

grant execute on function public.cancellation_stats(uuid[]) to authenticated;
