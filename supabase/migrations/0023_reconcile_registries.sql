-- =====================================================================
-- Reconcile the username / LoText ID registries with profiles
-- =====================================================================
-- Symptom fixed: "Add contact" search resolves a friend's username (or LoText
-- ID) to the signed-in user's own profile, so the app shows "That's you" and
-- the friend can never be added or messaged.
--
-- Root cause: public.profiles.username is not unique and usernames can end up
-- set directly on profiles without going through claim_username() (which is
-- the only writer that keeps public.usernames in sync). The 0022 backfill then
-- ran `on conflict (username) do update set uid = excluded.uid` with an
-- undefined row order, so when two profiles shared a username the last row
-- processed silently stole the registration. A stale usernames row can point a
-- friend's username at your own uid, and the app (which looked up the registry
-- first) showed your own profile -> "That's you".
--
-- This migration makes public.profiles the single source of truth and rebuilds
-- the registries from it. The app now also prefers the profile's own username /
-- lotext_id over the registry (see SupabaseProfileRepository), so lookups are
-- correct even before this migration is applied.

-- ---------------------------------------------------------------------------
-- 1. Deduplicate profiles.username: keep the earliest claim, clear the rest.
-- ---------------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select p.uid, p.username,
           row_number() over (
             partition by p.username
             order by p.created_at, p.uid
           ) as rn
    from public.profiles p
    where p.username <> ''
  loop
    if r.rn > 1 then
      update public.profiles
         set username = '', updated_at = now()
       where uid = r.uid;
    end if;
  end loop;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. Rebuild public.usernames from the (deduplicated) profiles.
-- ---------------------------------------------------------------------------
delete from public.usernames;

insert into public.usernames (username, uid)
select p.username, p.uid
from public.profiles p
where p.username <> '';

-- ---------------------------------------------------------------------------
-- 3. Reconcile public.lotext_ids with profiles.lotext_id (authoritative).
-- ---------------------------------------------------------------------------
-- Fix rows whose uid drifted away from the profile that actually owns the ID.
update public.lotext_ids li
   set uid = p.uid
  from public.profiles p
 where p.lotext_id = li.id
   and p.uid <> li.uid;

-- Register profile IDs that are missing from the registry.
insert into public.lotext_ids (id, uid)
select p.lotext_id, p.uid
from public.profiles p
where p.lotext_id is not null
  and p.lotext_id <> ''
  and not exists (
    select 1 from public.lotext_ids li where li.id = p.lotext_id
  );

-- ---------------------------------------------------------------------------
-- 4. Support the app's profile-first lookups.
-- ---------------------------------------------------------------------------
create index if not exists idx_profiles_username
  on public.profiles (username);
