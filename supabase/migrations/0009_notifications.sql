-- LoText push notifications — trigger that forwards new messages to the FCM
-- `notify` edge function (supabase/functions/notify).
--
-- The app registers device tokens in `device_tokens`; this trigger posts every
-- new message to the notify function, which sends an FCM notification to the
-- receiver's devices. The receiver still sees the message in-app via Realtime;
-- the push is only for when the app is in the background or closed (the client
-- ignores it while the matching chat is on screen).
--
-- The webhook is disabled until it is configured, so this migration is safe to
-- deploy before Firebase exists. Configure it from the app's Admin dashboard
-- (or SQL) once the notify function is deployed and its secrets are set:
--
--   insert into public.app_config (key, value) values
--     ('NOTIFY_FUNCTION_URL', 'https://<project-ref>.supabase.co/functions/v1/notify'),
--     ('NOTIFY_WEBHOOK_SECRET', '<same value as the NOTIFY_WEBHOOK_SECRET secret>')
--   on conflict (key) do update
--     set value = excluded.value, updated_at = now();
--
-- Deploy steps:
--   supabase db push
--   supabase functions deploy notify
--   supabase secrets set NOTIFY_WEBHOOK_SECRET=... FCM_PROJECT_ID=... \
--     FCM_CLIENT_EMAIL=... "FCM_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----..."

begin;

-- pg_net lets the trigger fire-and-forget an HTTP request. It ships with
-- Supabase; on a self-hosted database grant EXECUTE on net.http_post to the
-- `postgres` role instead of granting it publicly.
create extension if not exists pg_net;

create or replace function public.notify_new_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  function_url text;
  secret_value text;
  payload jsonb;
begin
  -- No-op until the admin configures the webhook (see file header).
  select value into function_url
  from public.app_config
  where key = 'NOTIFY_FUNCTION_URL';
  if function_url is null or function_url = '' then
    return new;
  end if;

  select value into secret_value
  from public.app_config
  where key = 'NOTIFY_WEBHOOK_SECRET';

  payload := jsonb_build_object(
    'conversationId', new.conversation_id,
    'messageId', new.id
  );

  perform net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-notify-secret', coalesce(secret_value, '')
    ),
    body := payload
  );
  return new;
end;
$$;

drop trigger if exists on_message_notify on public.messages;

create trigger on_message_notify
  after insert on public.messages
  for each row execute function public.notify_new_message();

commit;
