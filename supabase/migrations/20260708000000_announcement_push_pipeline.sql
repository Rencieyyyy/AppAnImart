-- Phone push for every in-app announcement (Part 3.1 of
-- docs/app_assessment_and_notification_plan.md).
--
-- Until now only plan-sale promos reached phones: announce_plan_sale()
-- queued its own row in plan_sale_pushes. Every other notice (new offer,
-- offer accepted/declined, deal completed/cancelled, admin announcements)
-- was in-app only.
--
-- This migration generalises the queue:
--   1. plan_sale_pushes gains recipient_id — null means broadcast to every
--      device (admin announcements, plan sales); set means deliver only to
--      that user's devices (personal notices).
--   2. A trigger on public.announcements queues a push for every announcement
--      that goes live, targeted via announcements.recipient_id. All existing
--      and future notification triggers get phone push for free, because they
--      all insert announcements.
--   3. announce_plan_sale() loses its own queue insert (the announcements
--      trigger now covers it — without this it would push twice).
--
-- The send-plan-sale-push edge function is updated in the same commit to
-- honour recipient_id when fanning out to device_push_tokens.
--
-- Idempotent: safe to re-run.

-- ── 1. Targeted pushes ───────────────────────────────────────────────────────
alter table public.plan_sale_pushes
  add column if not exists recipient_id uuid references auth.users (id) on delete cascade;

create index if not exists plan_sale_pushes_unsent_idx
  on public.plan_sale_pushes (created_at)
  where not sent;

-- ── 2. Queue a push whenever an announcement goes live ──────────────────────
create or replace function public.queue_announcement_push()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_body text;
begin
  -- Only live posts push. Drafts that are later activated push at that
  -- moment (the UPDATE OF status trigger); already-active posts don't
  -- re-push on unrelated edits.
  if new.deleted_at is not null
     or lower(coalesce(new.status, '')) <> 'active' then
    return new;
  end if;
  if tg_op = 'UPDATE' and lower(coalesce(old.status, '')) = 'active' then
    return new;
  end if;

  -- Compact one-line preview for the phone notification: collapse
  -- whitespace, drop the formal salutation ("Dear Seller," ...), truncate.
  v_body := regexp_replace(coalesce(new.body, ''), '\s+', ' ', 'g');
  v_body := regexp_replace(v_body, '^(dear|hello|hi)\s[^,]{0,40},\s*', '', 'i');
  v_body := trim(v_body);
  if length(v_body) > 178 then
    v_body := left(v_body, 177) || '…';
  end if;

  insert into public.plan_sale_pushes (title, body, recipient_id)
  values (new.title, v_body, new.recipient_id);

  return new;
exception when others then
  -- Never block posting an announcement because queueing its push failed.
  raise warning 'queue_announcement_push failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists trg_queue_announcement_push on public.announcements;
create trigger trg_queue_announcement_push
  after insert or update of status on public.announcements
  for each row
  execute function public.queue_announcement_push();

-- ── 3. announce_plan_sale() no longer queues its own push ────────────────────
-- Identical to 20260705010000, minus the plan_sale_pushes insert at the end
-- (the announcements trigger above now queues it — keeping both would push
-- every plan sale twice).
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

  return new;
exception when others then
  -- Never block the admin's pricing save because announcing failed.
  raise warning 'announce_plan_sale failed: %', sqlerrm;
  return new;
end;
$$;
