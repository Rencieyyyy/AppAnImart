-- GCash payment details for the in-app payment screen.
--
-- The mobile app's "Pay with GCash" sheet (Premium Subscription page) reads
-- these app_settings keys:
--   gcash_number        — the GCash mobile number users send payment to
--   gcash_account_name  — the registered account name shown for confidence
--   gcash_qr_url        — public URL of the GCash QR code image
-- plus the existing premium_payment_instructions text.
--
-- The values are managed from the ADMIN website by the SUPER ADMIN only
-- (regular admins must not edit them) — the role split, the write policy
-- carve-out for these keys, and the QR upload UI live in the admin repo's
-- migrations. Seeded empty here so the app degrades gracefully (the sheet
-- hides the number/QR sections until they're configured).
--
-- Idempotent: safe to re-run (never overwrites configured values).

insert into public.app_settings (key, value) values
  ('gcash_number', ''),
  ('gcash_account_name', ''),
  ('gcash_qr_url', '')
on conflict (key) do nothing;
