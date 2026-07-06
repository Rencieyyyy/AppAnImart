-- Offer guard + legacy offer cleanup.
--
-- 1. New/revised offers are rejected while a listing isn't active
--    (reserved/sold/disabled). The feed already hides or locks those
--    listings; this closes the remaining path (stale clients, favorites).
-- 2. One-time cleanup: offers accepted before the transactions migration
--    have no deal record and would show "Accepted" forever — fold them to
--    'declined' so buyers aren't left waiting on a deal that can't proceed.
--
-- Idempotent: safe to re-run.

create or replace function public.block_offers_on_unavailable()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Only fresh/pending offers are gated; the accept/decline updates the
  -- seller makes (and the reserve trigger's auto-declines) pass through.
  if new.status = 'pending'
     and (tg_op = 'INSERT' or new.status is distinct from old.status
          or new.amount is distinct from old.amount) then
    if exists (
      select 1 from public.listings l
       where l.id::text = new.listing_id
         and l.status <> 'active'
    ) then
      raise exception 'This listing is not accepting offers right now.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_block_offers_on_unavailable on public.offers;
create trigger trg_block_offers_on_unavailable
  before insert or update on public.offers
  for each row
  execute function public.block_offers_on_unavailable();

-- Legacy cleanup: accepted offers with no transaction predate the reserve
-- flow. (Their buyers get a decline notice via notify_offer_response —
-- acceptable for the handful of pre-migration test rows.)
update public.offers o
   set status = 'declined',
       updated_at = now()
 where o.status = 'accepted'
   and not exists (
     select 1 from public.transactions t where t.offer_id = o.id
   );
