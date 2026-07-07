# AniMart — Honest Assessment, Buying Flow & Notification Plan

*Compiled 2026-07-06. Updated 2026-07-07: **Part 1 is fully implemented**
(commit b488f9f — transactions/reserve flow incl. reserved-buyer UX,
My Offers, verified-purchase reviews, paged feeds + server search,
coordinates lockdown; migrations 20260707000000 + 20260707010000 applied).*

*Updated 2026-07-08: **Parts 2 and 3 are fully implemented** (migrations
20260708000000–20260708040000 applied; send-plan-sale-push redeployed with
targeted, claim-first sends).*

- **Part 2:** buyer "Did you receive it?" confirmation +
  `confirm_transaction_received()` + daily pg_cron auto-confirm after 7 days
  (`auto-confirm-transactions`); "Buy at asking price" one-tap offer on the
  listing page; `cancellation_stats()` trust metric (trust score −5 pts per
  deal cancelled in 90 days, "Cancels deals often" chip on buyer offers,
  standing line on the reviews page); "Report a problem" on a deal →
  `reports.transaction_id` + `target_type='transaction'`.
- **Part 3:** every announcement (broadcast or personal) now queues a phone
  push via `queue_announcement_push()` + `plan_sale_pushes.recipient_id` —
  offers both directions, deal events, admin announcements all push;
  subscription approved/rejected → personal notice
  (`notify_subscription_decision()`); new/updated review → seller notice
  (`notify_new_review()`); price drop on favorited listing → favoriter
  notices with a 20-hour per-listing cap (`notify_price_drop()` +
  `price_drop_notices`).

## ⏭ Remaining work — pick up here

**Still open from Part 1's "smaller but real" list:** listing expiry
nudges, real listing links (Copy Link points at a fake domain), account
deletion, in-app payment instructions for premium requests, rate limiting
on offers/reports.

**Part 3 nice-to-haves not yet wired:** subscription about-to-expire
reminder, report-outcome notice, listing-taken-down notice, favorited
listing sold/relisted, stale-listing nudge, welcome notice.

---

## Part 1 — Brutally honest assessment

**The core problem: the app handles everything *around* a sale but not the
sale itself.** Browsing, offers, and trust tooling exist, but the moment a
seller accepts an offer, the app loses the plot — nothing is reserved,
recorded, or resolved. Everything below flows from that.

### Critical gaps

1. **No transaction record — the deal evaporates after "Accept".**
   An accepted offer doesn't reserve the listing, doesn't decrement stock,
   doesn't close competing offers, and produces nothing either party can
   point to later. A seller can accept three offers on the same animal and
   the app sees no problem. "Mark as Sold" is manual and disconnected.
   The "Sales" stat and analytics revenue are inferred from
   `status='sold'` listings, not actual deals — so they're guesses.

2. **Buyers have no "My Offers" view.**
   A buyer sends an offer and it disappears — they can't see
   pending/accepted/declined offers anywhere, can't withdraw one (RLS
   allows delete; no UI), and can't attach a quantity or note. The only
   feedback is the offer-response announcement.

3. **~~Push notifications aren't live.~~** ✅ *Fixed 2026-07-06 —
   Firebase project `animart-5eb9b` configured, edge function deployed,
   webhook created. Plan-sale pushes work end to end. Other notification
   types still need wiring (see Part 3).*

4. **Reviews are unverified.**
   Anyone can review any seller with no purchase behind it — fake 5-stars
   and 1-star bombing are both trivially easy. "Verified Seller" means
   "pays for Premium", which is not what buyers will assume. Trust Score
   shows 100% for a brand-new account.

5. **Scale will hurt.**
   Both feeds `select *` on all listings with no pagination or server-side
   search; filtering is client-side. Fine at 200 listings, painful at
   5,000. The Explore query also embeds every seller's lat/lng from
   `users` — any signed-in user can read every user's stored coordinates.
   That's a privacy issue independent of scale.

### Smaller but real

- Stock is cosmetic — nothing decrements it (except the manual
  sold/relist flow).
- No listing expiry, so dead posts pile up.
- "Copy Link" copies a fake `farm.app` URL that leads nowhere.
- Messenger link is validated for shape, never for liveness; users
  without Facebook are excluded.
- No account deletion.
- Premium requests have no in-app payment instructions (user requests →
  admin approves, but the app never says how to pay).
- No rate limiting on offers/reports.

---

## Part 2 — Proposed buying flow: "Reserve → Messenger → Confirm"

Negotiation stays on Messenger by design. The app should still own the
**state** of the deal, because Messenger can't. The app is the referee;
Messenger is the conversation.

1. **Offer (in-app).** Buyer taps Make Offer with amount, quantity, and an
   optional note — or "Buy at asking price" (an auto-filled offer). The
   deal has a paper trail before the chat starts.

