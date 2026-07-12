-- Facebook as an opt-in seller contact channel.
--
-- Same pattern as 20260717000000_users_contact_channels.sql: an optional,
-- opt-in public link a seller fills in only if they want buyers to find
-- their Facebook page/profile. Shown as a button on the seller contact card.
--
-- users has column-level SELECT grants, so the new column must be granted
-- explicitly or profile SELECTs listing it would fail. The column is also
-- appended to public_profiles (the PII-safe view all cross-user reads use;
-- see 20260720000000) so it stays readable after the users PII lockdown.
--
-- Idempotent: safe to re-run.

alter table public.users
  add column if not exists facebook_url text;

grant select (facebook_url) on public.users to authenticated, anon;

create or replace view public.public_profiles
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
  messenger_link,
  contact_phone,
  whatsapp_number,
  viber_number,
  contact_email,
  facebook_url
from public.users;
