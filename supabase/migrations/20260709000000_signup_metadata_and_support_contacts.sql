-- 1) Copy sign-up metadata onto the users row at INSERT time.
--
-- The sign-up flow stashes the valid-ID photo URL, ID type, and the picked
-- city's coordinates in the Auth user's metadata (no session exists yet when
-- email confirmation is on). Until now the app only backfilled them into
-- public.users on the user's FIRST LOGIN — which meant an admin reviewing a
-- brand-new account (login is gated on is_verified!) had no valid ID to look
-- at unless the applicant had already attempted a login. Chicken-and-egg.
--
-- Fix: a BEFORE INSERT trigger on public.users that reads auth.users'
-- raw_user_meta_data and fills the columns the moment the dashboard's
-- handle-new-user trigger creates the row. Deliberately composed as a
-- separate trigger (not a replacement of the dashboard-managed function) so
-- it works no matter what that function looks like. The app's login-time
-- backfill stays as a safety net for pre-existing accounts.

alter table public.users add column if not exists valid_id_url text;
alter table public.users add column if not exists id_type text;

create or replace function public.enrich_new_user_from_metadata()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  meta jsonb;
begin
  select raw_user_meta_data into meta from auth.users where id = new.id;
  if meta is null then
    return new;
  end if;

  new.valid_id_url  := coalesce(new.valid_id_url,  nullif(meta->>'valid_id_url', ''));
  new.id_type       := coalesce(new.id_type,       nullif(meta->>'id_type', ''));
  new.location_name := coalesce(new.location_name, nullif(meta->>'location_name', ''));

  -- Coordinates only in a pair, and only when the row has none yet.
  if new.latitude is null and new.longitude is null
     and (meta->>'latitude')  ~ '^-?[0-9.]+$'
     and (meta->>'longitude') ~ '^-?[0-9.]+$' then
    new.latitude  := (meta->>'latitude')::double precision;
    new.longitude := (meta->>'longitude')::double precision;
  end if;

  return new;
end;
$$;

drop trigger if exists enrich_new_user_from_metadata on public.users;
create trigger enrich_new_user_from_metadata
  before insert on public.users
  for each row
  execute function public.enrich_new_user_from_metadata();

-- 2) Support contact details for the app's Customer Service sheet.
--
-- The app previously hardcoded a placeholder phone number and email. It now
-- reads these app_settings keys and HIDES each row until a real value is
-- set. Managed from the admin website by the super admin (same pattern as
-- the gcash_* keys). Seeded empty; idempotent.

insert into public.app_settings (key, value) values
  ('support_phone', ''),
  ('support_email', '')
on conflict (key) do nothing;
