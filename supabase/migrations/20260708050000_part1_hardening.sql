-- Part 1 "smaller but real" hardening (docs/app_assessment_and_notification_plan.md):
--
-- 1. Stale-listing nudges: a daily pg_cron job sends each seller one
--    personal announcement (in-app + push, via queue_announcement_push)
--    covering their active listings that have been up for 60+ days, asking
--    them to refresh or mark them Sold. Re-nudges the same listing at most
--    every 60 days (listings.last_nudged_at).
-- 2. Rate limits: a buyer can place at most 10 new offers per hour; a user
--    can file at most 5 reports per 24 hours. Enforced by BEFORE INSERT
--    triggers so stale/modified clients can't bypass them.
-- 3. Account deletion: delete_my_account() removes the caller's listings
--    (and their favorites/cooldown rows, which key on listing_id text with
--    no FK), their subscriptions, their profile row, and finally their
--    auth.users row — everything else (offers, transactions, reviews,
--    reports, blocks, push tokens, personal announcements) cascades from
--    auth.users. Blocked while they have a live reserved deal.
--    NOTE: Cloudinary listing images are not bulk-deleted here (no server
--    credentials for batch deletes); orphaned images are acceptable.
-- 4. app_settings: tiny admin-editable key/value store, seeded with
--    'premium_payment_instructions' — the app shows it after a premium
--    request so users finally know how to pay. Admins should update the
--    row with the real GCash/bank details:
--      update public.app_settings set value = '...', updated_at = now()
--       where key = 'premium_payment_instructions';
--
-- Idempotent: safe to re-run.

-- ══════════════════════════════════════════════════════════════════════════
-- 1. Stale-listing nudges
-- ══════════════════════════════════════════════════════════════════════════
alter table public.listings
  add column if not exists last_nudged_at timestamptz;

create or replace function public.nudge_stale_listings()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id     uuid;
  v_seller       record;
  v_titles       text;
  v_count        int;
  v_title        text;
  v_body         text;
  v_announcement uuid;
begin
  v_admin_id := (select id from public.admins limit 1);
  if v_admin_id is null then return; end if;

  -- One notice per seller per run, covering all their newly-stale posts.
  for v_seller in
    select l.seller_id,
           count(*) as stale_count,
           string_agg('"' || coalesce(nullif(trim(l.title), ''), 'Untitled')
                      || '"', ', ' order by l.created_at) as titles
      from public.listings l
     where l.status = 'active'
       and l.created_at < now() - interval '60 days'
       and coalesce(l.last_nudged_at, 'epoch'::timestamptz)
             < now() - interval '60 days'
       and l.seller_id is not null
     group by l.seller_id
  loop
    v_count := v_seller.stale_count;
    v_titles := v_seller.titles;
    -- Keep the notice readable when many posts are stale.
    if length(v_titles) > 300 then
      v_titles := left(v_titles, 300) || '…';
    end if;

    v_title := case when v_count = 1
                    then 'Is your listing still available?'
                    else format('Are your %s listings still available?', v_count) end;
    v_body :=
      'Dear Seller,' || E'\n\n' ||
      format(
        'The following listing%s been up for over 60 days: %s.',
        case when v_count = 1 then ' has' else 's have' end, v_titles
      ) || E'\n\n' ||
      'If it''s still for sale, consider refreshing the price, photos or '
      || 'description so buyers see it''s active. If it''s already gone, '
      || 'please mark it as Sold or disable it — this keeps the marketplace '
      || 'honest for everyone. Only you can see this notification.' || E'\n\n' ||
      'Thank you for selling on AniMart.' || E'\n' || '— The AniMart Team';

    insert into public.announcements (admin_id, title, body, status, audience, recipient_id)
    values (v_admin_id, v_title, v_body, 'Active', 'sellers', v_seller.seller_id)
    returning id into v_announcement;

    insert into public.announcement_tags (announcement_id, tag)
    values (v_announcement, 'general');

    update public.listings l
       set last_nudged_at = now()
     where l.seller_id = v_seller.seller_id
       and l.status = 'active'
       and l.created_at < now() - interval '60 days'
       and coalesce(l.last_nudged_at, 'epoch'::timestamptz)
             < now() - interval '60 days';
  end loop;
end;
$$;

do $$
begin
  if exists (select 1 from cron.job where jobname = 'nudge-stale-listings') then
    perform cron.unschedule('nudge-stale-listings');
  end if;
