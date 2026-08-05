# Plan-sale push notifications — setup

When an admin puts a subscription plan on sale (admin panel → Premium
Requests → **Edit Premium Pricing**), the pipeline is:

```
admin saves promo on public.prices
  → DB trigger announce_plan_sale()            (migration 20260705010000)
      → posts a formal announcement (tag: promo) → mobile Announcements page
      → queues a row in public.plan_sale_pushes
  → Database Webhook invokes send-plan-sale-push edge function
      → sends FCM push to every token in public.device_push_tokens
      → users' phones show the notification even with the app closed
```

The code is all in place; three one-time setup steps remain because they
need accounts/keys only you can create.

## 1. Apply the migrations

Run the three new migrations on the `kzhlhrhhfupgvpzjllce` project
(SQL Editor, or `npx supabase db push`):

- `20260705000000_offers.sql` — buyer offers (unrelated to push, ships together)
- `20260705010000_plan_sale_announcements.sql` — sale announcement trigger + push queue
- `20260705020000_device_push_tokens.sql` — device token registry

## 2. Firebase (FCM) — makes the phone notification possible

1. Create a project at https://console.firebase.google.com.
2. Add an **Android app** with package name `com.example.ani_mart`.
3. Open **Project settings → General → Your apps** and copy the values into
   `lib/firebase_options.dart` (replace every `REPLACE_ME`). Or run
   `flutterfire configure`, which fills the same values automatically.
   Until this is done the app runs normally with push silently disabled.
4. **Project settings → Service accounts → Generate new private key** —
   download the JSON, then store it as an edge-function secret:

   ```
   npx supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)"
   ```

5. Deploy the function:

   ```
   npx supabase functions deploy send-plan-sale-push
   ```

## 3. Database Webhook — fires the function on each sale

Supabase Dashboard → **Database → Webhooks → Create a new hook**:

- Table: `plan_sale_pushes`, Events: **Insert**
- Type: **Supabase Edge Function** → `send-plan-sale-push`
- Add HTTP header `Authorization: Bearer <anon key>` (the function verifies
  JWTs; the anon key passes and the function takes no meaningful input — it
  only drains its own queue).

The function is idempotent (rows are marked `sent`), so re-invocations or a
scheduled backup trigger (pg_cron) are harmless.

## Notes

- The push body and the announcement text are composed in the DB trigger
  (`announce_plan_sale()`); edit the wording there if needed.
- Promo end time is formatted in **Asia/Manila** time.
- Invalid/rotated device tokens are deleted automatically after a failed send.
- iOS would additionally need an APNs key uploaded to Firebase and the iOS
  app registered; the current setup targets Android first.
