// LoText AI Assistant — provider-agnostic backend.
//
// The app never talks to an AI provider directly, and no AI API key ever ships
// in the app. This edge function:
//   1. resolves the caller from the Supabase JWT (edge functions verify the
//      Authorization header by default, so only signed-in users can call it),
//   2. persists conversations and messages in Postgres via the service role,
//   3. calls the selected provider (OpenAI / Anthropic / Gemini) whose key
//      lives in the function's environment (supabase secrets) or in the
//      `app_config` table managed from the app's Admin dashboard.
//
// Provider keys are resolved in this order: environment first (set once with
// `supabase secrets set OPENAI_API_KEY=... ...`), then the `app_config` table.
// Keys saved from the Admin dashboard land in `app_config` and take effect
// immediately without a redeploy.
//
// Actions (body.action):
//   list                                  -> user's conversations, newest first
//   create                                -> new conversation { title?, provider? }
//   setProvider  { conversationId, provider }
//   delete       { conversationId }
//   history      { conversationId }       -> messages, oldest first
//   chat         { conversationId, content, task?, targetLanguage? }
//                                          -> sends, persists both messages,
//                                             returns { user, assistant }
//   translateText { text, targetLanguage? } -> stateless text translation
//   transcribe   { audioUrl, targetLanguage? }
//                                          -> transcribe (Whisper) + translate a
//                                             voice message, returns
//                                             { transcript, translation }
//
// `task` switches the system prompt so the same endpoint powers normal chat and
// the quick actions (write reply / rewrite / suggest replies / summarize /
// translate).

import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type ProviderName = "openai" | "anthropic" | "gemini";

const MODELS: Record<ProviderName, string> = {
  openai: "gpt-4o-mini",
  anthropic: "claude-3-5-haiku-latest",
  gemini: "gemini-2.0-flash",
};

const KEYS: Record<ProviderName, string | undefined> = {
  openai: Deno.env.get("OPENAI_API_KEY"),
  anthropic: Deno.env.get("ANTHROPIC_API_KEY"),
  gemini: Deno.env.get("GEMINI_API_KEY"),
};

// Row key in `app_config` for each provider. Matches the env var name so a
// secret set in the environment always wins without special-casing.
const MODEL_KEY_NAMES: Record<ProviderName, string> = {
  openai: "OPENAI_API_KEY",
  anthropic: "ANTHROPIC_API_KEY",
  gemini: "GEMINI_API_KEY",
};

// Resolves a provider's API key: environment secret first, then the value an
// admin saved from the app (read with the service role, so RLS never applies).
async function loadProviderKey(
  provider: ProviderName,
  admin: ReturnType<typeof createClient>,
): Promise<string | undefined> {
  const envKey = KEYS[provider];
  if (envKey) return envKey;
  const { data, error } = await admin
    .from("app_config")
    .select("value")
    .eq("key", MODEL_KEY_NAMES[provider])
    .single();
  if (error || !data) return undefined;
  return data.value;
}

interface ChatTurn {
  role: string;
  content: string;
}

const DEFAULT_SYSTEM =
  "You are LoText AI, a friendly assistant inside the LoText messaging app. " +
  "Be helpful, clear and safe. Keep answers concise unless the user asks for " +
  "detail. Never claim to be a human.";

