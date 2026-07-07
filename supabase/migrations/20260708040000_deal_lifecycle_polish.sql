-- Deal lifecycle polish (Part 2 of
-- docs/app_assessment_and_notification_plan.md):
--
-- 1. Buyer confirmation step. The seller's "Complete" no longer ends the
--    story: the buyer gets a "Did you receive it?" prompt (in My Offers) and
--    confirms via confirm_transaction_received(). A daily pg_cron job
--    auto-confirms deals the buyer has ignored for 7 days. Until confirmed,
--    a completed deal is only seller-confirmed (surfaced in both parties'
--    UIs).
-- 2. Cancellation trust metric. cancellation_stats() reports how many deals
--    a user cancelled in the last 90 days (vs. completed overall), so the
--    app can show a standing signal on seller profiles and buyer offers.
-- 3. "Report a problem" on a transaction. reports gains a transaction_id and
--    a 'transaction' target type, so reports can carry deal context.
--
-- Idempotent: safe to re-run.

-- ── 1a. Buyer confirmation column ────────────────────────────────────────────
alter table public.transactions
  add column if not exists buyer_confirmed_at timestamptz;

-- ── 1b. Buyer confirms receipt ───────────────────────────────────────────────
create or replace function public.confirm_transaction_received(p_tx uuid)
returns text  -- null on success, else an error message
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tx            public.transactions%rowtype;
  v_admin_id      uuid;
  v_listing_title text;
  v_buyer_name    text;
  v_announcement  uuid;
begin
  select * into v_tx from public.transactions where id = p_tx;
  if not found then return 'Transaction not found.'; end if;
  if v_tx.buyer_id <> auth.uid() then
    return 'Only the buyer can confirm receipt.';
  end if;
  if v_tx.status = 'reserved' then
    return 'The seller has not marked this deal completed yet.';
  end if;
  if v_tx.status <> 'completed' then
    return 'This transaction is ' || v_tx.status || '.';
  end if;
  if v_tx.buyer_confirmed_at is not null then
    return null;  -- already confirmed; treat as success
  end if;

  update public.transactions
     set buyer_confirmed_at = now(),
         updated_at = now()
   where id = p_tx;

  -- Close the loop for the seller with a personal notice (in-app + push).
  v_admin_id := coalesce(
    public.current_admin_id(),
    (select id from public.admins limit 1)
  );
  if v_admin_id is not null then
    select l.title into v_listing_title
      from public.listings l where l.id::text = v_tx.listing_id;
    v_listing_title := coalesce(nullif(trim(v_listing_title), ''), 'your listing');
    select coalesce(nullif(trim(u.name), ''), 'The buyer')
      into v_buyer_name from public.users u where u.id = v_tx.buyer_id;

    insert into public.announcements (admin_id, title, body, status, audience, recipient_id)
    values (
      v_admin_id,
      format('Order Received — "%s"', v_listing_title),
      'Dear Seller,' || E'\n\n' ||
      format(
        '%s has confirmed receiving their order of "%s" (₱%s). This deal is '
        || 'now fully closed.',
        coalesce(v_buyer_name, 'The buyer'), v_listing_title,
        public.fmt_amount(v_tx.agreed_price)
      ) || E'\n\n' ||
      'Only you can see this notification.' || E'\n\n' ||
      'Thank you for selling on AniMart.' || E'\n' || '— The AniMart Team',
      'Active', 'sellers', v_tx.seller_id)
    returning id into v_announcement;

    insert into public.announcement_tags (announcement_id, tag)
    values (v_announcement, 'offer');
  end if;

  return null;
end;
$$;

grant execute on function public.confirm_transaction_received(uuid) to authenticated;

-- ── 1c. Auto-confirm after 7 days ────────────────────────────────────────────
create extension if not exists pg_cron;

create or replace function public.auto_confirm_transactions()
returns void
language sql
security definer
set search_path = public
as $$
  update public.transactions
     set buyer_confirmed_at = now(),
         updated_at = now()
   where status = 'completed'
     and buyer_confirmed_at is null
     and completed_at < now() - interval '7 days';
$$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'auto-confirm-transactions') then
    perform cron.unschedule('auto-confirm-transactions');
  end if;
end $$;

-- Daily at 19:15 UTC = 3:15 AM Asia/Manila.
select cron.schedule(
  'auto-confirm-transactions',
  '15 19 * * *',
  $$select public.auto_confirm_transactions()$$
);

-- Legacy rows completed before this migration count as confirmed — their
-- buyers were never shown the prompt, and the review gate already passed.
update public.transactions
   set buyer_confirmed_at = coalesce(completed_at, updated_at, now())
 where status = 'completed'
   and buyer_confirmed_at is null
   and completed_at < now() - interval '7 days';

