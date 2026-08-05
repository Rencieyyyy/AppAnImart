-- Add the opt-in seller contact channels to public_profiles.
--
-- public_profiles is the PII-safe projection of users that the app reads for
-- OTHER people's profiles; the pending users-PII lockdown will end cross-user
-- SELECTs on the base table. The view was created without the seller contact
-- columns, but those are opt-in public BY DESIGN
-- (20260717000000_users_contact_channels.sql grants them to anon): a seller
-- types a public contact number/link only if they want buyers to have it.
-- Without them the seller contact card (Messenger / WhatsApp / Viber / SMS /
-- email buttons) goes blank the moment the lockdown ships.
--
-- Registration `phone` / `email` stay OUT of the view — they are private.
--
-- CREATE OR REPLACE appends columns only, preserving the existing owner
-- (postgres), grants (SELECT to authenticated) and security_invoker=false,
-- so the view keeps bypassing users RLS and exposes exactly this column list.
--
-- Idempotent: safe to re-run.

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
  -- Opt-in public contact channels (see 20260717000000).
  messenger_link,
  contact_phone,
  whatsapp_number,
  viber_number,
  contact_email
from public.users;
