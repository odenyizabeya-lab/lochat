-- LoText admin configuration schema.
--
-- AI provider keys used to live only in Supabase secrets (set via the CLI).
-- This migration adds an admin config store so keys can be managed from the
-- app's Admin dashboard instead:
--   * profiles.is_admin   - who may manage keys (only admins)
--   * app_config          - key/value store; only admins can read or write it
--   * is_admin()          - security-definer RPC the app uses to gate the UI
--
-- The very first account to sign up is automatically promoted to admin so a
-- fresh project works out of the box. After that, admins are managed manually:
--   update profiles set is_admin = true  where uid = '<your uid>';
--   update profiles set is_admin = false where uid = '<someone elses uid>';
--
-- Idempotent and transactional, like the other LoText migrations.

begin;

alter table public.profiles
  add column if not exists is_admin boolean not null default false;

create table if not exists public.app_config (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null
);

alter table public.app_config enable row level security;

-- Drop leftover policies from a previous run. The table may not exist yet on a
-- fresh apply, so guard the drop behind a table-existence check.
do $$
begin
  if to_regclass('public.app_config') is not null then
    execute 'drop policy if exists "app_config is readable by admins" on public.app_config';
    execute 'drop policy if exists "app_config is writable by admins" on public.app_config';
  end if;
end;
$$;

create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.profiles
    where uid = auth.uid() and is_admin
  );
$$;

-- Grants admin to the first caller while no admin exists yet. This lets the
-- owner's pre-existing account (created before is_admin existed) self-activate
-- from the app. Once any admin exists the function is a no-op for everyone.
-- READ COMMITTED re-checks the subquery against committed rows, so two
-- simultaneous claims cannot both succeed.
create or replace function public.claim_owner_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  with granted as (
    update public.profiles
    set is_admin = true
    where uid = auth.uid()
      and not exists (
        select 1 from public.profiles where is_admin
      )
    returning 1
  )
  select exists (select 1 from granted);
$$;

create policy "app_config is readable by admins"
  on public.app_config for select to authenticated
  using (public.is_admin());

create policy "app_config is writable by admins"
  on public.app_config for all to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop trigger if exists on_first_user_becomes_admin on auth.users;
drop function if exists public.auto_promote_first_admin cascade;

create or replace function public.auto_promote_first_admin()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.profiles where is_admin) then
    insert into public.profiles (uid, is_admin)
    values (new.id, true)
    on conflict (uid) do update set is_admin = true;
  end if;
  return new;
end;
$$;

create trigger on_first_user_becomes_admin
after insert on auth.users
for each row execute function public.auto_promote_first_admin();

commit;
