-- LoText AI Assistant schema.
--
-- Conversations and messages for the AI assistant live in Postgres so history
-- is private to each user and survives across devices. The app only talks to
-- these tables through the `ai-assistant` edge function (which resolves the
-- caller from their JWT and writes with the service role), so the RLS policies
-- below are defence in depth: even if a client gained direct access it could
-- only ever read or write its own rows.
--
-- Idempotent: safe to run again after a partial run.

begin;

drop policy if exists "ai conversations are readable by their owner"
  on public.ai_conversations;
drop policy if exists "ai conversations can be created by their owner"
  on public.ai_conversations;
drop policy if exists "ai conversations can be updated by their owner"
  on public.ai_conversations;
drop policy if exists "ai conversations can be deleted by their owner"
  on public.ai_conversations;
drop policy if exists "ai messages are readable by conversation owners"
  on public.ai_messages;
drop policy if exists "ai messages can be written by conversation owners"
  on public.ai_messages;

create table if not exists public.ai_conversations (
  id uuid primary key default gen_random_uuid(),
  owner_uid uuid not null references auth.users (id) on delete cascade,
  title text not null default 'New chat',
  provider text not null default 'openai'
    check (provider in ('openai', 'anthropic', 'gemini')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.ai_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null
    references public.ai_conversations (id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null,
  created_at timestamptz not null default now()
);

alter table public.ai_conversations enable row level security;
alter table public.ai_messages enable row level security;

create policy "ai conversations are readable by their owner"
  on public.ai_conversations for select to authenticated
  using (owner_uid = auth.uid());

create policy "ai conversations can be created by their owner"
  on public.ai_conversations for insert to authenticated
  with check (owner_uid = auth.uid());

create policy "ai conversations can be updated by their owner"
  on public.ai_conversations for update to authenticated
  using (owner_uid = auth.uid())
  with check (owner_uid = auth.uid());

create policy "ai conversations can be deleted by their owner"
  on public.ai_conversations for delete to authenticated
  using (owner_uid = auth.uid());

create policy "ai messages are readable by conversation owners"
  on public.ai_messages for select to authenticated
  using (conversation_id in (
    select id from public.ai_conversations where owner_uid = auth.uid()
  ));

create policy "ai messages can be written by conversation owners"
  on public.ai_messages for insert to authenticated
  with check (conversation_id in (
    select id from public.ai_conversations where owner_uid = auth.uid()
  ));

commit;
