-- Seller Messenger link.
--
-- "Become a Seller" now requires a valid Facebook Messenger link
-- (m.me/... or messenger.com/t/...). Buyers tap "Message Seller on
-- Messenger" on a listing (product_detail.dart) which opens this link, so
-- chat happens on Messenger instead of the old in-app placeholder chat.
--
-- Idempotent: safe to re-run.

alter table public.users
  add column if not exists messenger_link text;
