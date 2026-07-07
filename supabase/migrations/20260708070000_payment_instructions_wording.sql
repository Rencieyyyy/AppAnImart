-- Fix the default payment instructions: they told users to send a receipt
-- SCREENSHOT via Support Chat, but the support chat is text-only. Ask for
-- the GCash reference number instead (which the previous text already told
-- them to keep). Only replaces the un-customized default — an admin-edited
-- value is left alone.
--
-- Idempotent: safe to re-run.

update public.app_settings
   set value =
     'How to pay for your subscription:' || E'\n\n' ||
     '1. Send the exact amount shown to the GCash number above, or scan '
     || 'the QR code in your GCash app.' || E'\n' ||
     '2. Copy the payment reference number from your GCash receipt.' || E'\n' ||
     '3. Send us that reference number (plus the email of your AniMart '
     || 'account) through the Support Chat below.' || E'\n\n' ||
     'An admin will verify your payment and approve your subscription — '
     || 'you will be notified the moment it is approved.',
       updated_at = now()
 where key = 'premium_payment_instructions'
   and value like '%screenshot%';
