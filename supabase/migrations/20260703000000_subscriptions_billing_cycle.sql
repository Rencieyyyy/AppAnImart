-- Add an explicit billing cycle to subscriptions.
--
-- The app's plans page offers Monthly and Yearly billing, but until now a
-- yearly request could only be inferred from its 10x price (2 months free).
-- This column makes the cycle explicit so both the app and the admin website
-- can tell them apart — e.g. the admin can set `expires_at` to +1 year
-- instead of +1 month when approving a yearly request.
--
-- Idempotent: safe to re-run. Wrapped in a single transaction.

begin;

-- ════════════════════════════════════════════════════════════════════════════
-- 1. Column: 'monthly' (default) or 'yearly'.
-- ════════════════════════════════════════════════════════════════════════════
alter table public.subscriptions
  add column if not exists billing_cycle text not null default 'monthly';

alter table public.subscriptions
  drop constraint if exists subscriptions_billing_cycle_check;

alter table public.subscriptions
  add constraint subscriptions_billing_cycle_check
  check (billing_cycle in ('monthly', 'yearly'));

-- ════════════════════════════════════════════════════════════════════════════
-- 2. Backfill: earlier app versions could only signal a yearly request via a
--    10x price — ₱6,990 (Premium) / ₱12,990 (Super Premium). Mark those rows
--    as yearly; everything else stays monthly.
-- ════════════════════════════════════════════════════════════════════════════
update public.subscriptions
set billing_cycle = 'yearly'
where billing_cycle = 'monthly'
  and price in (6990, 12990);

commit;

-- ════════════════════════════════════════════════════════════════════════════
-- Verification (run separately after applying):
--   select plan, billing_cycle, count(*)
--   from public.subscriptions group by plan, billing_cycle;
-- ════════════════════════════════════════════════════════════════════════════