function systemPromptFor(
  task: string | undefined,
  targetLanguage: string | undefined
): string {
  switch (task) {
    case "reply":
      return (
        "You are helping a LoText user reply to a message. The user pasted the " +
        "message they received; write a natural, helpful reply on their behalf. " +
        "Keep it under 200 words."
      );
    case "rewrite":
      return (
        "Rewrite the user's message so it is clearer and more polished while " +
        "keeping exactly the same meaning and tone. Return only the rewritten " +
        "message."
      );
    case "suggest":
      return (
        "Suggest several short, natural reply options for the message the user " +
        "pasted. Return a short numbered list of 3-5 options."
      );
    case "summarize":
      return (
        "Summarize the user's text concisely. Return a short paragraph or a " +
        "few bullet points."
      );
    case "translate":
      return (
        "Translate the user's text into " + (targetLanguage ?? "English") +
        ". Return only the translation."
      );
    default:
      return DEFAULT_SYSTEM;
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

async function callOpenAI(
  apiKey: string,
  system: string,
  turns: ChatTurn[],
): Promise<string> {
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: MODELS.openai,
      max_tokens: 1500,
      messages: [
        { role: "system", content: system },
        ...turns.map((t) => ({ role: t.role, content: t.content })),
      ],
    }),
  });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(data?.error?.message ?? "OpenAI request failed");
  }
  return data?.choices?.[0]?.message?.content ?? "";
}

async function callAnthropic(
  apiKey: string,
  system: string,
  turns: ChatTurn[],
): Promise<string> {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: MODELS.anthropic,
      max_tokens: 1500,
      system,
      messages: turns
        .filter((t) => t.role !== "system")
        .map((t) => ({
          role: t.role === "assistant" ? "assistant" : "user",
          content: t.content,
        })),
    }),
  });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(data?.error?.message ?? "Anthropic request failed");
  }
  const parts = data?.content;
  if (Array.isArray(parts)) {
    return parts
      .map((p) => (typeof p?.text === "string" ? p.text : ""))
      .join("");
  }
  return "";
}