-- ── 1d. The buyer's "completed" notice now asks them to confirm receipt ─────
-- Same function as 20260707000000, with the completed-branch body updated.
create or replace function public.notify_transaction_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id      uuid;
  v_listing_title text;
  v_recipient     uuid;
  v_other_name    text;
  v_title         text;
  v_body          text;
  v_announcement  uuid;
begin
  if new.status not in ('completed', 'cancelled')
     or new.status is not distinct from old.status then
    return new;
  end if;

  v_admin_id := coalesce(
    public.current_admin_id(),
    (select id from public.admins limit 1)
  );
  if v_admin_id is null then return new; end if;

  select l.title into v_listing_title
    from public.listings l where l.id::text = new.listing_id;
  v_listing_title := coalesce(nullif(trim(v_listing_title), ''), 'the listing');

  if new.status = 'completed' then
    -- Tell the buyer; they should confirm receipt, then rate the seller.
    v_recipient := new.buyer_id;
    select coalesce(nullif(trim(u.name), ''), 'The seller')
      into v_other_name from public.users u where u.id = new.seller_id;
    v_title := format('Purchase Completed — "%s"', v_listing_title);
    v_body :=
      'Dear Buyer,' || E'\n\n' ||
      format(
        'Your purchase of "%s" (₱%s) has been marked completed by %s.',
        v_listing_title, public.fmt_amount(new.agreed_price),
        coalesce(v_other_name, 'the seller')
      ) || E'\n\n' ||
      'Did you receive your order? Please confirm it in Profile → My Offers '
      || '(deals confirm automatically after 7 days). You can then rate this '
      || 'seller — your review helps other buyers. Only you can see this '
      || 'notification.' || E'\n\n' ||
      'Thank you for buying on AniMart.' || E'\n' || '— The AniMart Team';
  else
    -- Tell the party who did NOT cancel.
    v_recipient := case when new.cancelled_by = new.buyer_id
                        then new.seller_id else new.buyer_id end;
    select coalesce(nullif(trim(u.name), ''), 'The other party')
      into v_other_name from public.users u where u.id = new.cancelled_by;
    v_title := format('Transaction Cancelled — "%s"', v_listing_title);
    v_body :=
      'Hello,' || E'\n\n' ||
      format(
        'The reserved transaction for "%s" (₱%s) was cancelled by %s.%s',
        v_listing_title, public.fmt_amount(new.agreed_price),
        coalesce(v_other_name, 'the other party'),
        case when new.cancel_reason is not null
             then E'\n\nReason: ' || new.cancel_reason else '' end
      ) || E'\n\n' ||
      'The listing is available again. Only you can see this notification.'
      || E'\n\n' || '— The AniMart Team';
  end if;

  insert into public.announcements (admin_id, title, body, status, audience, recipient_id)
  values (v_admin_id, v_title, v_body, 'Active',
          case when v_recipient = new.buyer_id then 'buyers' else 'sellers' end,
          v_recipient)
  returning id into v_announcement;

  insert into public.announcement_tags (announcement_id, tag)
  values (v_announcement, 'offer');

  return new;
exception when others then
  raise warning 'notify_transaction_event failed: %', sqlerrm;
  return new;
end;
$$;

-- ── 2. Cancellation trust metric ─────────────────────────────────────────────
-- Batch lookup so a page can resolve standing for several users in one call
-- (capped at 100 ids). SECURITY DEFINER because the transactions RLS only
-- shows a user their own deals — this exposes nothing but two counts.
create or replace function public.cancellation_stats(p_users uuid[])
returns table (
  user_id         uuid,
  cancelled_90d   int,
  completed_total int
)
language sql
stable
security definer
set search_path = public
as $$
  select
    u.uid,
    (select count(*) from public.transactions t
      where t.cancelled_by = u.uid
        and t.status = 'cancelled'
        and t.updated_at > now() - interval '90 days')::int,
    (select count(*) from public.transactions t
      where t.status = 'completed'
        and (t.buyer_id = u.uid or t.seller_id = u.uid))::int
  from unnest(p_users[1:100]) as u(uid)
  where u.uid is not null;
$$;

grant execute on function public.cancellation_stats(uuid[]) to authenticated;

-- ── 3. Reports carry deal context ────────────────────────────────────────────
alter table public.reports
  add column if not exists transaction_id uuid references public.transactions (id) on delete set null;

-- Extend the target_type allow-list with 'transaction' (drop whatever CHECK
-- currently guards the column, then re-add).
do $$
declare
  r record;
begin
  for r in
    select conname
      from pg_constraint
     where conrelid = 'public.reports'::regclass
       and contype = 'c'
       and pg_get_constraintdef(oid) ilike '%target_type%'
  loop
    execute format('alter table public.reports drop constraint %I', r.conname);
  end loop;
end $$;

alter table public.reports
  add constraint reports_target_type_check
  check (target_type in ('listing', 'seller', 'transaction'));