2. **Accept = Reserve (in-app, automatic).** Accepting creates a
   `transactions` row (listing, buyer, seller, agreed price, qty,
   `status='reserved'`) and, in the same trigger: auto-declines other
   pending offers on that listing (with "item was reserved by another
   buyer" notifications), holds the stock, and puts a **Reserved** badge
   on the listing. Fixes double-selling and closes the loop for losing
   bidders.

3. **Hand off to Messenger (outside app).** Both parties get a
   notification whose single CTA is "Continue on Messenger". Payment and
   logistics (COD, GCash between themselves, meetup) happen there. The
   in-app transaction card stays the source of truth for *what was
   agreed*.

4. **Confirm completion (in-app).** Seller taps "Mark completed"; buyer
   gets a "Did you receive it?" prompt (auto-confirm after ~7 days). On
   completion: stock decrements, listing auto-flips to Sold at zero
   stock, and Sales/analytics count from transactions instead of listing
   statuses.

5. **Review gate.** Only a buyer with a completed transaction can review
   that seller; one review per transaction. This single rule makes the
   review/Trust Score system meaningful.

6. **Cancel / dispute.** Either party can cancel a reservation with a
   reason (stock restored, listing back to active); repeated
   cancellations feed a real trust metric. "Report a problem" on the
   transaction files into the existing `reports` table with deal context.

**Infrastructure cost:** one `transactions` table, a trigger for
sibling-offer auto-decline (the announcement/notification pipeline is
reusable as-is), a "My Offers / My Purchases" page, and a
`transaction_id` requirement on reviews.

### Overall work order

① ~~Turn on Firebase push~~ ✅ done → ② transactions/reserve flow →
③ My Offers page → ④ transaction-gated reviews → ⑤ pagination +
server-side search → ⑥ stop exposing user coordinates.

---

## Part 3 — Notification map

### Admin website → mobile app

| Event | Who gets it | Today | Priority |
|---|---|---|---|
| Plan sale / discount | Everyone | ✅ In-app + push | done |
| General announcements (news, urgent, events) | Everyone | ⚠️ In-app only, no push | High |
| **Subscription request approved/rejected** | Requesting user | ❌ Nothing | **Highest** |
| Subscription about to expire / expired | Subscriber | ❌ Nothing | Medium |
| Report outcome ("we reviewed your report") | Reporter | ❌ Nothing | Medium |
| Listing taken down / disabled by admin | Listing owner | ❌ Nothing | Medium |

The subscription gap is the most glaring in the app: a user requests
Premium, pays outside the app, then hears nothing. Approval should fire a
personal announcement + push the moment the admin approves (same trigger
pattern as offer notices, on the `subscriptions` status change).

### Mobile app → mobile app (user to user)

| Event | Who gets it | Today | Priority |
|---|---|---|---|
| New offer / revised offer | Seller | ⚠️ In-app + red dot, no push | High |
| Offer accepted / declined | Buyer | ⚠️ In-app only, no push | High |
| **New review received** | Seller | ❌ Nothing | High |
| Listing you offered on sold to someone else | Losing bidders | ❌ Needs the transactions flow | High (blocked) |
| Price drop on a favorited listing | Favoriters | ❌ Nothing | Medium — re-engagement hook |
| Favorited listing sold / relisted | Favoriters | ❌ Nothing | Low–Medium |
| Someone favorited your listing | Seller | ❌ Nothing | Low — digest at most |

### System / lifecycle

- **Stale listing nudge** — "up 60 days, still available?" Keeps the feed
  honest. Missing.
- **Welcome / become-a-seller confirmation** — onboarding nice-to-have.
  Missing.

### Architecture rule

Everything flows through the existing pattern:

```
DB trigger on the event table
  → personal/broadcast announcement  (in-app record, red dot)
  → row in the push queue (plan_sale_pushes, + recipient_id for targeted)
      → Database Webhook → send-plan-sale-push edge function → FCM
```

One pipeline, one webhook, one edge function. Each new notification type
is one more small database trigger.

### Notification work order

1. **Push for what already notifies in-app** — offers (both directions)
   and admin announcements. One migration (add
   `plan_sale_pushes.recipient_id`, trigger on `announcements` insert,
   drop the duplicate queue insert in `announce_plan_sale()`) + edge
   function support for targeted sends.
2. **Subscription approved/rejected** — trigger on `subscriptions`
   status change → personal announcement + push.
3. **New review → seller** — trigger on `reviews` insert.
4. **Price drop → favoriters** — trigger on `listings` price decrease,
   fan out to `favorites`; needs a cap so five edits in an hour don't
   fire five pushes.
5. **Sold-to-someone-else** — fold into the Reserve/transactions flow.

Spam rule of thumb: broadcast pushes only for things users can act on
(sales, announcements); everything else targeted to one user. If admin
announcement volume grows, add a "send push" checkbox in the admin
composer or rate-limit in the trigger.
