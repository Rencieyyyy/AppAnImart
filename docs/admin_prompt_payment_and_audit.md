# Prompt for the ADMIN website repo (paste into Claude Code there)

*Written 2026-07-08 from the mobile-app repo. The mobile app side is already
live: the "Pay with GCash" sheet reads `app_settings` keys `gcash_number`,
`gcash_account_name`, `gcash_qr_url`, `premium_payment_instructions` (all
seeded, GCash ones empty). This prompt adds the admin-side management UI,
the super-admin role split, and audit logs.*

---

Implement three features on this admin website. It shares the Supabase
project `kzhlhrhhfupgvpzjllce` with the AniMart mobile app, so the database
contracts below must be kept exactly.

## Context you must not break

- `public.app_settings` already exists (created by the mobile repo,
  migration `20260708050000`): `key text primary key, value text not null
  default '', updated_at timestamptz`. RLS: any authenticated user may
  SELECT; there is a permissive write policy `app_settings_write_admin`
  allowing anyone in `public.admins` to INSERT/UPDATE/DELETE.
- The mobile app reads these keys and renders a "Pay with GCash" payment
  sheet: `gcash_number`, `gcash_account_name`, `gcash_qr_url` (a public
  image URL), and `premium_payment_instructions` (plain text, shown
  verbatim). Empty values hide their section in the app — never delete the
  rows, just blank them.
- `public.admins` is the existing admins table (admin panel sessions are
  Supabase auth users whose id exists there). `public.current_admin_id()`
  already exists and returns the caller's admin id or null.
- Many DB triggers from the mobile repo attribute announcements to
  `coalesce(public.current_admin_id(), (select id from admins limit 1))` —
  do not rename or drop `current_admin_id()` or the `admins` table.

## 1. Super admin role

- Add `role text not null default 'admin' check (role in ('admin',
  'super_admin'))` to `public.admins`. Promote exactly one account to
  `super_admin` (make this a documented one-line SQL update; also show the
  role on the admin's profile/header in the UI).
- Add a helper `public.is_super_admin()` (SECURITY DEFINER, returns
  boolean: caller exists in admins with role 'super_admin').
- The UI must reflect the role: regular admins never see the Payment
  Settings editor or the Audit Logs page (hide the nav entries AND guard
  the routes).

## 2. GCash payment settings (super admin only)

- New "Payment Settings" page: fields for **GCash number**, **account
  name**, a **QR code image upload**, and the **payment instructions
  text**. Saving writes the four `app_settings` keys above.
- QR upload: store the image in a new Supabase Storage bucket
  `payment-qr` with public READ (the mobile app loads the URL with no
  auth) and super-admin-only write. Save the public URL into
  `app_settings.gcash_qr_url`. Replace-on-upload is fine (fixed object
  name, e.g. `gcash-qr.png` + cache-busting query param in the stored URL).
- **Enforce at the database, not just the UI**: regular admins must NOT be
  able to edit the GCash keys. Replace/augment the app_settings policies:
  - keep admin-wide write access for non-protected keys;
  - add a RESTRICTIVE policy (or rewrite the permissive one) so that rows
    with `key in ('gcash_number','gcash_account_name','gcash_qr_url',
    'premium_payment_instructions')` can only be INSERTed/UPDATEd/DELETEd
    when `public.is_super_admin()`.
  - Storage policies on `payment-qr`: public select, super-admin-only
    insert/update/delete.
- Show a preview of exactly what the mobile app will display (amount
  aside): number, name, QR image, instructions.

## 3. Audit logs (visible to super admin only)

- New table `public.audit_logs`: `id uuid pk default gen_random_uuid()`,
  `admin_id uuid references public.admins(id) on delete set null`,
  `admin_email text` (denormalised so logs survive admin deletion),
  `action text` (short slug, e.g. 'subscription.approve'),
  `target_type text`, `target_id text`, `details jsonb`,
  `created_at timestamptz default now()`. Index on `(created_at desc)` and
  `(admin_id, created_at desc)`.
- RLS: SELECT only when `public.is_super_admin()`. No client
  INSERT/UPDATE/DELETE policies — writes happen via SECURITY DEFINER
  triggers so admins cannot skip or forge them.
- **Log via DB triggers** (capture `auth.uid()` only when it is an admin;
  skip otherwise so mobile-app user actions are never logged):
  - `subscriptions` UPDATE → 'subscription.approve' / 'subscription.reject'
    / 'subscription.update' with user_id, plan, price in details;
  - `listings` UPDATE of status by an admin → 'listing.disable' /
    'listing.enable'; DELETE → 'listing.delete';
  - `announcements` INSERT/UPDATE/DELETE by an admin (skip rows created by
    the notification trigger functions — those are SECURITY DEFINER
    inserts attributed to an admin id but fired by user actions; simplest
    reliable filter: only log when `auth.uid()` is an admin AND the
    announcement has no `recipient_id`);
  - `prices` UPDATE → 'pricing.update' (include old/new price and
    discount);
  - `reports` UPDATE → 'report.review' / 'report.dismiss';
  - `app_settings` INSERT/UPDATE/DELETE → 'settings.update' with the key
    and old/new values (this is how GCash-detail changes are audited);
  - `users` UPDATE of `is_verified` by an admin → 'user.approve' /
    'user.unverify'.
- New "Audit Logs" page (super admin only): reverse-chronological table
  with admin name/email, action, target, details (pretty JSON expandable),
  timestamp (Asia/Manila); filters by admin, action type, and date range;
  paginate server-side.
- Keep it append-only: no delete button. Optionally add a pg_cron purge of
  logs older than 1 year.

## Notes

- Write everything as idempotent SQL migrations in this repo's migrations
  folder and apply with `npx supabase db push --linked`.
- After the schema work, wire the two pages into the existing admin
  navigation and test with BOTH roles: a regular admin must get a
  database error (not just hidden UI) when trying to update
  `app_settings.gcash_number`, and must get zero rows selecting from
  `audit_logs`.
- Finally, have the super admin fill in the real GCash number, account
  name, QR image, and (optionally) tune `premium_payment_instructions` —
  the mobile app starts showing them immediately, no app release needed.
