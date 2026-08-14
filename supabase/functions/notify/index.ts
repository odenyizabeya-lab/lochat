// LoText push notifications — FCM (Firebase Cloud Messaging) HTTP v1 sender.
//
// Backend half of the push pipeline. The app registers each device's token in
// `device_tokens` (ChatRepository.registerFcmToken); the Postgres trigger in
// migration 0009 posts every new message here, and this function fans it out
// as a notification to the receiver's devices.
//
// The function is triggered by the DB (not by an end-user request), so it is
// intentionally NOT verify_jwt. It authenticates with a shared secret header
// instead. Configure it once with:
//
//   supabase secrets set NOTIFY_WEBHOOK_SECRET=<random string> \
//     FCM_PROJECT_ID=<your firebase project id> \
//     FCM_CLIENT_EMAIL=<service account email> \
//     "FCM_PRIVATE_KEY=-----BEGIN PRIVATE KEY-----..."
//
// FCM_* values come from the Firebase project's service-account JSON
// (Project settings -> Service accounts -> Generate new private key).
//
// The trigger reads NOTIFY_FUNCTION_URL and NOTIFY_WEBHOOK_SECRET from the
// `app_config` table (see migration 0009), so the webhook is a no-op until the
// app's admin inserts those two rows.

import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-notify-secret",
};

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const FCM_TOKEN_URL = "https://oauth2.googleapis.com/token";
const FCM_URL = "https://fcm.googleapis.com/v1";

const TYPE_SUMMARY: Record<string, string> = {
  text: "",
  image: "Photo",
  video: "Video",
  voice: "Voice message",
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// FCM HTTP v1 sends need an OAuth2 access token minted from the service
// account. Tokens live 1 hour, so cache them and refresh lazily.
let cachedAccessToken: { value: string; expiresAt: number } | null = null;

async function mintAccessToken(
  clientEmail: string,
  key: CryptoKey,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && cachedAccessToken.expiresAt - now > 120) {
    return cachedAccessToken.value;
  }
  const jwt = await new SignJWT({ scope: FCM_SCOPE })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(clientEmail)
    .setSubject(clientEmail)
    .setAudience(FCM_TOKEN_URL)
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);
  const res = await fetch(FCM_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(data?.error_description ?? "Could not get an OAuth token");
  }
  cachedAccessToken = {
    value: data.access_token as string,
    expiresAt: now + 3600,
  };
  return cachedAccessToken.value;
}

interface FcmSendArgs {
  token: string;
  title: string;
  body: string;
  conversationId: string;
}

async function sendFcm(
  projectId: string,
  clientEmail: string,
  key: CryptoKey,
  args: FcmSendArgs,
): Promise<void> {
  const accessToken = await mintAccessToken(clientEmail, key);
  const res = await fetch(`${FCM_URL}/projects/${projectId}/messages:send`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      message: {
        token: args.token,
        notification: { title: args.title, body: args.body },
        data: {
          conversationId: args.conversationId,
          url: "/home/chats",
        },
        android: { priority: "high", notification: { sound: "default" } },
        apns: { payload: { aps: { sound: "default" } } },
      },
    }),
  });
  if (!res.ok) {
    const detail = await res.json().catch(() => null);
    const error = new Error(
      `FCM ${res.status}: ${detail?.error?.message ?? res.statusText}`,
    ) as Error & { status?: number; code?: string };
    error.status = res.status;
    error.code = detail?.error?.status ?? "";
    throw error;
  }
}

// Unregistered / revoked tokens come back 404 (NOT_FOUND) or UNREGISTERED.
function isUnregistered(error: unknown): boolean {
  const e = error as { status?: number; code?: string; message?: string };
  return (
    e?.status === 404 ||
    e?.code === "UNREGISTERED" ||
    e?.code === "NOT_FOUND" ||
    /unregistered/i.test(e?.message ?? "")
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const webhookSecret = Deno.env.get("NOTIFY_WEBHOOK_SECRET") ?? "";
  if (
    webhookSecret === "" ||
    req.headers.get("x-notify-secret") !== webhookSecret
  ) {
    return json({ error: "Unauthorized" }, 401);
  }

  try {
    const body = await req.json();
    const conversationId = String(body.conversationId ?? "");
    if (conversationId === "") {
      return json({ error: "conversationId is required" }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (supabaseUrl === "" || serviceKey === "") {
      throw new Error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are missing");
    }
    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false },
    });

    const { data: conversation, error: conversationError } = await admin
      .from("conversations")
      .select("participant_ids")
      .eq("id", conversationId)
      .single();
    if (conversationError || !conversation) {
      return json({ error: "Conversation not found" }, 404);
    }
    const participants = (conversation.participant_ids ?? []) as string[];
    if (participants.length !== 2) {
      return json({ error: "Invalid conversation" }, 400);
    }

    const { data: message } = await admin
      .from("messages")
      .select("sender_uid, type, text")
      .eq("conversation_id", conversationId)
      .order("created_at_ms", { ascending: false })
      .limit(1)
      .single();
    if (!message || !message.sender_uid) {
      return json({ error: "No message found" }, 400);
    }
    const senderUid = message.sender_uid as string;
    const receiverUid =
      participants[0] === senderUid ? participants[1] : participants[0];

    const { data: sender } = await admin
      .from("profiles")
      .select("display_name, username")
      .eq("uid", senderUid)
      .single();
    const senderName = sender?.display_name || sender?.username || "Someone";

    const summary =
      message.type === "text"
        ? String(message.text ?? "")
        : (TYPE_SUMMARY[String(message.type)] ?? "New message");
    const bodyText = summary.length > 200
      ? `${summary.slice(0, 197)}\u2026`
      : summary;

    const { data: tokens } = await admin
      .from("device_tokens")
      .select("token")
      .eq("uid", receiverUid);
    const tokenList = (tokens ?? [])
      .map((t) => t.token as string)
      .filter((t) => t && t.length > 0);
    if (tokenList.length === 0) {
      return json({ ok: true, sent: 0, removed: 0 });
    }

    const projectId = Deno.env.get("FCM_PROJECT_ID") ?? "";
    const clientEmail = Deno.env.get("FCM_CLIENT_EMAIL") ?? "";
    const privateKey = (Deno.env.get("FCM_PRIVATE_KEY") ?? "").replace(
      /\\n/g,
      "\n",
    );
    if (projectId === "" || clientEmail === "" || privateKey === "") {
      throw new Error("FCM_PROJECT_ID / FCM_CLIENT_EMAIL / FCM_PRIVATE_KEY are not set");
    }
    const key = await importPKCS8(privateKey, "RS256");

    let sent = 0;
    const invalid: string[] = [];
    for (const token of tokenList) {
      try {
        await sendFcm(projectId, clientEmail, key, {
          token,
          title: senderName,
          body: bodyText,
          conversationId,
        });
        sent++;
      } catch (error) {
        if (isUnregistered(error)) invalid.push(token);
      }
    }

    if (invalid.length > 0) {
      await admin.from("device_tokens").delete().eq("uid", receiverUid).in(
        "token",
        invalid,
      );
    }

    return json({ ok: true, sent, removed: invalid.length });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unexpected error";
    return json({ error: message }, 400);
  }
});
