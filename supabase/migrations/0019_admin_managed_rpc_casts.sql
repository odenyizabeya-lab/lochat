-- Fix uuid = text comparisons in the managed chat RPCs. The app passes
-- conversation ids as text but managed_account_conversations.id is uuid.

create or replace function public.set_managed_typing(p_conversation_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  managed_account_id_value uuid;
begin
  select c.managed_account_id into managed_account_id_value
  from public.managed_account_conversations c
  where c.id::text = p_conversation_id;

  if managed_account_id_value is null then
    return;
  end if;

  if not exists (
    select 1 from public.admin_managed_accounts a
    where a.id = managed_account_id_value and a.admin_uid = auth.uid()
  ) then
    return;
  end if;

  update public.managed_account_conversations
  set typing_uid = auth.uid(),
      typing_until = now() + interval '8 seconds'
  where id::text = p_conversation_id;
end;
$$;

create or replace function public.send_managed_message(
  p_message jsonb,
  p_conversation_id text,
  p_summary jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  managed_account_id_value uuid;
  sender_uid_value uuid;
begin
  managed_account_id_value := (p_message ->> 'managed_account_id')::uuid;
  sender_uid_value := (p_message ->> 'sender_uid')::uuid;

  if managed_account_id_value is null then
    raise exception 'INVALID_ACCOUNT';
  end if;

  if not exists (
    select 1 from public.admin_managed_accounts a
    where a.id = managed_account_id_value and a.admin_uid = auth.uid()
  ) then
    raise exception 'FORBIDDEN';
  end if;

  if not exists (
    select 1 from public.managed_account_conversations c
    where c.id::text = p_conversation_id
      and c.managed_account_id = managed_account_id_value
  ) then
    raise exception 'INVALID_CONVERSATION';
  end if;

  insert into public.managed_account_messages (
    id, conversation_id, managed_account_id, sender_uid, type, text, media_url,
    thumbnail_url, duration_ms, width, height, file_name, mime_type, size_bytes,
    voice_effect, reply_to_id, reply_to_type, reply_to_text, reply_to_sender,
    sender_lang, original_text, source_lang, status
  ) values (
    coalesce(p_message ->> 'id', gen_random_uuid()::text),
    p_conversation_id,
    managed_account_id_value,
    sender_uid_value,
    coalesce(p_message ->> 'type', 'text'),
    coalesce(p_message ->> 'text', ''),
    nullif(p_message ->> 'media_url', ''),
    nullif(p_message ->> 'thumbnail_url', ''),
    nullif((p_message ->> 'duration_ms')::int, null)::int,
    nullif((p_message ->> 'width')::double precision, null)::double precision,
    nullif((p_message ->> 'height')::double precision, null)::double precision,
    nullif(p_message ->> 'file_name', ''),
    nullif(p_message ->> 'mime_type', ''),
    nullif((p_message ->> 'size_bytes')::bigint, null)::bigint,
    nullif(p_message ->> 'voice_effect', ''),
    nullif(p_message ->> 'reply_to_id', ''),
    nullif(p_message ->> 'reply_to_type', ''),
    nullif(p_message ->> 'reply_to_text', ''),
    nullif(p_message ->> 'reply_to_sender', ''),
    nullif(p_message ->> 'sender_lang', ''),
    nullif(p_message ->> 'original_text', ''),
    nullif(p_message ->> 'source_lang', ''),
    coalesce(p_message ->> 'status', 'sent')
  )
  on conflict (id) do nothing;

  update public.managed_account_conversations
  set last_message_text = coalesce(
        p_summary ->> 'last_message_text',
        coalesce(p_message ->> 'text', '')
      ),
      last_message_at = now(),
      last_sender_uid = sender_uid_value,
      last_message_type = coalesce(p_message ->> 'type', 'text'),
      last_message_duration_ms = nullif(
        (p_summary ->> 'last_message_duration_ms')::int, null
      )::int,
      typing_uid = null,
      typing_until = null
  where id::text = p_conversation_id;
end;
$$;