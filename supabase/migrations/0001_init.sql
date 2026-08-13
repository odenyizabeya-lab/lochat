-- LoText initial schema for Supabase (Postgres).
--
-- Layout mirrors the previous Firestore structure:
--   * profiles            - one public row per auth user (public by design)
--   * usernames           - lowercase username -> uid registry (uniqueness)
--   * lotext_ids          - 9-digit LoText ID -> uid registry (uniqueness)
--   * contacts            - private, one-way contact lists
--   * conversations       - one row per 1-to-1 pair, deterministic id
--   * messages            - PK (id, conversation_id); writes go through the
--                           send_message RPC so summary/unread stay atomic
--   * calls               - call lifecycle + SDP offer/answer columns
--   * call_candidates     - ICE candidates, one row per candidate
--   * device_tokens       - FCM token registrations per user
--
-- All writes that span multiple tables go through SECURITY DEFINER RPCs so a
-- single call is atomic and clients never touch the registry tables directly.
--
-- This migration is idempotent and transactional: it first drops any LoText
-- objects left behind by an earlier (partial) run, then recreates everything.
-- If any statement fails, the whole transaction rolls back and the database is
-- left untouched, so it is safe to run again after fixing the error.

begin;

-- Remove any leftovers from a previous run. Only LoText-owned objects are
-- touched; nothing under auth.* or the storage.* plumbing is dropped except
-- the storage policies/buckets that LoText itself creates.
drop table if exists public.device_tokens cascade;
drop table if exists public.call_candidates cascade;
drop table if exists public.calls cascade;
drop table if exists public.messages cascade;
drop table if exists public.conversations cascade;
drop table if exists public.contacts cascade;
drop table if exists public.lotext_ids cascade;
drop table if exists public.usernames cascade;
drop table if exists public.profiles cascade;

drop policy if exists "chat_media is readable by authenticated users" on storage.objects;
drop policy if exists "chat_media is writable by conversation participants" on storage.objects;
drop policy if exists "profile_photos are readable by authenticated users" on storage.objects;
drop policy if exists "users can upload their own profile photo" on storage.objects;
drop policy if exists "users can replace their own profile photo" on storage.objects;
drop policy if exists "users can delete their own profile photo" on storage.objects;

drop trigger if exists on_auth_user_created on auth.users;

drop function if exists public.handle_new_user cascade;
drop function if exists public.claim_username cascade;
drop function if exists public.ensure_lotext_id cascade;
drop function if exists public.send_message cascade;
drop function if exists public.mark_conversation_read cascade;
drop function if exists public.mark_message_status cascade;

-- =====================================================================
-- Tables
-- =====================================================================

