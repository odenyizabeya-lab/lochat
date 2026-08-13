-- LoText typing indicator.
--
-- Conversations get a single "who is typing" slot (typing_uid + typing_until).
-- Only one participant can be shown typing at a time; in a 1-to-1 chat the
-- only other participant is the peer, so a single slot is enough. A
-- set_typing RPC stamps the caller's uid with a short TTL, and sending a
-- message clears the sender's own typing state (they're no longer typing).
-- The client hides the indicator once typing_until is in the past.

begin;

alter table public.conversations
  add column if not exists typing_uid uuid,
  add column if not exists typing_until timestamptz;

create index if not exists conversations_typing_until_idx
  on public.conversations (typing_until)
  where typing_until is not null;

-- ---------------------------------------------------------------------
-- set_typing: stamp the caller as typing in a conversation they belong to.
-- ---------------------------------------------------------------------

create or replace function public.set_typing(p_conversation_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  participants uuid[];
begin
  select c.participant_ids into participants
  from public.conversations c
  where c.id = p_conversation_id;

  if participants is null or not (auth.uid() = any (participants)) then
    return;
  end if;

  update public.conversations
  set typing_uid = auth.uid(),
      typing_until = now() + interval '8 seconds',
      updated_at = now()
  where id = p_conversation_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Clear typing when the sender actually sends a message.
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
  p_reply_to_sender text default null
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
    reply_to_id, reply_to_type, reply_to_text, reply_to_sender
  ) values (
    message_id, p_conversation_id, p_sender_uid, p_type,
    case when p_type = 'text' then btrim(p_text) else '' end,
    p_media_url, p_thumbnail_url, p_duration_ms, p_width, p_height,
    p_file_name, p_mime_type, p_size_bytes,
    (extract(epoch from now()) * 1000)::bigint,
    p_reply_to_id, p_reply_to_type, p_reply_to_text, p_reply_to_sender
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
