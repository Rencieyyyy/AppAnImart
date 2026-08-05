-- Auto-delete announcements after 90 days.
--
-- A daily pg_cron job (same mechanism as the admin repo's promo-reset job):
--   1. Announcements 90 days past their post date are soft-deleted
--      (deleted_at = now()). They vanish from the mobile Announcements page
--      (which filters deleted_at IS NULL) and move to the admin panel's
--      "Deleted" view, where an admin can still restore one if needed.
--   2. Announcements that have then sat in the trash for another 90 days are
--      permanently removed, along with their tags / views / likes / comments
--      (deleted explicitly so this works regardless of FK cascade settings).
--
-- Idempotent: safe to re-run.

create extension if not exists pg_cron;

create or replace function public.purge_old_announcements()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- 1) Soft-delete anything posted more than 90 days ago.
  update public.announcements
     set deleted_at = now()
   where deleted_at is null
     and created_at < now() - interval '90 days';

  -- 2) Permanently purge what has been in the trash for 90 more days.
  delete from public.announcement_comments c
   using public.announcements a
   where c.announcement_id = a.id
     and a.deleted_at is not null
     and a.deleted_at < now() - interval '90 days';

  delete from public.announcement_likes l
   using public.announcements a
   where l.announcement_id = a.id
     and a.deleted_at is not null
     and a.deleted_at < now() - interval '90 days';

  delete from public.announcement_views v
   using public.announcements a
   where v.announcement_id = a.id
     and a.deleted_at is not null
     and a.deleted_at < now() - interval '90 days';

  delete from public.announcement_tags t
   using public.announcements a
   where t.announcement_id = a.id
     and a.deleted_at is not null
     and a.deleted_at < now() - interval '90 days';

  delete from public.announcements
   where deleted_at is not null
     and deleted_at < now() - interval '90 days';
end;
$$;

-- (Re)create the daily job — 19:00 UTC = 3:00 AM Asia/Manila.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'purge-old-announcements') then
    perform cron.unschedule('purge-old-announcements');
  end if;
end $$;

select cron.schedule(
  'purge-old-announcements',
  '0 19 * * *',
  $$select public.purge_old_announcements()$$
);

-- One-time catch-up so already-overdue posts don't wait for tonight's run.
select public.purge_old_announcements();

-- To inspect / remove later:
--   select jobid, jobname, schedule, command from cron.job;
--   select cron.unschedule('purge-old-announcements');
