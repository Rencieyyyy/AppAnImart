-- Multi-channel seller contact links.
--
-- Sellers were only reachable via a single Facebook Messenger link
-- (20260705050000_users_messenger_link.sql). This adds optional, opt-in
-- public contact channels so a buyer visiting a seller's profile can reach
-- them through whichever app they use: WhatsApp, Viber, a phone call/SMS, or
-- email. The profile page stacks a button for each channel the seller filled.
--
-- These are DELIBERATELY separate from the private registration `phone`
-- column: that number is not public. Sellers type a public contact number
-- here only if they want buyers to have it.
--
-- Idempotent: safe to re-run.

alter table public.users
  add column if not exists contact_phone   text,
  add column if not exists whatsapp_number text,
  add column if not exists viber_number    text,
  add column if not exists contact_email   text;

-- users has column-level SELECT grants (latitude/longitude are revoked for
-- privacy — see 20260707000000_transactions_reserve_flow.sql). Columns added
-- after that migration are NOT covered by the earlier blanket grant, so the
-- new contact columns must be granted explicitly or the seller profile's
-- SELECT would silently drop them. UPDATE is table-wide, so no UPDATE grant
-- is needed for the seller to edit their own row (RLS still scopes the row).
grant select (contact_phone, whatsapp_number, viber_number, contact_email)
  on public.users to authenticated, anon;
