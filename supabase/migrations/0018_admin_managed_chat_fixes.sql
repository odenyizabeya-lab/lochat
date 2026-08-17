-- Fix the admin managed chat room:
--   * managed_account_messages.id must accept the app's mm_... text ids
--   * add columns the app sends but the table never had
--   * create the missing send_managed_message / set_managed_typing RPCs
--   * put the managed tables into the realtime publication so the app's
--     .stream() queries emit data (this is what made the chat list "load and
--     stop").
--   * create the storage buckets the repositories reference.

begin;

-- The app generates message ids like "mm_<microseconds>_<millis>" which are not
-- valid uuids. Change the column to text and keep a sane default.
alter table public.managed_account_messages
  alter column id drop default;

alter table public.managed_account_messages
  alter column id type text using id::text;

alter table public.managed_account_messages
  alter column id set default gen_random_uuid()::text;

-- Columns the app writes but the table never had.
alter table public.managed_account_messages
  add column if not exists thumbnail_url text,
  add column if not exists duration_ms int,
  add column if not exists width double precision,
  add column if not exists height double precision,
  add column if not exists file_name text,
  add column if not exists mime_type text,
  add column if not exists size_bytes bigint;

-- Reply references point at message ids (now text), not uuids.
alter table public.managed_account_messages
  alter column reply_to_id type text using reply_to_id::text;

-- ---------------------------------------------------------------------
-- set_managed_typing: only the admin who owns the managed account may set
-- typing state on one of that account's conversations.
-- ---------------------------------------------------------------------

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
  where c.id = p_conversation_id;

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
  where id = p_conversation_id;
end;
$$;

-- ---------------------------------------------------------------------
-- send_managed_message: insert a message as one of the caller's managed
-- accounts and update the conversation summary in one transaction.
-- ---------------------------------------------------------------------

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

  -- The caller must be the admin who owns this managed account.
  if not exists (
    select 1 from public.admin_managed_accounts a
    where a.id = managed_account_id_value and a.admin_uid = auth.uid()
  ) then
    raise exception 'FORBIDDEN';
  end if;

  -- The conversation must belong to the same managed account.
  if not exists (
    select 1 from public.managed_account_conversations c
    where c.id = p_conversation_id
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
  where id = p_conversation_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Realtime: without these the app's .stream() never emits.
-- ---------------------------------------------------------------------

alter publication supabase_realtime add table
  public.admin_managed_accounts,
  public.managed_account_contacts,
  public.managed_account_conversations,
  public.managed_account_messages;

-- ---------------------------------------------------------------------
-- Storage buckets used by the repositories.
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('managed_chat_media', 'managed_chat_media', true),
       ('managed_account_photos', 'managed_account_photos', true)
on conflict (id) do nothing;

create policy "managed_chat_media is readable by authenticated users"
  on storage.objects for select to authenticated
  using (bucket_id = 'managed_chat_media');

create policy "managed_chat_media is writable by owning admins"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'managed_chat_media'
    and exists (
      select 1 from public.managed_account_conversations c
      where c.id::text = (storage.foldername(name))[1]
        and exists (
          select 1 from public.admin_managed_accounts a
          where a.id = c.managed_account_id and a.admin_uid = auth.uid()
        )
    )
  );

create policy "managed_account_photos is readable by authenticated users"
  on storage.objects for select to authenticated
  using (bucket_id = 'managed_account_photos');

create policy "managed_account_photos is writable by owning admins"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'managed_account_photos'
    and exists (
      select 1 from public.admin_managed_accounts a
      where a.id = name::uuid and a.admin_uid = auth.uid()
    )
  );

commit;