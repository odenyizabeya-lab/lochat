-- LoText security hardening.
--
-- Fixes the issues found in the production-readiness audit:
--   * send_message       - trusted the client-supplied p_sender_uid with no
--                          auth.uid() check, so any signed-in user could
--                          inject/impersonate messages into any conversation.
--   * claim_username /   - SECURITY DEFINER RPCs that trusted the client uid,
--     ensure_lotext_id     letting anyone claim a username/LoText ID for
--                          another account.
--   * mark_message_status- no participant check.
--   * chat_media         - public bucket + "readable by all authenticated
--                          users" policy made private chat media readable by
--                          any signed-in user (and the anonymous public).
--   * profile_photos     - public bucket: avatars were readable by the whole
--                          internet instead of just signed-in users.
--
-- The client already passes the caller's own uid everywhere, so the extra
-- auth.uid() guards change the server contract without breaking the app. The
-- storage buckets become private; the app now stores object paths in the DB
-- and resolves signed URLs at render time.

begin;

-- ---------------------------------------------------------------------
-- send_message: the sender must be the authenticated user, not whoever the
-- client claims to be.
-- ---------------------------------------------------------------------

create or replace function public.send_message(
  p_conversation_id text,
  p_sender_uid uuid,
  p_text text default '',
  p_message_id text default null,
  p_type text default 'text',
  p_media_url text default null,
  p_thumbnail_url text default null,
  p_duration_ms int default null,
  p_width double precision default null,
  p_height double precision default null,
  p_file_name text default null,
  p_mime_type text default null,
  p_size_bytes bigint default null,
  p_reply_to_id text default null,
  p_reply_to_type text default null,
  p_reply_to_text text default null,
  p_reply_to_sender text default null,
  p_voice_effect text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  participants uuid[];
  receiver_uid uuid;
  sender_name text;
  summary text;
  message_id text;
begin
  -- The caller can only ever send as themselves.
  if p_sender_uid <> auth.uid() then
    raise exception 'FORBIDDEN';
  end if;

  if p_type = 'text' and btrim(coalesce(p_text, '')) = '' then
    return;
  end if;
  if p_type <> 'text' and (p_media_url is null or p_media_url = '') then
    return;
  end if;

  select c.participant_ids into participants
  from public.conversations c
  where c.id = p_conversation_id;

  if participants is null or array_length(participants, 1) <> 2 then
    raise exception 'INVALID_CONVERSATION';
  end if;
  if not (p_sender_uid = any (participants)) then
    raise exception 'NOT_PARTICIPANT';
  end if;

  receiver_uid := case
    when participants[1] = p_sender_uid then participants[2]
    else participants[1]
  end;

  select coalesce(display_name, '') into sender_name
  from public.profiles where uid = p_sender_uid;

  message_id := coalesce(p_message_id, gen_random_uuid()::text);

  insert into public.messages (
    id, conversation_id, sender_uid, type, text, media_url, thumbnail_url,
    duration_ms, width, height, file_name, mime_type, size_bytes, created_at_ms,
    reply_to_id, reply_to_type, reply_to_text, reply_to_sender, voice_effect
  ) values (
    message_id, p_conversation_id, p_sender_uid, p_type,
    case when p_type = 'text' then btrim(p_text) else '' end,
    p_media_url, p_thumbnail_url, p_duration_ms, p_width, p_height,
    p_file_name, p_mime_type, p_size_bytes,
    (extract(epoch from now()) * 1000)::bigint,
    p_reply_to_id, p_reply_to_type, p_reply_to_text, p_reply_to_sender,
    nullif(btrim(coalesce(p_voice_effect, '')), '')
  )
  on conflict (id, conversation_id) do nothing;

  summary := case p_type
    when 'text' then btrim(p_text)
    when 'image' then 'Photo'
    when 'video' then 'Video'
    when 'voice' then 'Voice message'
    else 'Message'
  end;

  update public.conversations
  set last_message_text = summary,
      last_sender_uid = p_sender_uid,
      last_sender_name = sender_name,
      last_message_at = now(),
      unread_counts = jsonb_set(
        unread_counts,
        array[receiver_uid::text],
        to_jsonb(
          coalesce((unread_counts ->> receiver_uid::text)::int, 0) + 1
        )
      ),
      typing_uid = case when typing_uid = p_sender_uid then null else typing_uid end,
      typing_until = case when typing_uid = p_sender_uid then null else typing_until end,
      updated_at = now()
  where id = p_conversation_id;
end;
$$;

-- ---------------------------------------------------------------------
-- mark_message_status: only participants may update statuses in a
-- conversation (and never their own messages, as before).
-- ---------------------------------------------------------------------

create or replace function public.mark_message_status(
  p_conversation_id text,
  p_message_ids text[],
  p_status text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_status not in ('delivered', 'read') then
    raise exception 'INVALID_STATUS';
  end if;
  if not exists (
    select 1 from public.conversations c
    where c.id = p_conversation_id
      and auth.uid() = any (c.participant_ids)
  ) then
    raise exception 'FORBIDDEN';
  end if;
  update public.messages
  set status = p_status
  where conversation_id = p_conversation_id
    and id = any (p_message_ids)
    and sender_uid <> auth.uid();
end;
$$;

-- ---------------------------------------------------------------------
-- claim_username: only the account itself may claim its username.
-- ---------------------------------------------------------------------

create or replace function public.claim_username(
  p_uid uuid,
  p_new_username text,
  p_old_username text default ''
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  name text;
  old text;
begin
  if p_uid <> auth.uid() then
    raise exception 'FORBIDDEN';
  end if;

  name := regexp_replace(lower(btrim(p_new_username)), '^@', '');
  if name = '' then
    raise exception 'USERNAME_UNAVAILABLE';
  end if;

  if exists (select 1 from public.usernames where username = name and uid <> p_uid) then
    raise exception 'USERNAME_UNAVAILABLE';
  end if;

  insert into public.usernames (username, uid)
  values (name, p_uid)
  on conflict (username) do update set uid = excluded.uid;

  old := regexp_replace(lower(btrim(coalesce(p_old_username, ''))), '^@', '');
  if old <> '' and old <> name then
    delete from public.usernames where username = old and uid = p_uid;
  end if;

  update public.profiles
  set username = name, updated_at = now()
  where uid = p_uid;
end;
$$;

-- ---------------------------------------------------------------------
-- ensure_lotext_id: only the account itself may obtain its LoText ID.
-- ---------------------------------------------------------------------

create or replace function public.ensure_lotext_id(p_uid uuid)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id text;
  existing text;
begin
  if p_uid <> auth.uid() then
    raise exception 'FORBIDDEN';
  end if;

  select lotext_id into existing from public.profiles where uid = p_uid;
  if existing is not null and existing <> '' then
    return existing;
  end if;

  loop
    new_id := (floor(random() * 900000000) + 100000000)::bigint::text;
    begin
      insert into public.lotext_ids (id, uid) values (new_id, p_uid);
      exit;
    exception when unique_violation then
    end;
  end loop;

  update public.profiles
  set lotext_id = new_id, updated_at = now()
  where uid = p_uid;
  return new_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Storage: chat_media and profile_photos become private. Chat media is only
-- readable by the conversation's participants; profile photos are readable by
-- any signed-in user (avatars are semi-public, but no longer anonymous).
-- ---------------------------------------------------------------------

update storage.buckets
set public = false
where id in ('chat_media', 'profile_photos');

drop policy if exists "chat_media is readable by authenticated users"
  on storage.objects;
drop policy if exists "profile_photos are readable by authenticated users"
  on storage.objects;

create policy "chat_media is readable by conversation participants"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'chat_media'
    and exists (
      select 1 from public.conversations c
      where c.id = (storage.foldername(name))[1]
        and auth.uid() = any (c.participant_ids)
    )
  );

create policy "profile_photos are readable by authenticated users"
  on storage.objects for select to authenticated
  using (bucket_id = 'profile_photos');

commit;
