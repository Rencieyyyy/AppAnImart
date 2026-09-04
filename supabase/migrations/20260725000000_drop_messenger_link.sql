-- Retire the seller Messenger link.


-- ── 1. Rebuild the PII-safe projection without messenger_link ───────────────

drop view if exists public.public_profiles;

create view public.public_profiles
  with (security_invoker = false) as
select
  id,
  name,
  avatar_url,
  is_seller,
  is_verified,
  trust_score,
  sales_count,
  business_name,
  shop_category,
  shop_description,
  location_name,
  member_since,
  created_at,
  -- Opt-in public contact channels (see 20260717000000, 20260721000000).
  -- All optional now: the in-app chat is the guaranteed way to reach a seller.
  contact_phone,
  whatsapp_number,
  viber_number,
  contact_email,
  facebook_url
from public.users;

-- security_invoker = false makes the view run as its OWNER, which is how it
-- bypasses users' RLS. Recreating it reset the owner to whoever ran this, so
-- pin it back to postgres.
alter view public.public_profiles owner to postgres;

-- Grants don't survive a DROP either — restore the read access the app needs.
grant select on public.public_profiles to authenticated, anon;

-- ── 2. Drop the column ──────────────────────────────────────────────────────

alter table public.users drop column if exists messenger_link;

notify pgrst, 'reload schema';
