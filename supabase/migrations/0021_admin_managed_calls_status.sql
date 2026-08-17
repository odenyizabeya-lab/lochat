-- Admin managed accounts: voice/video call records and status (updates)
-- posting, all scoped to the owning admin (mirrors the user-side `calls` and
-- `statuses` tables but keyed by managed_account_id).

begin;

-- ---------------------------------------------------------------------
-- Managed calls
-- ---------------------------------------------------------------------

create table if not exists public.managed_account_calls (
  id text primary key default gen_random_uuid()::text,
  managed_account_id uuid not null references public.admin_managed_accounts(id) on delete cascade,
  conversation_id uuid not null references public.managed_account_conversations(id) on delete cascade,
  peer_uid uuid not null,
  type text not null check (type in ('audio', 'video')),
  status text not null default 'ringing'
    check (status in ('ringing', 'active', 'ended', 'missed', 'declined')),
  created_at timestamptz not null default now(),
  answered_at timestamptz,
  ended_at timestamptz,
  ended_by uuid
);

create index if not exists idx_managed_calls_account on public.managed_account_calls(managed_account_id, created_at desc);
create index if not exists idx_managed_calls_conversation on public.managed_account_calls(conversation_id);

alter table public.managed_account_calls enable row level security;

create policy "admin_manage_calls" on public.managed_account_calls
  for all using (
    exists (
      select 1 from public.admin_managed_accounts
      where id = managed_account_id and admin_uid = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.admin_managed_accounts
      where id = managed_account_id and admin_uid = auth.uid()
    )
  );

-- ---------------------------------------------------------------------
-- Managed statuses (updates) + views
-- ---------------------------------------------------------------------

create table if not exists public.managed_account_statuses (
  id text primary key default gen_random_uuid()::text,
  managed_account_id uuid not null references public.admin_managed_accounts(id) on delete cascade,
  type text not null default 'text' check (type in ('text', 'image', 'video')),
  text text not null default '',
  media_url text,
  thumbnail_url text,
  duration_ms int,
  width double precision,
  height double precision,
  mime_type text,
  created_at timestamptz not null default now(),
  created_at_ms bigint not null,
  expires_at timestamptz not null
);

create table if not exists public.managed_account_status_views (
  status_id text not null references public.managed_account_statuses(id) on delete cascade,
  viewer_uid uuid not null,
  viewed_at timestamptz not null default now(),
  primary key (status_id, viewer_uid)
);

create index if not exists idx_managed_statuses_account on public.managed_account_statuses(managed_account_id, created_at_ms desc);
create index if not exists idx_managed_status_views_status on public.managed_account_status_views(status_id);

alter table public.managed_account_statuses enable row level security;
alter table public.managed_account_status_views enable row level security;

create policy "admin_manage_statuses" on public.managed_account_statuses
  for all using (
    exists (
      select 1 from public.admin_managed_accounts
      where id = managed_account_id and admin_uid = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.admin_managed_accounts
      where id = managed_account_id and admin_uid = auth.uid()
    )
  );

create policy "admin_manage_status_views" on public.managed_account_status_views
  for all using (
    exists (
      select 1 from public.managed_account_statuses s
      where s.id = status_id
        and exists (
          select 1 from public.admin_managed_accounts a
          where a.id = s.managed_account_id and a.admin_uid = auth.uid()
        )
    )
  )
  with check (
    exists (
      select 1 from public.managed_account_statuses s
      where s.id = status_id
        and exists (
          select 1 from public.admin_managed_accounts a
          where a.id = s.managed_account_id and a.admin_uid = auth.uid()
        )
    )
  );

-- ---------------------------------------------------------------------
-- post_managed_status: owner-gated insert with 24h expiry.
-- ---------------------------------------------------------------------

create or replace function public.post_managed_status(p_status jsonb)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  managed_account_id_value uuid;
  status_id text;
begin
  managed_account_id_value := (p_status ->> 'managed_account_id')::uuid;

  if managed_account_id_value is null then
    raise exception 'INVALID_ACCOUNT';
  end if;

  if not exists (
    select 1 from public.admin_managed_accounts a
    where a.id = managed_account_id_value and a.admin_uid = auth.uid()
  ) then
    raise exception 'FORBIDDEN';
  end if;

  status_id := coalesce(p_status ->> 'id', gen_random_uuid()::text);

  insert into public.managed_account_statuses (
    id, managed_account_id, type, text, media_url, thumbnail_url,
    duration_ms, width, height, mime_type, created_at_ms, expires_at
  ) values (
    status_id,
    managed_account_id_value,
    coalesce(p_status ->> 'type', 'text'),
    coalesce(p_status ->> 'text', ''),
    nullif(p_status ->> 'media_url', ''),
    nullif(p_status ->> 'thumbnail_url', ''),
    nullif((p_status ->> 'duration_ms')::int, null)::int,
    nullif((p_status ->> 'width')::double precision, null)::double precision,
    nullif((p_status ->> 'height')::double precision, null)::double precision,
    nullif(p_status ->> 'mime_type', ''),
    (extract(epoch from now()) * 1000)::bigint,
    now() + interval '24 hours'
  )
  on conflict (id) do nothing;

  return status_id;
end;
$$;

-- ---------------------------------------------------------------------
-- delete_managed_status: owner-gated delete that also removes media objects.
-- ---------------------------------------------------------------------

create or replace function public.delete_managed_status(p_status_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.managed_account_statuses s
    where s.id = p_status_id
      and exists (
        select 1 from public.admin_managed_accounts a
        where a.id = s.managed_account_id and a.admin_uid = auth.uid()
      )
  ) then
    return;
  end if;

  delete from storage.objects
  where bucket_id = 'managed_status_media'
    and (storage.foldername(name))[1]::uuid in (
      select a.id from public.admin_managed_accounts a
      where a.admin_uid = auth.uid()
    )
    and (storage.foldername(name))[2] like p_status_id || '%';

  delete from public.managed_account_statuses where id = p_status_id;
end;
$$;

-- ---------------------------------------------------------------------
-- mark_managed_status_viewed: record a view for a non-author.
-- ---------------------------------------------------------------------

create or replace function public.mark_managed_status_viewed(p_status_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.managed_account_statuses s
    where s.id = p_status_id and s.expires_at > now()
  ) then
    insert into public.managed_account_status_views (status_id, viewer_uid)
    values (p_status_id, auth.uid())
    on conflict (status_id, viewer_uid) do nothing;
  end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Realtime: the app's .stream() queries need these in the publication.
-- ---------------------------------------------------------------------

alter publication supabase_realtime add table
  public.managed_account_calls,
  public.managed_account_statuses,
  public.managed_account_status_views;

-- ---------------------------------------------------------------------
-- Storage bucket for status media (private to the owning admin).
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('managed_status_media', 'managed_status_media', true)
on conflict (id) do nothing;

create policy "managed_status_media is readable by authenticated users"
  on storage.objects for select to authenticated
  using (bucket_id = 'managed_status_media');

create policy "managed_status_media is writable by owning admins"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'managed_status_media'
    and (storage.foldername(name))[1]::uuid in (
      select a.id from public.admin_managed_accounts a
      where a.admin_uid = auth.uid()
    )
  );

create policy "managed_status_media is deletable by owning admins"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'managed_status_media'
    and (storage.foldername(name))[1]::uuid in (
      select a.id from public.admin_managed_accounts a
      where a.admin_uid = auth.uid()
    )
  );

commit;