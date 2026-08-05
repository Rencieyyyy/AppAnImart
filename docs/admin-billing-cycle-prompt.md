# Prompt for the admin website: support the new `billing_cycle` column

Copy everything below the line into a session on the admin website project.

---

The AniMart mobile app now lets sellers request **yearly** billing for paid
plans, and the shared `subscriptions` table has a new column to carry it. The
migration (already applied to the shared Supabase database by the app repo,
file `20260703000000_subscriptions_billing_cycle.sql`) did the following:

- Added `subscriptions.billing_cycle text not null default 'monthly'` with a
  check constraint allowing only `'monthly'` or `'yearly'`.
- Backfilled `'yearly'` onto old rows whose price was ₱6,990 or ₱12,990 (the
  only way earlier app versions could signal a yearly request).

How the app writes requests now:

- A monthly request inserts `billing_cycle = 'monthly'` and the plan's monthly
  price (Premium ₱699, Super Premium ₱1,299).
- A yearly request inserts `billing_cycle = 'yearly'` and 10× the monthly
  price — 2 months free (Premium ₱6,990, Super Premium ₱12,990).
- Plan names are unchanged: `'Free' | 'Premium' | 'Super Premium'`.
- Yearly requests can come from members who already hold an approved monthly
  subscription for the **same** plan — that is a billing-cycle upgrade, not a
  duplicate.

Please update the admin website so it fetches and honours this column:

1. **Pending requests queue** — select `billing_cycle` along with the existing
   fields and display it on each request (e.g. a "Monthly" / "Yearly" chip
   next to the plan name) so admins can tell a ₱6,990 yearly Premium apart
   from a custom-priced monthly one.
2. **Approval flow** — when approving a request, set `expires_at` based on the
   cycle: `started_at + 1 year` for `'yearly'`, keeping the existing
   `+ 1 month` for `'monthly'`. Do not change the row's `billing_cycle`.
3. **Subscription lists / member detail pages** — show the billing cycle
   wherever a subscription's plan and price are shown, and add it to any
   filters or CSV/report exports of subscriptions.
4. **Revenue / analytics** — anywhere revenue is aggregated from
   `subscriptions.price`, treat the stored price as the full amount for its
   cycle (a yearly row's price is the whole year, not a monthly rate), so
   monthly-recurring-revenue style metrics should divide yearly prices by 12
   or report the two cycles separately.
5. **Legacy safety** — rows without an explicit value default to
   `'monthly'`; treat missing/null as monthly everywhere.

Nothing else about the flow changed: requests still arrive with
`status = 'pending'`, admins still approve/reject/expire them, and RLS is
unchanged (users insert/read their own rows, admins manage everything).
