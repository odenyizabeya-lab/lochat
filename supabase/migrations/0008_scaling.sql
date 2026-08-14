-- LoText scalability: indexes for the hot read paths.
--
-- Before this migration only primary keys existed, so queries that filter or
-- order by anything else (the chat list, the message window, call history,
-- FCM fan-out) had to seq-scan the whole table. As conversations grow those
-- scans are what make the app feel like it's hanging. These indexes turn the
-- hot paths into index seeks.

begin;

-- Chat window: WHERE conversation_id = ? ORDER BY created_at_ms DESC LIMIT 100.
-- The (id, conversation_id) PK does not help here.
create index if not exists idx_messages_conversation_created_ms
  on public.messages (conversation_id, created_at_ms desc);

-- Chats list: ORDER BY last_message_at DESC over the caller's conversations.
create index if not exists idx_conversations_last_message_at
  on public.conversations (last_message_at desc);

-- Call history is queried by caller and by callee; candidates by call id.
create index if not exists idx_calls_caller_uid
  on public.calls (caller_uid, created_at desc);
create index if not exists idx_calls_callee_uid
  on public.calls (callee_uid, created_at desc);
create index if not exists idx_call_candidates_call_id
  on public.call_candidates (call_id);

-- FCM cleanup deletes a token by its value; the (uid, token) PK only covers
-- uid-prefixed lookups.
create index if not exists idx_device_tokens_token
  on public.device_tokens (token);

-- Lookups that go from a uid back to a registry row.
create index if not exists idx_usernames_uid
  on public.usernames (uid);

commit;
