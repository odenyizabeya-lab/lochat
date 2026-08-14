# LoText

A professional, cross-platform messaging app — chats, voice & video calls,
status updates and an AI assistant — built with Flutter and Supabase.

## Features

**Chats**
- One-to-one messaging with your contacts, plus typing indicators, unread
  badges and message status (sent / delivered / read)
- Media messages: photos, videos and voice notes, with inline playback
- Reply to a message, pick emoji from a searchable picker, and manage
  conversation previews
- Real-time translation: auto-translate incoming messages to your preferred
  language, or translate any message on demand (and even change your voice
  effect)

**Calls**
- WhatsApp-style voice and video calls over WebRTC (peer-to-peer when
  possible, relayed otherwise)
- Live call history with one-tap call-back, missed/declined states, durations
  and name search
- Full-screen active-call UI with mute, camera toggle and elapsed time

**Status (Updates)**
- Text, photo and video statuses that expire after 24 hours
- Grouped ring UI, view tracking per contact and delete-your-own-status

**Profile & contacts**
- Claim a username and a human-readable LoText ID
- Private, one-way contact list; add people by exact LoText ID or username
- Presence: online / last-seen, avatar photos, editable display name

**AI assistant (admin-gated)**
- Chat with an AI assistant wired to configurable providers (OpenAI, Anthropic,
  Gemini) through the `ai-assistant` edge function
- Admin dashboard to manage provider keys, an admin chat room, and an
  admin-only gate for the assistant

**Extras**
- Light and dark themes, in-app language picker
- FCM push notifications for new messages (via the `notify` edge function)
- Branded launcher icons and splash screens across Android, iOS and web

## Tech stack

| Layer      | Choice |
| ---------- | ------ |
| App        | Flutter (Dart), Material 3 |
| Backend    | Supabase — Auth, Postgres + RLS, Realtime, Storage |
| Routing    | `go_router` (stateful shell + detail routes) |
| Calls      | `flutter_webrtc` with live signaling documents over Supabase Realtime |
| Media      | `image_picker`, `video_player`, `just_audio`, `record`, compressors |
| Notifications | `flutter_local_notifications` + FCM token registration |
| Edge functions | `supabase/functions/ai-assistant`, `supabase/functions/notify` |

## Project structure

```
lib/
  core/        auth, router, theme, supabase wiring, shared utils
  features/
    ai/        AI assistant (admin-gated chat)
    admin/     provider-key dashboard + admin chat room
    auth/      welcome / login / register / forgot password
    calls/     WebRTC calls, signaling, call history (screens/, rtc/, signaling/)
    chat/      conversations, messages, media, translation
    home/      main shell: Chats / Calls / Updates / Tools tabs
    profile/   profiles, LoText IDs, contacts
    settings/  theme + language
    status/    status updates (Updates tab)
    splash/    startup gating
  shared/      reusable widgets
supabase/
  migrations/  0001..0012 database schema, RLS policies, RPCs
  functions/   ai-assistant, notify edge functions
test/
  fakes.dart   in-memory fakes for every service (no platform channels)
  widget_test.dart + features/  56 widget tests
```

## Getting started

### Prerequisites

- Flutter SDK (see `pubspec.yaml` for the Dart SDK constraint)
- A [Supabase](https://supabase.com) project
- Docker + the Supabase CLI for local edge function development (optional)

### 1. Backend setup

Run the migrations against your Supabase project in order:

```sh
supabase db push   # applies supabase/migrations/0001..0012
```

Deploy the edge functions:

```sh
supabase functions deploy ai-assistant
supabase functions deploy notify
```

Set environment secrets the functions need (e.g. `OPENAI_API_KEY`) either in
the Supabase dashboard or through the app's **Admin** dashboard (which stores
them in the `app_config` table and uses them at call time).

### 2. Run the app

The Supabase URL and publishable key are injected at build time so no secrets
are committed:

```sh
flutter run --dart-define=LOTEXT_SUPABASE_URL=https://<project>.supabase.co \
            --dart-define=LOTEXT_SUPABASE_KEY=<publishable-key>
```

The same flags work with `flutter build apk` / `flutter build ios` /
`flutter build web`. The app refuses to start without them.

### 3. Admin access

The first user to open **Settings** is auto-promoted to admin (and can then
reach the AI assistant and admin dashboard). Every subsequent admin must be
promoted by an existing admin — see the admin dashboard.

## Testing

The suite runs against in-memory fakes (see `test/fakes.dart`) so no network
or platform channels are needed:

```sh
flutter analyze
flutter test
```

Widget tests cover the full shell — chat, calls, contacts, profile, status,
AI gating and admin flows — at a realistic phone surface size.
