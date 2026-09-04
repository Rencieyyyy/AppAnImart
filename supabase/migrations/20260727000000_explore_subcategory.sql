-- Explore browse-by-category: carry `subcategory` through the feed.

drop function if exists public.explore_listings(text, int, int);

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
  subcategory text,
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
as $fn$
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
    l.subcategory,
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
      or l.subcategory ilike '%' || trim(p_search) || '%'
      or l.breed ilike '%' || trim(p_search) || '%'
      or l.location ilike '%' || trim(p_search) || '%'
    )
  order by l.created_at desc
  limit greatest(p_limit, 1)
  offset greatest(p_offset, 0);
$fn$;

grant execute on function public.explore_listings(text, int, int) to authenticated;

notify pgrst, 'reload schema';
