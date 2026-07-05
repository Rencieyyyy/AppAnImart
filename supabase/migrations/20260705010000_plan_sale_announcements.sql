-- Auto-announce subscription plan sales.
--
-- When an admin puts a plan on sale in the admin panel (Premium Requests →
-- "Edit Premium Pricing": a discount %, optional promo label and a promo
-- deadline saved to public.prices), a trigger composes a formal announcement
-- and posts it to public.announcements with the 'promo' tag, so it appears on
-- the mobile app's Announcements page immediately.
--
-- It also notifies the push pipeline: a row is queued in
-- public.plan_sale_pushes, which the send-plan-sale-push edge function (see
-- supabase/functions/send-plan-sale-push) drains via a scheduled invocation
-- or a Database Webhook — that is what reaches users' phones even when the
-- app is closed (see 20260705020000_device_push_tokens.sql).
--
-- The trigger function is SECURITY DEFINER because the announcements RLS
-- only allows admin inserts and the pg_cron promo-reset job runs as the
-- postgres role.
--
-- Idempotent: safe to re-run.

-- ── Queue of sale pushes for the edge function ──────────────────────────────
create table if not exists public.plan_sale_pushes (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  body       text not null,
  sent       boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.plan_sale_pushes enable row level security;
-- No client policies on purpose: only the service role (edge function) and
-- the SECURITY DEFINER trigger below touch this table.

-- ── Number formatting helper ────────────────────────────────────────────────
-- Renders a numeric as plain text: whole numbers keep all their digits
-- (30 → '30', 100 → '100'), fractional amounts keep two decimals
-- (559.2 → '559.20'). A naive trim(trailing '0') is wrong here — it eats the
-- zeros of round numbers and turned "30% off" into "3% off".
create or replace function public.fmt_amount(x numeric)
returns text
language sql
immutable
as $$
  select case
    when round(x, 2) % 1 = 0 then trunc(round(x, 2))::text
    else round(x, 2)::text
  end;
$$;

-- ── The announcement composer ───────────────────────────────────────────────
create or replace function public.announce_plan_sale()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id      uuid;
  v_title         text;
  v_body          text;
  v_sale_price    numeric;
  v_deadline_text text;
  v_discount_text text;
  v_announcement  uuid;
begin
  -- Only react when a live discount is (re)configured. The pg_cron job that
  -- clears expired promos sets discount_percent back to 0 and must not
  -- announce anything.
  if coalesce(new.discount_percent, 0) <= 0 then
    return new;
  end if;
  if new.discount_percent is not distinct from old.discount_percent
     and new.promo_deadline is not distinct from old.promo_deadline
     and coalesce(new.promo_label, '') = coalesce(old.promo_label, '') then
    return new;  -- unrelated edit (e.g. tagline/capacity); no announcement
  end if;

  -- Author: the admin who saved the promo, or any admin as a fallback (the
  -- announcements table requires an admin author for the app's author card).
  v_admin_id := coalesce(
    public.current_admin_id(),
    (select id from public.admins limit 1)
  );
  if v_admin_id is null then
    return new;  -- no admin account to attribute the post to
  end if;

  v_sale_price := round(new.price * (1 - new.discount_percent / 100), 2);
  v_discount_text := public.fmt_amount(new.discount_percent);

  if new.promo_deadline is not null then
    v_deadline_text := to_char(
      new.promo_deadline at time zone 'Asia/Manila',
      'FMMonth FMDD, YYYY "at" FMHH12:MI AM');
  end if;

  v_title := format('%s Plan Sale — %s%% Off', new.name, v_discount_text);

  v_body :=
    'Dear AniMart users,' || E'\n\n' ||
    format(
      'We are pleased to announce that the %s subscription plan is now on sale. '
      || 'For a limited time, enjoy %s%% off the regular monthly price: the plan '
      || 'is reduced from ₱%s to ₱%s per month.',
      new.name, v_discount_text,
      public.fmt_amount(new.price),
      public.fmt_amount(v_sale_price)
    ) || E'\n\n' ||
    case
      when v_deadline_text is not null then
        format(
          'This promotion will end on %s (Philippine Time). We encourage you to '
          || 'take advantage of this offer before it expires.',
          v_deadline_text)
      else
        'This promotion is available for a limited time only. We encourage you '
        || 'to take advantage of this offer while it lasts.'
    end || E'\n\n' ||
    'To upgrade, open the app and go to Profile → Premium Subscription.'
    || E'\n\n' ||
    'Thank you for being part of AniMart.' || E'\n' ||
    '— The AniMart Team';

  -- 'Active' matches the admin panel's uiStatusToDb() casing.
  insert into public.announcements (admin_id, title, body, status, audience)
  values (v_admin_id, v_title, v_body, 'Active', 'all')
  returning id into v_announcement;

  insert into public.announcement_tags (announcement_id, tag)
  values (v_announcement, 'promo');

  -- Queue the device push so phones are notified even with the app closed.
  insert into public.plan_sale_pushes (title, body)
  values (
    v_title,
    format(
      '%s is now ₱%s/month (%s%% off)%s. Open AniMart to upgrade.',
      new.name,
      public.fmt_amount(v_sale_price),
      v_discount_text,
      case when v_deadline_text is not null
           then ' until ' || v_deadline_text else '' end
    )
  );

  return new;
exception when others then
  -- Never block the admin's pricing save because announcing failed.
  raise warning 'announce_plan_sale failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists trg_announce_plan_sale on public.prices;
create trigger trg_announce_plan_sale
  after update on public.prices
  for each row
  execute function public.announce_plan_sale();
