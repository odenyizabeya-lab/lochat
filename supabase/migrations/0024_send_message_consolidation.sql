-- Consolidate send_message.
--
-- Earlier migrations recreated send_message with CREATE OR REPLACE while the
-- parameter list grew (reply metadata, voice effects, translation metadata).
-- Because the argument list changed each time, every revision created a NEW
-- overloaded function instead of replacing the old one, leaving up to four
-- live copies of send_message. PostgREST then picked whichever overload matched
-- the parameters the caller happened to send, so some callers hit old bodies
-- (and the auth.uid() check introduced in 0007 was dropped by 0011's
-- recreation of a differently-shaped signature).
--
-- This migration drops every overload and recreates the single canonical
-- send_message: the full latest signature (reply + voice + translation
-- metadata, last_message_type/duration sync) with the caller-is-sender guard
-- restored so a user can never send as someone else.
--
-- Idempotent and transactional, like the other LoText migrations.

begin;

-- DROP FUNCTION without an argument list fails (SQLSTATE 42725) when several
-- overloads exist, so drop each one individually by signature.
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'send_message'
  loop
    execute 'drop function ' || r.sig;
  end loop;
end $$;

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
  -- The caller can only ever send as themselves. (Service-role callers have no
  -- auth.uid() and therefore pass, which is intentional for server tooling.)
  if auth.uid() is not null and p_sender_uid <> auth.uid() then
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
      last_message_type = p_type,
      last_message_duration_ms = p_duration_ms,
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