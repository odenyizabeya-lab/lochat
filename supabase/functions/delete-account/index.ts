// LoText account deletion — permanent account and data removal.
//
// Triggered from Settings -> Delete account. Supabase client sessions cannot
// delete the user themselves, so this edge function acts on the caller's
// behalf with the service role:
//   1. resolves the caller from the Supabase JWT (edge functions verify the
//      Authorization header by default, so only the signed-in user can trigger
//      it),
//   2. deletes the user's conversations (they have no FK to auth.users — the
//      participant list is an array — so the auth delete cannot reach them);
//      this cascades to the messages, calls and ICE candidates of those
//      conversations,
//   3. removes every storage object the user owns (chat media per conversation,
//      profile photos and status media; storage is never touched by an auth
//      user delete),
//   4. deletes the auth user itself, which cascades to profiles, usernames,
//      lotext_ids, contacts, device_tokens, statuses, status_views and AI
//      conversations (all reference auth.users(id) on delete cascade).
//
// There is no restore: the user, their usernames/LoText IDs and all of their
// data are permanently gone.

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const STORAGE_BUCKETS = ["chat_media", "profile_photos", "status_media"] as const;

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/// Recursively removes every object under [prefix] in [bucket]. Missing buckets
/// and empty folders are silently skipped. Returns the number of objects
/// removed.
async function removeFolder(
  admin: ReturnType<typeof createClient>,
  bucket: string,
  prefix: string,
): Promise<number> {
  const { data, error } = await admin.storage.from(bucket).list(prefix);
  if (error || !data) return 0;
  let removed = 0;
  const files: string[] = [];
  for (const entry of data) {
    if (entry.metadata === null) {
      removed += await removeFolder(admin, bucket, `${prefix}${entry.name}/`);
    } else {
      files.push(`${prefix}${entry.name}`);
    }
  }
  if (files.length > 0) {
    const { error: removeError } = await admin.storage.from(bucket).remove(files);
    if (!removeError) removed += files.length;
  }
  return removed;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) {
    return json({ error: "Function is not configured." }, 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Unauthorized" }, 401);

  const client = createClient(supabaseUrl, "anon");
  const {
    data: { user },
    error: userError,
  } = await client.auth.getUser(token);
  if (userError || !user) {
    return json({ error: "Unauthorized" }, 401);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false },
  });

  try {
    // 1. All conversations involving this user.
    const { data: rows, error: rowsError } = await admin
      .from("conversations")
      .select("id")
      .contains("participant_ids", [user.id]);
    if (rowsError) throw new Error("Could not load your conversations");
    const conversationIds = (rows ?? []).map((row) => row.id as string);

    if (conversationIds.length > 0) {
      const { error: deleteError } = await admin
        .from("conversations")
        .delete()
        .in("id", conversationIds);
      if (deleteError) throw new Error("Could not delete your conversations");
    }

    // 2. Storage owned by this user.
    for (const bucket of STORAGE_BUCKETS) {
      if (bucket === "chat_media") {
        for (const conversationId of conversationIds) {
          await removeFolder(admin, bucket, `${conversationId}/`);
        }
      } else {
        await removeFolder(admin, bucket, `${user.id}/`);
      }
    }

    // 3. The auth user (hard delete). Cascades to every per-user table.
    const { error: deleteError } = await admin.auth.admin.deleteUser(
      user.id,
      false,
    );
    if (deleteError) throw new Error("Could not delete your account");

    return json({ ok: true });
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unexpected error";
    return json({ error: message }, 400);
  }
});