create table public.profiles (
  uid uuid primary key references auth.users (id) on delete cascade,
  username text not null default '',
  display_name text not null default '',
  lotext_id text unique,
  photo_url text,
  is_online boolean not null default false,
  last_seen timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.usernames (
  username text primary key,
  uid uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.lotext_ids (
  id text primary key,
  uid uuid not null unique references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.contacts (
  owner_uid uuid not null references auth.users (id) on delete cascade,
  contact_uid uuid not null references auth.users (id) on delete cascade,
  added_at timestamptz not null default now(),
  primary key (owner_uid, contact_uid)
);

create table public.conversations (
  id text primary key,
  participant_ids uuid[] not null,
  last_message_text text not null default '',
  last_sender_uid uuid,
  last_sender_name text not null default '',
  unread_counts jsonb not null default '{}'::jsonb,
  last_message_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (cardinality(participant_ids) = 2)
);

create table public.messages (
  id text not null default gen_random_uuid()::text,
  conversation_id text not null references public.conversations (id) on delete cascade,
  sender_uid uuid not null references auth.users (id) on delete cascade,
  type text not null default 'text',
  text text not null default '',
  media_url text,
  thumbnail_url text,
  duration_ms int,
  width double precision,
  height double precision,
  file_name text,
  mime_type text,
  size_bytes bigint,
  status text not null default 'sent',
  created_at timestamptz not null default now(),
  created_at_ms bigint not null,
  primary key (id, conversation_id)
);

create table public.calls (
  id uuid primary key default gen_random_uuid(),
  conversation_id text not null references public.conversations (id) on delete cascade,
  type text not null check (type in ('audio', 'video')),
  caller_uid uuid not null references auth.users (id) on delete cascade,
  callee_uid uuid not null references auth.users (id) on delete cascade,
  status text not null default 'ringing'
    check (status in ('ringing', 'active', 'ended', 'missed', 'declined')),
  offer_sdp text,
  answer_sdp text,
  created_at timestamptz not null default now(),
  answered_at timestamptz,
  ended_at timestamptz,
  ended_by uuid
);

create table public.call_candidates (
  id bigint generated always as identity primary key,
  call_id uuid not null references public.calls (id) on delete cascade,
  sender_uid uuid not null references auth.users (id) on delete cascade,
  candidate text not null,
  sdp_mid text not null default '',
  sdp_ml_index int not null,
  created_at timestamptz not null default now()
);

create table public.device_tokens (
  uid uuid not null references auth.users (id) on delete cascade,
  token text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (uid, token)
);

-- =====================================================================
-- Row level security
-- =====================================================================

alter table public.profiles enable row level security;
alter table public.usernames enable row level security;
alter table public.lotext_ids enable row level security;
alter table public.contacts enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.calls enable row level security;
alter table public.call_candidates enable row level security;
alter table public.device_tokens enable row level security;

-- Profiles are public to every signed-in user; only the owner writes theirs.
create policy "profiles are readable by authenticated users"
  on public.profiles for select to authenticated
  using (true);

create policy "users can insert their own profile"
  on public.profiles for insert to authenticated
  with check (uid = auth.uid());

create policy "users can update their own profile"
  on public.profiles for update to authenticated
  using (uid = auth.uid())
  with check (uid = auth.uid());

-- Registries: readable for lookups, writes only via SECURITY DEFINER RPCs.
create policy "usernames are readable by authenticated users"
  on public.usernames for select to authenticated
  using (true);

create policy "lotext ids are readable by authenticated users"
  on public.lotext_ids for select to authenticated
  using (true);

-- Contacts are private to the owner and one-way.
create policy "contacts are readable by their owner"
  on public.contacts for select to authenticated
  using (owner_uid = auth.uid());

create policy "contacts can be added by their owner"
  on public.contacts for insert to authenticated
  with check (owner_uid = auth.uid());

create policy "contacts can be removed by their owner"
  on public.contacts for delete to authenticated
  using (owner_uid = auth.uid());

-- Conversations are only visible to their participants.
create policy "conversations are readable by participants"
  on public.conversations for select to authenticated
  using (auth.uid() = any (participant_ids));

create policy "participants can create conversations"
  on public.conversations for insert to authenticated
  with check (auth.uid() = any (participant_ids));

create policy "participants can update conversations"
  on public.conversations for update to authenticated
  using (auth.uid() = any (participant_ids))
  with check (auth.uid() = any (participant_ids));

-- Messages: participants can read; delivery/read status changes go through the
-- mark_message_status RPC so message content can never be rewritten in place.
create policy "messages are readable by participants"
  on public.messages for select to authenticated
  using (exists (
    select 1 from public.conversations c
    where c.id = messages.conversation_id
      and auth.uid() = any (c.participant_ids)
  ));

-- No UPDATE policy on messages on purpose: the mark_message_status RPC is the
-- only allowed write path for status, so a participant can never tamper with
-- the other user's message content.

-- Calls are only visible to the two participants.
create policy "calls are readable by participants"
  on public.calls for select to authenticated
  using (auth.uid() in (caller_uid, callee_uid));

create policy "participants can create calls"
  on public.calls for insert to authenticated
  with check (auth.uid() in (caller_uid, callee_uid));

create policy "participants can update calls"
  on public.calls for update to authenticated
  using (auth.uid() in (caller_uid, callee_uid))
  with check (auth.uid() in (caller_uid, callee_uid));

-- ICE candidates follow the call's participants.
create policy "candidates are readable by call participants"
  on public.call_candidates for select to authenticated
  using (auth.uid() in (
    select caller_uid from public.calls c where c.id = call_candidates.call_id
  ) or auth.uid() in (
    select callee_uid from public.calls c where c.id = call_candidates.call_id
  ));

create policy "candidates can be written by call participants"
  on public.call_candidates for insert to authenticated
  with check (auth.uid() in (
    select caller_uid from public.calls c where c.id = call_candidates.call_id
  ) or auth.uid() in (
    select callee_uid from public.calls c where c.id = call_candidates.call_id
  ));

-- Device tokens are private per user.
create policy "tokens are readable by their owner"
  on public.device_tokens for select to authenticated
  using (uid = auth.uid());

create policy "tokens can be registered by their owner"
  on public.device_tokens for insert to authenticated
  with check (uid = auth.uid());

create policy "tokens can be removed by their owner"
  on public.device_tokens for delete to authenticated
  using (uid = auth.uid());

-- =====================================================================
-- New-user trigger: create the profile and allocate a LoText ID.
-- =====================================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id text;
begin
  insert into public.profiles (uid, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', ''))
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

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- =====================================================================
-- RPCs
-- =====================================================================

-- Atomically claims a username: verifies it is free, registers it, releases
-- the previous one, and updates the profile. Raises USERNAME_UNAVAILABLE when
-- the name belongs to someone else.
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

-- Ensures the user owns a LoText ID, allocating one when missing. Returns the
-- current (or newly allocated) ID.
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

-- Atomically inserts a message and updates the conversation summary plus the
-- receiver's unread counter. Idempotent for a resend with the same message id.
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
  p_size_bytes bigint default null
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
    duration_ms, width, height, file_name, mime_type, size_bytes, created_at_ms
  ) values (
    message_id, p_conversation_id, p_sender_uid, p_type,
    case when p_type = 'text' then btrim(p_text) else '' end,
    p_media_url, p_thumbnail_url, p_duration_ms, p_width, p_height,
    p_file_name, p_mime_type, p_size_bytes,
    (extract(epoch from now()) * 1000)::bigint
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

-- Resets a participant's unread counter.
create or replace function public.mark_conversation_read(
  p_conversation_id text,
  p_uid uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or auth.uid() <> p_uid then
    raise exception 'FORBIDDEN';
  end if;
  update public.conversations
  set unread_counts = jsonb_set(
        unread_counts,
        array[p_uid::text],
        '0'
      ),
      updated_at = now()
  where id = p_conversation_id;
end;
$$;

-- Marks a participant's received messages as delivered or read. The sender can
-- never mark their own messages, and status is the only column that changes.
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
  update public.messages
  set status = p_status
  where conversation_id = p_conversation_id
    and id = any (p_message_ids)
    and sender_uid <> auth.uid();
end;
$$;

-- =====================================================================
-- Storage
-- =====================================================================

insert into storage.buckets (id, name, public)
values ('chat_media', 'chat_media', true),
       ('profile_photos', 'profile_photos', true)
on conflict (id) do nothing;

-- chat_media/{conversationId}/{fileName}: readable by all authenticated users,
-- writable only by participants of that conversation.
create policy "chat_media is readable by authenticated users"
  on storage.objects for select to authenticated
  using (bucket_id = 'chat_media');

create policy "chat_media is writable by conversation participants"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'chat_media'
    and exists (
      select 1 from public.conversations c
      where c.id = (storage.foldername(name))[1]
        and auth.uid() = any (c.participant_ids)
    )
  );

-- profile_photos/{uid}: readable by all authenticated users, writable only by
-- the profile owner. Objects are named exactly `{uid}`.
create policy "profile_photos are readable by authenticated users"
  on storage.objects for select to authenticated
  using (bucket_id = 'profile_photos');

create policy "users can upload their own profile photo"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'profile_photos'
    and name = auth.uid()::text
  );

create policy "users can replace their own profile photo"
  on storage.objects for update to authenticated
  using (bucket_id = 'profile_photos' and name = auth.uid()::text)
  with check (bucket_id = 'profile_photos' and name = auth.uid()::text);

create policy "users can delete their own profile photo"
  on storage.objects for delete to authenticated
  using (bucket_id = 'profile_photos' and name = auth.uid()::text);

-- =====================================================================
-- Realtime
-- =====================================================================

alter publication supabase_realtime add table
  public.profiles,
  public.usernames,
  public.lotext_ids,
  public.contacts,
  public.conversations,
  public.messages,
  public.calls,
  public.call_candidates,
  public.device_tokens;

commit;
