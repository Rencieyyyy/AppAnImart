-- Device push tokens for FCM notifications.
--
-- The app registers its Firebase Cloud Messaging token here after login
-- (lib/services/push_service.dart). The send-plan-sale-push edge function
-- reads every token with the service role and delivers plan-sale
-- notifications to users' phones — including when the app is closed.
--
-- One row per device token; a token moves to whichever account signed in
-- last on that device.
--
-- Idempotent: safe to re-run.

create table if not exists public.device_push_tokens (
  token      text primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  platform   text,                    -- 'android' | 'ios' | 'web'
  updated_at timestamptz not null default now()
);

create index if not exists device_push_tokens_user_idx
  on public.device_push_tokens (user_id);

alter table public.device_push_tokens enable row level security;

-- A user manages only their own device tokens. The edge function bypasses
-- RLS via the service role when broadcasting.
drop policy if exists "push_tokens_select_own" on public.device_push_tokens;
create policy "push_tokens_select_own"
  on public.device_push_tokens
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "push_tokens_insert_own" on public.device_push_tokens;
create policy "push_tokens_insert_own"
  on public.device_push_tokens
  for insert
  to authenticated
  with check (user_id = auth.uid());

-- Signing in on a device another account used must be able to take over the
-- token row, so updates only require the row to end up owned by the caller.
drop policy if exists "push_tokens_update_own" on public.device_push_tokens;
create policy "push_tokens_update_own"
  on public.device_push_tokens
  for update
  to authenticated
  using (true)
  with check (user_id = auth.uid());

drop policy if exists "push_tokens_delete_own" on public.device_push_tokens;
create policy "push_tokens_delete_own"
  on public.device_push_tokens
  for delete
  to authenticated
  using (user_id = auth.uid());
