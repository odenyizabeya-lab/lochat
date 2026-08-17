-- =====================================================================
-- Backfill the usernames registry
-- =====================================================================
-- The app looks up friends by username through public.usernames, which is
-- normally kept in sync by claim_username(). Accounts whose username was set
-- directly on public.profiles (seeded/admin-managed) were never registered,
-- so username search could not find them. Register every non-empty profile
-- username that is not already in the registry.

insert into public.usernames (username, uid)
select p.username, p.uid
from public.profiles p
where p.username <> ''
on conflict (username) do update set uid = excluded.uid;
