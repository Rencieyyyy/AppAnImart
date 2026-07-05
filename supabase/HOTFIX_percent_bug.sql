-- ═══════════════════════════════════════════════════════════════════════════
-- HOTFIX — plan-sale announcement shows wrong % (20% → "2%", 100% → "1%")
--
-- WHY YOU'RE SEEING THE BUG: the fix lives in the migration file
-- 20260705010000_plan_sale_announcements.sql, but your database is still
-- running the first version of the trigger. SQL files in the repo do nothing
-- until they are executed against the project.
--
-- HOW TO APPLY (one time):
--   1. Open https://supabase.com/dashboard/project/kzhlhrhhfupgvpzjllce/sql
--   2. Paste this ENTIRE file and click Run.
--   3. The result grid at the bottom must show:  20 | 100 | 559.20 | 594.15
--   4. In the admin panel, re-save the promo — the new announcement will be
--      correct. Delete the old wrong post from Announcements → Deleted.
-- ═══════════════════════════════════════════════════════════════════════════

-- Correct number formatting: whole numbers keep all digits, fractional
-- amounts keep two decimals. (The old code did trim(trailing '0'), which ate
-- the zeros of 20 / 30 / 100.)
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

-- Replace the announcement composer with the version that uses fmt_amount.
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
  if coalesce(new.discount_percent, 0) <= 0 then
    return new;
  end if;
  if new.discount_percent is not distinct from old.discount_percent
     and new.promo_deadline is not distinct from old.promo_deadline
     and coalesce(new.promo_label, '') = coalesce(old.promo_label, '') then
    return new;
  end if;

  v_admin_id := coalesce(
    public.current_admin_id(),
    (select id from public.admins limit 1)
  );
  if v_admin_id is null then
    return new;
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

  insert into public.announcements (admin_id, title, body, status, audience)
  values (v_admin_id, v_title, v_body, 'Active', 'all')
  returning id into v_announcement;

  insert into public.announcement_tags (announcement_id, tag)
  values (v_announcement, 'promo');

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
  raise warning 'announce_plan_sale failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists trg_announce_plan_sale on public.prices;
create trigger trg_announce_plan_sale
  after update on public.prices
  for each row
  execute function public.announce_plan_sale();

-- ── Verification: must print  20 | 100 | 559.20 | 594.15 ────────────────────
select
  public.fmt_amount(20)      as twenty,
  public.fmt_amount(100)     as hundred,
  public.fmt_amount(559.20)  as sale_price,
  public.fmt_amount(594.15)  as sale_price_2;
