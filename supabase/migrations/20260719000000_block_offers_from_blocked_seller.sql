-- Blocked sellers get no buyer actions: reject offers to a seller the buyer
-- has blocked.
--
-- The app hides the buy/offer/message/favourite controls on a blocked
-- seller's listing (product_detail.dart). This is the server-side backstop:
-- even a bypassed client can't insert an offer to a seller the buyer has in
-- their user_blocks. Buyers must unblock the seller first.
--
-- Idempotent: safe to re-run.

drop policy if exists "offers_insert_own" on public.offers;
create policy "offers_insert_own"
  on public.offers
  for insert
  to authenticated
  with check (
    buyer_id = auth.uid()
    and not exists (
      select 1 from public.user_blocks b
       where b.blocker_id = auth.uid()
         and b.blocked_id = offers.seller_id
    )
  );
