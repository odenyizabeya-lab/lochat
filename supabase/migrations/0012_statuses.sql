-- LoText status updates (the Updates tab).
--
-- WhatsApp-style ephemeral statuses:
--   * statuses     - one row per post. Media objects live in the private
--                    `status_media` bucket at `{uid}/{statusId}` (and
--                    `{uid}/{statusId}_thumb` for video posters); the DB stores
--                    the object paths and the app resolves signed URLs at
--                    render time, exactly like chat media.
--   * status_views - one row per viewer per status (PK status_id, viewer_uid),
--                    so the author sees "Seen by" and the viewer can tell the
--                    Updates list which posts are already seen.
--
-- Visibility matches the Updates screen copy: a status is visible to the
-- author and the people the author has added as contacts. Writes go through
-- SECURITY DEFINER RPCs (post_status / delete_status / mark_status_viewed) so
-- the author check and the 24h expiry are applied server-side and atomically.
-- Every status expires after 24 hours; expired rows are purged on each post so
-- the table never grows unbounded.

begin;

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

create table if not exists public.statuses (
  id text primary key default gen_random_uuid()::text,
  uid uuid not null references auth.users (id) on delete cascade,
  type text not null default 'text'
    check (type in ('text', 'image', 'video')),
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

create table if not exists public.status_views (
  status_id text not null references public.statuses (id) on delete cascade,
  viewer_uid uuid not null references auth.users (id) on delete cascade,
  viewed_at timestamptz not null default now(),
  primary key (status_id, viewer_uid)
);

-- ---------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------

alter table public.statuses enable row level security;
alter table public.status_views enable row level security;

-- A status is readable by its author and the author's contacts.
create policy "statuses are readable by the author and their contacts"
  on public.statuses for select to authenticated
  using (
    uid = auth.uid()
    or exists (
      select 1 from public.contacts c
      where c.owner_uid = statuses.uid
        and c.contact_uid = auth.uid()
    )
  );

create policy "users can post their own status"
  on public.statuses for insert to authenticated
  with check (uid = auth.uid());

create policy "users can delete their own status"
  on public.statuses for delete to authenticated
  using (uid = auth.uid());

-- Views: the author can see who viewed; a viewer can see their own view rows
-- (so the Updates list can tell what is already seen). No direct INSERT/DELETE
-- policies: views are only ever written by the mark_status_viewed RPC.
create policy "views are readable by the status author"
  on public.status_views for select to authenticated
  using (exists (
    select 1 from public.statuses s
    where s.id = status_views.status_id
      and s.uid = auth.uid()
  ));

create policy "views are readable by their viewer"
  on public.status_views for select to authenticated
  using (viewer_uid = auth.uid());

-- ---------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------

-- Posts a status on behalf of the caller. Purges expired statuses first so
-- the table only ever holds live rows. Media statuses require the object
-- path; text statuses require text. [p_status_id] is client-generated so the
-- stored media path (`{uid}/{statusId}`) matches the row id and deletes can
-- find the objects.
create or replace function public.post_status(
  p_type text,
  p_text text default '',
  p_status_id text default null,
  p_media_url text default null,
  p_thumbnail_url text default null,
  p_duration_ms int default null,
  p_width double precision default null,
  p_height double precision default null,
  p_mime_type text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  status_id text;
  created bigint;
begin
  if p_type not in ('text', 'image', 'video') then
    raise exception 'INVALID_TYPE';
  end if;
  if p_type = 'text' and btrim(coalesce(p_text, '')) = '' then
    raise exception 'EMPTY_STATUS';
  end if;
  if p_type <> 'text' and (p_media_url is null or p_media_url = '') then
    raise exception 'EMPTY_STATUS';
  end if;
  if p_text is not null and char_length(p_text) > 500 then
    raise exception 'STATUS_TOO_LONG';
  end if;

  -- Garbage-collect expired statuses (and their views) on every post.
  delete from public.statuses where expires_at <= now();

  status_id := coalesce(p_status_id, gen_random_uuid()::text);
  created := (extract(epoch from now()) * 1000)::bigint;

  insert into public.statuses (
    id, uid, type, text, media_url, thumbnail_url, duration_ms,
    width, height, mime_type, created_at_ms, expires_at
  ) values (
    status_id, auth.uid(), p_type,
    case when p_type = 'text' then btrim(p_text) else '' end,
    p_media_url, p_thumbnail_url, p_duration_ms,
    p_width, p_height, p_mime_type, created,
    now() + interval '24 hours'
  )
  on conflict (id) do nothing;

  return status_id;
end;
$$;

-- Deletes one of the caller's own statuses, including its media objects.
create or replace function public.delete_status(p_status_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.statuses
    where id = p_status_id and uid = auth.uid()
  ) then
    return;
  end if;

  delete from public.statuses where id = p_status_id and uid = auth.uid();

  delete from storage.objects
  where bucket_id = 'status_media'
    and (storage.foldername(name))[1] = auth.uid()::text
    and (storage.foldername(name))[2] like p_status_id || '%';
end;
$$;

-- Records that the caller viewed a status. The caller must be a contact of the
-- author (mirrors the read policy). Idempotent for repeated views.
create or replace function public.mark_status_viewed(p_status_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.statuses s
    where s.id = p_status_id
      and s.expires_at > now()
      and s.uid <> auth.uid()
      and exists (
        select 1 from public.contacts c
        where c.owner_uid = s.uid
          and c.contact_uid = auth.uid()
      )
  ) then
    return;
  end if;

  insert into public.status_views (status_id, viewer_uid)
  values (p_status_id, auth.uid())
  on conflict (status_id, viewer_uid) do nothing;
end;
$$;

-- ---------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------

-- Updates list: statuses of one author (and the realtime stream) sorted newest
-- first.
create index if not exists idx_statuses_uid_created_ms
  on public.statuses (uid, created_at_ms desc);

-- The author's "Seen by" list.
create index if not exists idx_status_views_status_id
  on public.status_views (status_id);

-- ---------------------------------------------------------------------
-- Storage: private status_media bucket, keyed by `{uid}/{statusId}`.
-- ---------------------------------------------------------------------

insert into storage.buckets (id, name, public)
values ('status_media', 'status_media', false)
on conflict (id) do nothing;

-- Readable by the author and the author's contacts (same rule as the table).
create policy "status_media is readable by the author and their contacts"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'status_media'
    and (
      auth.uid()::text = (storage.foldername(name))[1]
      or exists (
        select 1 from public.contacts c
        where c.owner_uid::text = (storage.foldername(name))[1]
          and c.contact_uid = auth.uid()
      )
    )
  );

create policy "status media can be uploaded by its owner"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'status_media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "status media can be replaced by its owner"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'status_media'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'status_media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

create policy "status media can be deleted by its owner"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'status_media'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- ---------------------------------------------------------------------
-- Realtime
-- ---------------------------------------------------------------------

alter publication supabase_realtime add table
  public.statuses,
  public.status_views;

commit;
