-- Publicly-readable seller-tier lookup, used to give Super Premium sellers
-- priority placement in the listings feed.
--
-- Buyers can't read other users' rows in `subscriptions` (RLS limits SELECT to
-- the owner / admins), so the app can't sort listings by the seller's tier on
-- its own. This SECURITY DEFINER function exposes ONLY the derived tier label
-- ('Free' | 'Premium' | 'Super Premium') for a given set of sellers — never any
-- sensitive subscription details.

create or replace function public.seller_tiers(seller_ids uuid[])
returns table(user_id uuid, tier text)
language sql
security definer
set search_path = public
as $$
  select distinct on (s.user_id)
    s.user_id,
    case
      when lower(trim(s.plan)) in ('super premium', 'elite') then 'Super Premium'
      when lower(trim(s.plan)) in ('premium', 'pro', 'basic') then 'Premium'
      else 'Free'
    end as tier
  from public.subscriptions s
  where s.user_id = any(seller_ids)
    and lower(trim(s.status)) in ('approved', 'active')
    and (s.expires_at is null or s.expires_at > now())
  order by s.user_id, s.started_at desc
$$;

grant execute on function public.seller_tiers(uuid[]) to anon, authenticated;

notify pgrst, 'reload schema';
