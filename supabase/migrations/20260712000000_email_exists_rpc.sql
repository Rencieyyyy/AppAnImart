-- Forgot-password email check.
--
-- resetPasswordForEmail() succeeds silently for unknown emails (Supabase
-- anti-enumeration default), so the app happily moved a user with a typo'd
-- email to the "enter the code" screen where no code would ever arrive.
-- The product decision here is to tell the user up front: the app calls this
-- RPC before requesting the reset code and refuses to proceed when no
-- account matches.
--
-- SECURITY DEFINER because the caller is anonymous (no session yet) and
-- auth.users is not otherwise readable. Returns only a boolean.

create or replace function public.email_exists(p_email text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from auth.users
    where lower(email) = lower(trim(p_email))
      and deleted_at is null
  );
$$;

revoke all on function public.email_exists(text) from public;
grant execute on function public.email_exists(text) to anon, authenticated;
