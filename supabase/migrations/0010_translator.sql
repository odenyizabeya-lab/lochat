-- LoText translator.
--
-- Messages are auto-translated on the receiver's device (never rewritten on
-- the server). This migration provides the metadata both sides need:
--
--   * profiles.preferred_lang    ISO 639-1-ish code of the user's preferred
--                                language (e.g. 'en', 'fr', 'zh-CN'). New
--                                accounts take the device locale the app
--                                passed at sign-up; existing accounts set it
--                                from Edit profile.
--   * profiles.auto_translate    master switch for auto-translating incoming
--                                messages into preferred_lang (default on).
--   * messages.p_lang            the sender's language code at send time, so
--                                the receiver can decide (client-side, zero
--                                AI cost) whether a message needs translating
--                                without language detection.
--   * messages.original_text     "translate before sending": the peer sees the
--                                translation as the message text plus a
--                                "See original" toggle backed by this column.
--   * messages.source_lang       language code of original_text.
--
-- Idempotent and transactional, like the other LoText migrations.

begin;

alter table public.profiles
  add column if not exists preferred_lang text,
  add column if not exists auto_translate boolean not null default true;

alter table public.messages
  add column if not exists p_lang text,
  add column if not exists original_text text,
  add column if not exists source_lang text;

-- New users: seed preferred_lang from the device locale the app passes at
-- sign-up (raw_user_meta_data.preferred_lang), when present.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id text;
begin
  insert into public.profiles (uid, display_name, preferred_lang)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'display_name', ''),
    nullif(btrim(coalesce(new.raw_user_meta_data ->> 'preferred_lang', '')), '')
  )
  on conflict (uid) do nothing;

  loop
    new_id := (floor(random() * 900000000) + 100000000)::bigint::text;
    begin
      insert into public.lotext_ids (id, uid) values (new_id, new.id);
      exit;
    exception when unique_violation then
      -- Extremely unlikely collision; try another random id.
    end;
  end loop;

  update public.profiles set lotext_id = new_id where uid = new.id;
  return new;
end;
$$;

-- Recreate send_message to accept and store the translation metadata.
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
  p_voice_effect text default null,
  p_lang text default null,
  p_original_text text default null,
  p_source_lang text default null
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
    reply_to_id, reply_to_type, reply_to_text, reply_to_sender, voice_effect,
    p_lang, original_text, source_lang
  ) values (
    message_id, p_conversation_id, p_sender_uid, p_type,
    case when p_type = 'text' then btrim(p_text) else '' end,
    p_media_url, p_thumbnail_url, p_duration_ms, p_width, p_height,
    p_file_name, p_mime_type, p_size_bytes,
    (extract(epoch from now()) * 1000)::bigint,
    p_reply_to_id, p_reply_to_type, p_reply_to_text, p_reply_to_sender,
    nullif(btrim(coalesce(p_voice_effect, '')), ''),
    nullif(btrim(coalesce(p_lang, '')), ''),
    case when p_type = 'text' then nullif(btrim(coalesce(p_original_text, '')), '') else null end,
    nullif(btrim(coalesce(p_source_lang, '')), '')
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

commit;
