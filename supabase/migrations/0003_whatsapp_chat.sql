-- LoText WhatsApp-style chat support.
--
-- Adds the reply-quote columns to messages (so a reply renders a preview on
-- both sides without a second lookup) and a delete_message RPC so a sender can
-- remove one of their own messages for everyone.

begin;

-- ---------------------------------------------------------------------
-- Reply metadata on messages
-- ---------------------------------------------------------------------

alter table public.messages
  add column if not exists reply_to_id text,
  add column if not exists reply_to_type text,
  add column if not exists reply_to_text text,
  add column if not exists reply_to_sender text;

-- Recreate send_message to accept and store the reply context.
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
      updated_at = now()
  where id = p_conversation_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Delete a message for everyone
-- ---------------------------------------------------------------------

-- Deletes one of the caller's own messages. SECURITY DEFINER + the
-- sender_uid = auth.uid() check guarantees nobody can remove someone else's
-- messages. Realtime DELETE events remove it from every open chat.
create or replace function public.delete_message(
  p_conversation_id text,
  p_message_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.messages
  where conversation_id = p_conversation_id
    and id = p_message_id
    and sender_uid = auth.uid();
end;
$$;

commit;
