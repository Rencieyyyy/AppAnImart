-- Pay-first flow: capture the GCash reference number in the app itself.
--
-- The payment instructions told users to send their reference number through
-- the Support Chat, but the new "Pay with GCash" checkout sheet now has a
-- dedicated field for it — the number is stored on the request row alongside
-- the receipt so the admin can verify both in one place.
--
-- 1. New column `subscriptions.reference_number` (nullable — legacy requests
--    predate it, same as `receipt_url`).
-- 2. Update the un-customized default instructions: step 3 now points at the
--    in-app field instead of the Support Chat. An admin-edited value is left
--    alone.
--
-- Idempotent: safe to re-run.

alter table public.subscriptions
  add column if not exists reference_number text;

update public.app_settings
   set value =
     'How to pay for your subscription:' || E'\n\n' ||
     '1. Send the exact amount shown to the GCash number above, or scan '
     || 'the QR code in your GCash app.' || E'\n' ||
     '2. Copy the payment reference number from your GCash receipt.' || E'\n' ||
     '3. Enter that reference number in the field provided below.' || E'\n' ||
     '4. Attach a screenshot of your GCash receipt, then submit your '
     || 'request.' || E'\n\n' ||
     'An admin will verify your payment and approve your subscription — '
     || 'you will be notified the moment it is approved.',
       updated_at = now()
 where key = 'premium_payment_instructions'
   and value like '%through the Support Chat below%';