async function callGemini(
  apiKey: string,
  system: string,
  turns: ChatTurn[],
): Promise<string> {
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${MODELS.gemini}:generateContent`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": apiKey,
      },
      body: JSON.stringify({
        system_instruction: { parts: [{ text: system }] },
        contents: turns
          .filter((t) => t.role !== "system")
          .map((t) => ({
            role: t.role === "assistant" ? "model" : "user",
            parts: [{ text: t.content }],
          })),
        generationConfig: { maxOutputTokens: 1500 },
      }),
    },
  );
  const data = await res.json();
  if (!res.ok) {
    throw new Error(data?.error?.message ?? "Gemini request failed");
  }
  const parts = data?.candidates?.[0]?.content?.parts;
  if (Array.isArray(parts)) {
    return parts
      .map((p) => (typeof p?.text === "string" ? p.text : ""))
      .join("");
  }
  return "";
}

async function generateReply(
  provider: ProviderName,
  system: string,
  turns: ChatTurn[],
  admin: ReturnType<typeof createClient>,
): Promise<string> {
  const apiKey = await loadProviderKey(provider, admin);
  if (!apiKey) {
    throw new Error(
      `The ${provider} provider is not configured yet. Set its key in the Admin dashboard.`,
    );
  }
  switch (provider) {
    case "openai":
      return callOpenAI(apiKey, system, turns);
    case "anthropic":
      return callAnthropic(apiKey, system, turns);
    case "gemini":
      return callGemini(apiKey, system, turns);
  }
}

// ---------------------------------------------------------------------------
// Request handling
// ---------------------------------------------------------------------------

function replyToAdmin(admin: ReturnType<typeof createClient>) {
  return {
    async getConversation(id: string, ownerUid: string) {
      const { data, error } = await admin
        .from("ai_conversations")
        .select("id, title, provider")
        .eq("id", id)
        .eq("owner_uid", ownerUid)
        .single();
      if (error || !data) throw new Error("Conversation not found");
      return data as { id: string; title: string; provider: ProviderName };
    },
    async insertMessage(conversationId: string, role: string, content: string) {
      const { data, error } = await admin
        .from("ai_messages")
        .insert({ conversation_id: conversationId, role, content })
        .select("id, role, content, created_at")
        .single();
      if (error || !data) throw new Error("Could not save the message");
      return data;
    },
    async history(conversationId: string): Promise<ChatTurn[]> {
      const { data, error } = await admin
        .from("ai_messages")
        .select("role, content")
        .eq("conversation_id", conversationId)
        .order("created_at", { ascending: true });
      if (error) throw new Error("Could not load the conversation");
      return (data ?? []).map((m) => ({
        role: m.role === "assistant" ? "assistant" : "user",
        content: m.content,
      }));
    },
    async setTitle(conversationId: string, title: string) {
      await admin
        .from("ai_conversations")
        .update({ title, updated_at: new Date().toISOString() })
        .eq("id", conversationId);
    },
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json({ error: "Function is not configured." }, 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) {
    return json({ error: "Unauthorized" }, 401);
  }

  const client = createClient(supabaseUrl, anonKey);
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
  const db = replyToAdmin(admin);

  try {
    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      return json({ error: "Invalid request body" }, 400);
    }

    const action = String(body.action ?? "chat");

    switch (action) {
      case "list": {
        const { data, error } = await admin
          .from("ai_conversations")
          .select("id, title, provider, created_at, updated_at")
          .eq("owner_uid", user.id)
          .order("updated_at", { ascending: false });
        if (error) throw new Error("Could not load your AI chats");
        return json({ conversations: data ?? [] });
      }

      case "create": {
        const provider = (String(body.provider ?? "openai") as ProviderName) in
          MODELS
          ? (String(body.provider) as ProviderName)
          : "openai";
        const title = String(body.title ?? "New chat").slice(0, 60);
        const { data, error } = await admin
          .from("ai_conversations")
          .insert({ owner_uid: user.id, title, provider })
          .select("id, title, provider, created_at, updated_at")
          .single();
        if (error || !data) throw new Error("Could not create the chat");
        return json({ conversation: data });
      }

      case "setProvider": {
        const conversationId = String(body.conversationId ?? "");
        const provider = (String(body.provider ?? "") as ProviderName) in MODELS
          ? (String(body.provider) as ProviderName)
          : "openai";
        await db.getConversation(conversationId, user.id);
        const { data, error } = await admin
          .from("ai_conversations")
          .update({ provider, updated_at: new Date().toISOString() })
          .eq("id", conversationId)
          .select("id, title, provider, created_at, updated_at")
          .single();
        if (error || !data) throw new Error("Could not update the provider");
        return json({ conversation: data });
      }

      case "delete": {
        const conversationId = String(body.conversationId ?? "");
        await db.getConversation(conversationId, user.id);
        const { error } = await admin
          .from("ai_conversations")
          .delete()
          .eq("id", conversationId);
        if (error) throw new Error("Could not delete the chat");
        return json({ ok: true });
      }

      case "history": {
        const conversationId = String(body.conversationId ?? "");
        await db.getConversation(conversationId, user.id);
        const { data, error } = await admin
          .from("ai_messages")
          .select("id, role, content, created_at")
          .eq("conversation_id", conversationId)
          .order("created_at", { ascending: true });
        if (error) throw new Error("Could not load the conversation");
        return json({ messages: data ?? [] });
      }

      case "chat": {
        const conversationId = String(body.conversationId ?? "");
        const content = String(body.content ?? "").trim();
        if (content === "") return json({ error: "Message is empty" }, 400);
        const task = body.task === undefined ? undefined : String(body.task);
        const targetLanguage = body.targetLanguage === undefined
          ? undefined
          : String(body.targetLanguage);

        const conversation = await db.getConversation(conversationId, user.id);
        const provider: ProviderName = conversation.provider in MODELS
          ? (conversation.provider as ProviderName)
          : "openai";

        const userMessage = await db.insertMessage(
          conversationId,
          "user",
          content,
        );

        const turns = await db.history(conversationId);
        const system = systemPromptFor(task, targetLanguage);
        const reply = await generateReply(provider, system, turns, admin);

        const assistantMessage = await db.insertMessage(
          conversationId,
          "assistant",
          reply,
        );

        if (conversation.title === "New chat") {
          const title = content.length > 40 ? `${content.slice(0, 40)}\u2026` : content;
          await db.setTitle(conversationId, title);
        }

        return json({ user: userMessage, assistant: assistantMessage });
      }

      case "translateText": {
        // Stateless text translation for the chat screen (no AI conversation
        // rows are created). The model returns JSON so the client also learns
        // the source language (shown as "Translated from X").
        const text = String(body.text ?? "").trim();
        if (text === "") return json({ error: "Text is empty" }, 400);
        const targetLanguage = body.targetLanguage === undefined
          ? "English"
          : String(body.targetLanguage);
        const system =
          "Translate the user's text into " + targetLanguage + ". " +
          'Respond with ONLY a JSON object with two fields: ' +
          '"sourceLanguage" (the English name of the language the text was ' +
          'originally written in, e.g. "French") and "translation" (the text ' +
          'translated into ' + targetLanguage + '). Return only the JSON.';
        const reply = await generateReply(
          "openai",
          system,
          [{ role: "user", content: text }],
          admin,
        );
        let sourceLanguage = "";
        let translation = "";
        try {
          const parsed = JSON.parse(reply.trim());
          sourceLanguage = String(parsed?.sourceLanguage ?? "").trim();
          translation = String(parsed?.translation ?? "").trim();
        } catch {
          // The model ignored the JSON instruction: treat the raw reply as
          // the translation and leave the source language unknown.
          translation = reply.trim();
        }
        if (translation === "") {
          return json({ error: "Could not translate the message" }, 400);
        }
        return json({ translation, sourceLanguage, targetLanguage });
      }

      case "transcribe": {
        // Translates a voice message: transcribe it (Whisper), then translate
        // the transcript. Returns both so the UI can show the original words
        // and the translation.
        const audioUrl = String(body.audioUrl ?? "").trim();
        if (audioUrl === "") return json({ error: "No audio to transcribe" }, 400);
        const targetLanguage = body.targetLanguage === undefined
          ? "English"
          : String(body.targetLanguage);

        const audioRes = await fetch(audioUrl, {
          headers: { Authorization: `Bearer ${serviceKey}` },
        });
        if (!audioRes.ok) {
          return json({ error: "Could not download the voice message" }, 400);
        }
        const audioBuf = await audioRes.arrayBuffer();

        const openaiKey = await loadProviderKey("openai", admin);
        if (!openaiKey) {
          return json({
            error:
              "The OpenAI provider is not configured yet. Set its key in the Admin dashboard.",
          }, 400);
        }

        const form = new FormData();
        form.append(
          "file",
          new Blob([audioBuf], { type: "audio/mp4" }),
          "voice.m4a",
        );
        form.append("model", "whisper-1");
        form.append("response_format", "json");

        const whisperRes = await fetch(
          "https://api.openai.com/v1/audio/transcriptions",
          {
            method: "POST",
            headers: { Authorization: `Bearer ${openaiKey}` },
            body: form,
          },
        );
        const whisperData = await whisperRes.json();
        if (!whisperRes.ok) {
          throw new Error(
            whisperData?.error?.message ?? "Could not transcribe the voice message",
          );
        }
        const transcript = String(whisperData?.text ?? "").trim();
        if (transcript === "") {
          return json(
            { error: "No speech was detected in the voice message" },
            400,
          );
        }

        const system = systemPromptFor("translate", targetLanguage);
        const translation = await generateReply(
          "openai",
          system,
          [{ role: "user", content: transcript }],
          admin,
        );

        return json({
          transcript,
          translation: translation.trim(),
          targetLanguage,
        });
      }

      default:
        return json({ error: `Unknown action: ${action}` }, 400);
    }
  } catch (e) {
    const message = e instanceof Error ? e.message : "Unexpected error";
    return json({ error: message }, 400);
  }
});
