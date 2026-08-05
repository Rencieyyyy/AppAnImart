-- New review received → notify the seller (Part 3.3 of
-- docs/app_assessment_and_notification_plan.md — pairs with the
-- verified-purchase "Rate seller" flow).
--
-- A trigger on public.reviews posts a personal announcement to the reviewed
-- seller when a buyer leaves a review, or meaningfully edits one (rating or
-- comment changed — the app upserts on re-review). Phone push rides the
-- queue_announcement_push() trigger (20260708000000).
--
-- Idempotent: safe to re-run.

create or replace function public.notify_new_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id      uuid;
  v_reviewer_name text;
  v_comment       text;
  v_title         text;
  v_body          text;
  v_announcement  uuid;
begin
  -- Skip no-op upserts (the app re-submits the row on "Update Review").
  if tg_op = 'UPDATE'
     and new.rating is not distinct from old.rating
     and coalesce(new.comment, '') = coalesce(old.comment, '') then
    return new;
  end if;

  -- The announcements table needs an admin author for the app's author card;
  -- attribute the notice to any admin (same convention as notify_new_offer).
  v_admin_id := coalesce(
    public.current_admin_id(),
    (select id from public.admins limit 1)
  );
  if v_admin_id is null then
    return new;
  end if;

  select coalesce(nullif(trim(u.name), ''), 'A buyer')
    into v_reviewer_name
    from public.users u
   where u.id = new.reviewer_id;
  v_reviewer_name := coalesce(v_reviewer_name, 'A buyer');

  v_comment := trim(coalesce(new.comment, ''));
  if length(v_comment) > 200 then
    v_comment := left(v_comment, 199) || '…';
  end if;

  v_title := format(
    case when tg_op = 'UPDATE'
         then 'Review Updated — %s/5 Stars from %s'
         else 'New Review Received — %s/5 Stars from %s' end,
    new.rating, v_reviewer_name);

  v_body :=
    'Dear Seller,' || E'\n\n' ||
    format(
      '%s has %s you a %s-star review after a completed purchase.%s',
      v_reviewer_name,
      case when tg_op = 'UPDATE' then 'updated their review of' else 'left' end,
      new.rating,
      case when v_comment <> ''
           then E'\n\nTheir comment: “' || v_comment || '”' else '' end
    ) || E'\n\n' ||
    'Reviews from verified buyers build your Trust Score and help future '
    || 'buyers choose you. You can see all your reviews on your seller '
    || 'profile. Only you can see this notification.' || E'\n\n' ||
    'Thank you for selling on AniMart.' || E'\n' ||
    '— The AniMart Team';

  insert into public.announcements (admin_id, title, body, status, audience, recipient_id)
  values (v_admin_id, v_title, v_body, 'Active', 'sellers', new.seller_id)
  returning id into v_announcement;

  insert into public.announcement_tags (announcement_id, tag)
  values (v_announcement, 'general');

  return new;
exception when others then
  -- Never block the buyer's review because notifying failed.
  raise warning 'notify_new_review failed: %', sqlerrm;
  return new;
end;
$$;

drop trigger if exists trg_notify_new_review on public.reviews;
create trigger trg_notify_new_review
  after insert or update on public.reviews
  for each row
  execute function public.notify_new_review();