end $$;

-- Daily at 19:45 UTC = 3:45 AM Asia/Manila.
select cron.schedule(
  'nudge-stale-listings',
  '45 19 * * *',
  $$select public.nudge_stale_listings()$$
);

-- ══════════════════════════════════════════════════════════════════════════
-- 2. Rate limits on offers and reports
-- ══════════════════════════════════════════════════════════════════════════
create or replace function public.enforce_offer_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select count(*) from public.offers o
       where o.buyer_id = new.buyer_id
         and o.created_at > now() - interval '1 hour') >= 10 then
    raise exception
      'You are sending offers too quickly. Please try again in an hour.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_offer_rate_limit on public.offers;
create trigger trg_enforce_offer_rate_limit
  before insert on public.offers
  for each row
  execute function public.enforce_offer_rate_limit();

create or replace function public.enforce_report_rate_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if (select count(*) from public.reports r
       where r.reporter_id = new.reporter_id
         and r.created_at > now() - interval '24 hours') >= 5 then
    raise exception
      'You have reached the daily limit for reports. Please try again tomorrow.';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_enforce_report_rate_limit on public.reports;
create trigger trg_enforce_report_rate_limit
  before insert on public.reports
  for each row
  execute function public.enforce_report_rate_limit();

-- ══════════════════════════════════════════════════════════════════════════
-- 3. Account deletion
-- ══════════════════════════════════════════════════════════════════════════
create or replace function public.delete_my_account()
returns text  -- null on success, else an error message
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then return 'You must be signed in.'; end if;

  -- A live deal must be resolved first — deleting mid-deal would strand the
  -- other party with a reserved listing.
  if exists (
    select 1 from public.transactions t
     where t.status = 'reserved'
       and (t.buyer_id = v_uid or t.seller_id = v_uid)
  ) then
    return 'You have a reserved deal in progress. Complete or cancel it '
           || 'before deleting your account.';
  end if;

  -- listing_id is text with no FK in these tables — clean them up manually.
  delete from public.favorites f
   where f.listing_id in
     (select l.id::text from public.listings l where l.seller_id = v_uid);
  delete from public.price_drop_notices n
   where n.listing_id in
     (select l.id::text from public.listings l where l.seller_id = v_uid);
  delete from public.listings where seller_id = v_uid;

  -- Rows that may lack ON DELETE CASCADE (admin-repo tables).
  delete from public.subscriptions where user_id = v_uid;
  delete from public.users where id = v_uid;

  -- Everything else (offers, transactions, reviews, reports, user_blocks,
  -- device_push_tokens, personal announcements, favorites-as-buyer, ...)
  -- references auth.users with ON DELETE CASCADE.
  delete from auth.users where id = v_uid;

  return null;
end;
$$;

grant execute on function public.delete_my_account() to authenticated;

-- ══════════════════════════════════════════════════════════════════════════
-- 4. App settings + premium payment instructions
-- ══════════════════════════════════════════════════════════════════════════
create table if not exists public.app_settings (
  key        text primary key,
  value      text not null default '',
  updated_at timestamptz not null default now()
);

alter table public.app_settings enable row level security;

-- Any signed-in user may read settings; only admins write them.
drop policy if exists "app_settings_select_all" on public.app_settings;
create policy "app_settings_select_all"
  on public.app_settings
  for select
  to authenticated
  using (true);

drop policy if exists "app_settings_write_admin" on public.app_settings;
create policy "app_settings_write_admin"
  on public.app_settings
  for all
  to authenticated
  using (exists (select 1 from public.admins a where a.id = auth.uid()))
  with check (exists (select 1 from public.admins a where a.id = auth.uid()));

-- Seed the payment instructions ONLY if absent, so admin edits survive
-- re-running this migration.
insert into public.app_settings (key, value)
values (
  'premium_payment_instructions',
  'How to pay for your subscription:' || E'\n\n' ||
  '1. Send the exact plan amount via GCash or bank transfer.' || E'\n' ||
  '2. Keep your payment reference number.' || E'\n' ||
  '3. Send a screenshot of your receipt to our team via Profile → '
  || 'Customer Service → Support Chat.' || E'\n\n' ||
  'An admin will verify your payment and approve your subscription — you '
  || 'will be notified the moment it is approved.'
)
on conflict (key) do nothing;
