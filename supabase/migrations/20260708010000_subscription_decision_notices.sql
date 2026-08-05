-- Subscription approved/rejected → notify the requesting user (Part 3.2 of
-- docs/app_assessment_and_notification_plan.md — the biggest silent gap:
-- a user requests Premium, pays outside the app, then hears nothing).
--
-- A trigger on public.subscriptions posts a personal announcement to the
-- requesting user the moment an admin approves or rejects their request.
-- The announcement automatically reaches their phone too, via the
-- queue_announcement_push() trigger (20260708000000).
--
-- Idempotent: safe to re-run.

create or replace function public.notify_subscription_decision()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id     uuid;
  v_status       text;
  v_approved     boolean;
  v_plan         text;
  v_cycle        text;
  v_expires_text text;
  v_title        text;
  v_body         text;
  v_announcement uuid;
begin
  v_status := lower(coalesce(new.status, ''));

  -- Only when the request is newly decided. 'active' covers legacy admin
  -- builds that mark approvals that way.
  if v_status not in ('approved', 'active', 'rejected', 'declined')
     or lower(coalesce(new.status, '')) is not distinct from lower(coalesce(old.status, '')) then
    return new;
  end if;
  v_approved := v_status in ('approved', 'active');

  -- The announcements table needs an admin author for the app's author card;
  -- attribute the notice to the deciding admin (same convention as
  -- notify_new_offer).
  v_admin_id := coalesce(
    public.current_admin_id(),
    (select id from public.admins limit 1)
  );
  if v_admin_id is null then
    return new;
  end if;

  v_plan := coalesce(nullif(trim(new.plan), ''), 'Premium');
  v_cycle := case when lower(coalesce(new.billing_cycle, '')) = 'yearly'
                  then 'yearly' else 'monthly' end;
  if new.expires_at is not null then
    v_expires_text := to_char(
      new.expires_at at time zone 'Asia/Manila',
      'FMMonth FMDD, YYYY');
  end if;

  if v_approved then
    v_title := format('Subscription Approved — %s Plan', v_plan);
    v_body :=
      'Dear Subscriber,' || E'\n\n' ||
      format(
        'Great news! Your %s subscription request (%s billing, ₱%s) has been '
        || 'approved and is now active on your account.%s',
        v_plan, v_cycle, public.fmt_amount(coalesce(new.price, 0)),
        case when v_expires_text is not null
             then format(' Your subscription is valid until %s (Philippine Time).',
                         v_expires_text)
             else '' end
      ) || E'\n\n' ||
      'Open the app to enjoy your new plan benefits. Only you can see this '
      || 'notification.' || E'\n\n' ||
      'Thank you for subscribing to AniMart.' || E'\n' ||
      '— The AniMart Team';
  else
    v_title := format('Subscription Request Update — %s Plan', v_plan);
    v_body :=
      'Dear User,' || E'\n\n' ||
      format(
        'We regret to inform you that your %s subscription request '
        || '(%s billing, ₱%s) was not approved at this time. If you have '
        || 'already sent a payment, or believe this is a mistake, please '
        || 'contact us through the app''s Support Chat.',
        v_plan, v_cycle, public.fmt_amount(coalesce(new.price, 0))
      ) || E'\n\n' ||
      'You are welcome to submit a new request anytime from Profile → '
      || 'Premium Subscription. Only you can see this notification.' || E'\n\n' ||
      'Thank you for using AniMart.' || E'\n' ||
      '— The AniMart Team';
  end if;

  insert into public.announcements (admin_id, title, body, status, audience, recipient_id)
  values (v_admin_id, v_title, v_body, 'Active', 'all', new.user_id)
  returning id into v_announcement;

  insert into public.announcement_tags (announcement_id, tag)
  values (v_announcement, 'general');

  return new;
exception when others then
  -- Never block the admin's decision because notifying failed.
  raise warning 'notify_subscription_decision failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists trg_notify_subscription_decision on public.subscriptions;
create trigger trg_notify_subscription_decision
  after update on public.subscriptions
  for each row
  execute function public.notify_subscription_decision();
