-- Buyer-interest ("saves") metric for the seller analytics view.
--
-- `favorites` RLS only lets a user read their OWN favorites, so a seller
-- can't count how many buyers saved their listings. This SECURITY DEFINER
-- function exposes ONLY the aggregate count for a given seller — never who
-- saved what.
--
-- `favorites.listing_id` is text (the app passes listing ids around as
-- strings), so the join casts `listings.id` to text; this works whether the
-- id column is a uuid or a bigint.

create or replace function public.seller_saves_count(seller uuid)
returns bigint
language sql
security definer
set search_path = public
as $$
  select count(*)
  from public.favorites f
  join public.listings l on l.id::text = f.listing_id
  where l.seller_id = seller;
$$;

grant execute on function public.seller_saves_count(uuid) to authenticated;

notify pgrst, 'reload schema';
