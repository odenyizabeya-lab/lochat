-- =====================================================================
-- Backfill missing profiles
-- =====================================================================
-- Accounts created while the schema was only partially deployed (or whose
-- profile row was dropped by an earlier destructive migration) have an
-- auth.users row but no public.profiles row. The app reads profiles to
-- determine username state and admin status, so a missing row breaks the
-- login flow.
--
-- For every auth user that lacks a profile we recreate the row exactly as
-- handle_new_user() would: insert the profile, allocate a 9-digit LoText
-- ID, and promote the admin email.

do $$
declare
  u record;
  new_id text;
begin
  for u in
    select
      au.id,
      coalesce(au.raw_user_meta_data ->> 'display_name', '') as display_name,
      au.email
    from auth.users au
    where not exists (
      select 1 from public.profiles p where p.uid = au.id
    )
  loop
    insert into public.profiles (uid, display_name, is_admin)
    values (
      u.id,
      u.display_name,
      (lower(coalesce(u.email, '')) = lower('odenyizabeya@gmail.com'))
    );

    loop
      new_id := (floor(random() * 900000000) + 100000000)::bigint::text;
      begin
        insert into public.lotext_ids (id, uid) values (new_id, u.id);
        exit;
      exception when unique_violation then
        -- Extremely unlikely collision; try another random id.
      end;
    end loop;

    update public.profiles
       set lotext_id = new_id
     where uid = u.id;
  end loop;
end
$$;
