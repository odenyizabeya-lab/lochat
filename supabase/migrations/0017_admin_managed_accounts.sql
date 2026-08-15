-- Admin managed accounts: up to 10 separate chat room accounts per admin.

create table if not exists public.admin_managed_accounts (
  id uuid primary key default gen_random_uuid(),
  admin_uid uuid not null references auth.users(id) on delete cascade,
  slot_index integer not null check (slot_index between 1 and 10),
  lotext_id text,
  username text not null,
  display_name text not null,
  photo_url text,
  settings jsonb default '{}',
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(admin_uid, slot_index),
  unique(admin_uid, username),
  unique(admin_uid, lotext_id)
);

create table if not exists public.managed_account_contacts (
  managed_account_id uuid not null references admin_managed_accounts(id) on delete cascade,
  contact_uid uuid not null,
  display_name text not null,
  username text not null,
  photo_url text,
  created_at timestamptz default now(),
  primary key (managed_account_id, contact_uid)
);

create table if not exists public.managed_account_conversations (
  id uuid primary key default gen_random_uuid(),
  managed_account_id uuid not null references admin_managed_accounts(id) on delete cascade,
  peer_uid uuid not null,
  peer_display_name text not null,
  peer_username text not null,
  peer_photo_url text,
  last_message_text text,
  last_message_at timestamptz,
  last_sender_uid uuid,
  unread_count integer default 0,
  typing_uid uuid,
  typing_until timestamptz,
  last_message_type text,
  last_message_duration_ms integer,
  created_at timestamptz default now(),
  unique(managed_account_id, peer_uid)
);

create table if not exists public.managed_account_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references managed_account_conversations(id) on delete cascade,
  managed_account_id uuid not null references admin_managed_accounts(id) on delete cascade,
  sender_uid uuid not null,
  type text not null,
  text text,
  media_url text,
  voice_effect text,
  reply_to_id uuid,
  reply_to_type text,
  reply_to_text text,
  reply_to_sender text,
  sender_lang text,
  original_text text,
  source_lang text,
  status text default 'sent',
  created_at timestamptz default now()
);

create index if not exists idx_managed_accounts_admin on public.admin_managed_accounts(admin_uid);
create index if not exists idx_managed_conversations_account on public.managed_account_conversations(managed_account_id);
create index if not exists idx_managed_messages_conversation on public.managed_account_messages(conversation_id);
create index if not exists idx_managed_messages_account on public.managed_account_messages(managed_account_id);

alter table public.admin_managed_accounts enable row level security;
alter table public.managed_account_contacts enable row level security;
alter table public.managed_account_conversations enable row level security;
alter table public.managed_account_messages enable row level security;

create policy "admin_manage_own_accounts" on public.admin_managed_accounts
  for all using (auth.uid() = admin_uid)
  with check (auth.uid() = admin_uid);

create policy "admin_manage_contacts" on public.managed_account_contacts
  for all using (
    exists (
      select 1 from public.admin_managed_accounts
      where id = managed_account_id and admin_uid = auth.uid()
    )
  );

create policy "admin_manage_conversations" on public.managed_account_conversations
  for all using (
    exists (
      select 1 from public.admin_managed_accounts
      where id = managed_account_id and admin_uid = auth.uid()
    )
  );

create policy "admin_manage_messages" on public.managed_account_messages
  for all using (
    exists (
      select 1 from public.admin_managed_accounts
      where id = managed_account_id and admin_uid = auth.uid()
    )
  );
