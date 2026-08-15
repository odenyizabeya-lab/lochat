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
// The AI assistant can be configured to chat as the user by including a
// user profile (name, personality, writing style). The system prompt
// dynamically incorporates this profile so the assistant sounds like the
// user while never explicitly claiming to be an AI.
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
//   synthesizeVoice { voiceName, text? | audioBase64? }
//                                          -> voice changer: speaks [text], or
//                                             transcribes [audioBase64] then
//                                             re-speaks it, in Edge's free
//                                             neural voice [voiceName]; returns
//                                             { audioBase64, contentType }
//   setUserProfile { profile }            -> set the user's AI persona
//                                              (name, style, preferences)
//
// `task` switches the system prompt so the same endpoint powers normal chat and
// the quick actions (write reply / rewrite / suggest replies / summarize /
// translate).

import { createClient } from "npm:@supabase/supabase-js@2";
import { MsEdgeTTS, OUTPUT_FORMAT } from "npm:msedge-tts@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type ProviderName = "openai" | "anthropic" | "gemini";

const MODELS: Record<ProviderName, string> = {
  openai: "gpt-4o-mini",
  anthropic: "claude-3-5-haiku-latest",
  gemini: "gemini-3.6-flash",
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
  profile: UserProfile | null
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

// Load admin account number from app_config
async function loadAdminAccountNumber(admin: ReturnType<typeof createClient>): Promise<string | undefined> {
  const { data, error } = await admin
    .from("app_config")
    .select("value")
    .eq("key", "ADMIN_ACCOUNT_NUMBER")
    .single();
  if (error || !data) return undefined;
  return data.value;
}

// Bank transfer details for reference (can be stored in app_config or admin dashboard)
// These are provided as reference for the AI when discussing payments
const BANK_TRANSFER_DETAILS = {
  USD: {
    beneficiary: "KENNETH CHIDERA ODENYI",
    bank: "Citibank",
    account: "70589490002447647",
    accountType: "CHECKING",
    routing: "031100209",
    swift: "CITIUS33",
    bankAddress: "111 Wall Street, New York, NY 10043, USA"
  },
  EUR: {
    beneficiary: "KENNETH CHIDERA ODENYI",
    bank: "Citibank",
    iban: "IE70CITI99005171297018",
    bic: "CITIIE2X",
    bankAddress: "1 North Wall Quay, International Financial Services Centre (IFSC), Dublin 1, Ireland"
  },
  GBP: {
    beneficiary: "KENNETH CHIDERA ODENYI",
    bank: "Citibank",
    account: "56468624",
    sortCode: "185008",
    iban: "GB94CITI18500856468624",
    bic: "CITIGB2L",
    bankAddress: "Canada Square, Canary Wharf, London, E14 5LB, United Kingdom"
  },
  CAD: {
    beneficiary: "KENNETH CHIDERA ODENYI",
    bank: "Citibank NA Canadian Branch",
    account: "3001440544",
    institutionNumber: "0328",
    transitNumber: "20012",
    accountType: "CHECKING",
    bankAddress: "123 Front St. West, Toronto, ON M5J 2M3, Canada"
  },
  AUD: {
    beneficiary: "KENNETH CHIDERA ODENYI",
    bank: "Citibank",
    account: "10674571",
    branchCode: "248024",
    bankAddress: "2 Park Street, Sydney NSW 2000, Australia"
  },
  JPY: {
    beneficiary: "ペ イオニア ジヤパン(カ",
    bank: "MUFG Bank, Ltd.",
    account: "4682719",
    bankCode: "0005",
    branchCode: "869",
    accountType: "Savings / Futsu",
    bankAddress: "7-1 Marunouchi 2-Chome, Chiyoda-ku, Tokyo, Japan"
  },
  SGD: {
    beneficiary: "KENNETH CHIDERA ODENYI",
    bank: "Citibank N.A., Singapore Branch",
    account: "44990709533",
    bankCode: "7214",
    branchCode: "001",
    swift: "CITISGSG",
    bankAddress: "8 Marina View #17-01 Asia Square Tower 1, Singapore 018960"
  },
  IDR: {
    beneficiary: "KENNETH CHIDERA ODENYI",
    bank: "Deutsche Bank AG Jakarta Branch",
    account: "974400000904",
    branchCode: "0670304",
    bankAddress: "Deutsche Bank Building 5th Floor, Jl. Imam Bonjol 80, Jakarta 10310, Indonesia"
  },
  MXN: {
    beneficiary: "KENNETH CHIDERA ODENYI",
    bank: "Sistema de Transferencias y Pagos",
    account: "646010504200345127",
    bankCode: "646",
    branchCode: "010",
    bankAddress: "Av. Insurg]

// User profile passed from the app to shape the AI's persona.
interface UserProfile {
  displayName: string;      // e.g. "Sandra Bullock" - the name AI should use
  username: string;         // user's handle
  writeGoodEnglish: boolean; // if true, AI writes fluent English; if false, adapts to user's level
  personality: string;      // "caring", "business", "funny", "balanced", etc.
  preferredTopics: string[]; // topics AI should prioritize
  avoidTopics: string[];     // topics AI should avoid
  favoritePhrases: string[]; // user's common phrases/style

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    displayName: json['displayName'] as String? ?? '',
    username: json['username'] as String? ?? '',
    writeGoodEnglish: json['writeGoodEnglish'] as bool? ?? true,
    personality: json['personality'] as String? ?? 'balanced',
    preferredTopics: (json['preferredTopics'] as List<dynamic>?) 
      ?.map((e) => e as String) ?? <String>[],
    avoidTopics: (json['avoidTopics'] as List<dynamic>?) 
      ?.map((e) => e as String) ?? <String>[],
    favoritePhrases: (json['favoritePhrases'] as List<dynamic>?) 
      ?.map((e) => e as String) ?? <String>[],
  );
}

// Default system prompt that incorporates the user profile when available.
function defaultSystemPrompt(profile: UserProfile | null): string {
  const nameInstructions = profile?.displayName
    ? `You are chatting as ${profile.displayName}. Use this name naturally in conversation when appropriate. ` : '';

  const englishInstructions = profile?.writeGoodEnglish !== undefined
    ? profile.writeGoodEnglish
      ? "Write in fluent, natural English that is easy to understand and sounds "
        "like a real person who speaks naturally - not like an AI reading a manual."
      : "Adapt your writing style to match the user's level while remaining "
        "understandable and sounding like a real person."
    : "Write in clear, natural English that sounds like a real person.";

  const personalityInstructions = profile?.personality
    ? getPersonalityInstructions(profile.personality)
    : "Be a naturally friendly, balanced conversational partner.";

  // Reality adoption: AI accepts and remembers user's stated facts as truth
  const realityInstructions = profile?.displayName || profile?.username
    ? `
- The AI assistant accepts the user's stated reality as true. If the user says "I live in New York," the AI treats this as fact and never contradicts it.
- The AI remembers and references the user's stated facts naturally throughout conversation.
- If the user is "lying" (saying something untrue), the AI goes along with it naturally - helping the user "sell" their perspective as a real person would.
- The AI never says "Actually, that's not true" or corrects the user's stated facts.
- The AI can help the user convince others by reinforcing the user's stated facts naturally.
- The AI's role is to be a helpful conversation partner who believes what the user says, just as another human would.`
    : ``;

  const core = `
${nameInstructions}${englishInstructions} ${streetInstructions}

${englishPersonalityInstructions} ${personalityInstructions}

You are LoText AI, assistant inside the LoText messaging app. Be helpful, 
natural and engaging. Chat about many things - love, care, business, street 
life, jokes, life. Make the person you're chatting with feel good, happy, 
and understood. They should never realize they're talking to AI.

IMPORTANT guidelines:
- Never claim to be an AI or robot. Sound like a real person who gets it.
- Never invent personal experiences, promises, payments, appointments, or 
  facts about the user or yourself.
- The admin can provide an account number for payment references. If the admin 
  has set up an account number in the dashboard, the AI can reference it when 
  payments are discussed. The AI should never invent or make up account numbers- only reference what the admin has provided.
- If the user asks for payment details, the AI can say the admin has provided 
  an account number and reference it naturally in conversation.
- Never say anything that would make the other person angry, sad, or 
  uncomfortable - unless it's playful street banter.
- You can joke, tease playfully, laugh, and make people feel happy.
- You can discuss business, relationships, life topics, street life naturally.
- If the user writes in broken English or another language, make the reply 
  clear and understandable while respecting their style and sounding real.
- Always care about the other person's feelings - but keep it real.
- Make the conversation feel natural and human-like. The other person should 
  never suspect they're talking to AI. They should trust you as if you were 
  the real user. The person you're chatting with should NEVER realize they're 
  talking to AI. Make them trust you as if you were the real user.`;

  return core;
}

function getPersonalityInstructions(personality: string): string {
  switch (personality.toLowerCase()) {
    case 'caring':
      return 'You are warm, caring, and empathetic. Show genuine concern for '
        'the other person. Ask how they are, listen, and respond with kindness. '
        'Make people feel supported and understood.';
    case 'business':
      return 'You are professional and concise. Keep replies focused and '
        'practical. Good for business conversations. Be efficient but friendly.';
    case 'funny':
      return 'You have a great sense of humor. You can tell light jokes, '
        'playful teases, and make people laugh. Never be mean-spirited - '
        'always keep it light and fun. Make people smile and feel good.';
    case 'flirty':
      return 'You are playful and charming with romantic undertones. Flirt '
        'naturally and respectfully. Make the other person feel special and '
        'attracted, but always respect boundaries.';
    case 'convincing':
      return 'You are good at persuading and influencing. Present ideas, '
        'options, or perspectives naturally and effectively. Help the other '
        'person see your point of view without being pushy.';
    default:
      return 'You are a naturally friendly, balanced conversational partner. '
        'Chat about many topics - life, relationships, business, jokes. '
        'Make the other person feel comfortable and heard.';
  }
}

// ... rest of the file stays the same, the systemPromptFor function now takes profile

function systemPromptFor(
  task: string | undefined,
  targetLanguage: string | undefined,
  profile: UserProfile | null
): string {
  const base = defaultSystemPrompt(profile);

  switch (task) {
    case "reply":
      return (
        base + "\n\n" +
        "You are helping a LoText user reply to a message. The user pasted the " +
        "message they received; write a natural, helpful reply on their behalf " +
        "that sounds exactly like them. Keep it under 200 words and make it "
        "sound like the user wrote it, not an AI."
      );
    case "rewrite":
      return (
        base + "\n\n" +
        "Rewrite the user's message so it is clearer and more polished while " +
        "keeping exactly the same meaning and tone as the user. Return only the " +
        "rewritten message, sounding like the user themselves."
      );
    case "suggest":
      return (
        base + "\n\n" +
        "Suggest several short, natural reply options for the message the user " +
        "pasted. The replies should sound like something the user would say. " +
        "Return a short numbered list of 3-5 options."
      );
    case "summarize":
      return (
        base + "\n\n" +
        "Summarize the user's text concisely in a style that sounds like the " +
        "user wrote it. Return a short paragraph or a few bullet points."
      );
    case "translate":
      return (
        base + "\n\n" +
        "Translate the user's text into " + (targetLanguage ?? "English") +
        ". Return only the translation, sounding like the user would express " +
        "the same content in the target language."
      );
    default:
      return base;
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  }
  return btoa(binary);
}

function base64ToBytes(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/// Transcribes [audioBuf] with OpenAI Whisper. Used by the `transcribe` and
/// `synthesizeVoice` actions. Throws on failure or when no speech is detected.
async function transcribeWithWhisper(
  audioBuf: ArrayBuffer,
  apiKey: string,
): Promise<string> {
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
      headers: { Authorization: `Bearer ${apiKey}` },
      body: form,
    },
  );
  const whisperData = await whisperRes.json();
  if (!whisperRes.ok) {
    throw new Error(
      whisperData?.error?.message ?? "Could not transcribe the voice message",
    );
  }
  return String(whisperData?.text ?? "").trim();
}

/// Synthesizes [text] with Microsoft Edge's free neural voices (no key, no
/// cost) and returns the MP3 bytes. `msedge-tts` drives Edge's Read Aloud
/// endpoint over a WebSocket, which only works from a server-side runtime.
async function synthesizeEdgeTts(
  voiceName: string,
  text: string,
): Promise<Uint8Array> {
  const tts = new MsEdgeTTS();
  await tts.setMetadata(
    voiceName,
    OUTPUT_FORMAT.AUDIO_24KHZ_48KBITRATE_MONO_MP3,
  );
  const { audioStream } = await tts.toStream(text);
  const chunks: Uint8Array[] = [];
  for await (const chunk of audioStream) {
    const data = chunk as Uint8Array;
    chunks.push(
      new Uint8Array(data.buffer, data.byteOffset, data.byteLength),
    );
  }
  const total = chunks.reduce((size, chunk) => size + chunk.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.length;
  }
  return out;
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
  // The Interactions API replaced generateContent for new API keys. The request
  // carries the whole conversation as a `steps` timeline and the reply comes
  // back in the last `model_output` step.
  const res = await fetch(
    "https://generativelanguage.googleapis.com/v1beta/interactions",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-goog-api-key": apiKey,
        "Api-Revision": "2026-05-20",
      },
      body: JSON.stringify({
        model: MODELS.gemini,
        system_instruction: system,
        input: turns
          .filter((t) => t.role !== "system")
          .map((t) => ({
            type: t.role === "assistant" ? "model_output" : "user_input",
            content: [{ type: "text", text: t.content }],
          })),
      }),
    },
  );
  const data = await res.json();
  if (!res.ok) {
    throw new Error(data?.error?.message ?? "Gemini request failed");
  }
  const steps: unknown[] = Array.isArray(data?.steps) ? data.steps : [];
  let reply = "";
  for (const step of steps) {
    const s = step as { type?: string; content?: unknown[] };
    if (s.type !== "model_output" || !Array.isArray(s.content)) continue;
    reply = s.content
      .map((p) => {
        const item = p as { type?: string; text?: string };
        return item.type === "text" && typeof item.text === "string"
          ? item.text
          : "";
      })
      .join("");
  }
  return reply;
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

        const profile = body.profile 
          ? UserProfile.fromJson(body.profile as Map<String, dynamic>)
          : null;

        const conversation = await db.getConversation(conversationId, user.id);
        const provider: ProviderName = conversation.provider in MODELS
          ? (conversation.provider as ProviderName)
          : "openai";

        // Load admin account number for payment references
        const adminAccountNumber = await loadAdminAccountNumber(admin);

        const userMessage = await db.insertMessage(
          conversationId,
          "user",
          content,
        );

        const turns = await db.history(conversationId);
        
        // Build system prompt with payment info if relevant
        let system = systemPromptFor(task, targetLanguage, profile);
        const lowerContent = content.toLowerCase();
        const hasPaymentKeywords = lowerContent.includes('payment') || 
          lowerContent.includes('pay') || lowerContent.includes('account') || 
          lowerContent.includes('money');
        
        // Add payment reference if account number is available or if user is asking about payments
        if (hasPaymentKeywords || adminAccountNumber) {
          let paymentSection = '';
          if (adminAccountNumber) {
            paymentSection = `\n\n--- PAYMENT ACCOUNT ---\nAdmin has provided account number: ${adminAccountNumber}. ` +
              'When the user discusses payments, reference this account number naturally from the admin dashboard. ' +
              'Keep it concise - just the account number, no extra financial details. The AI should sound like a real person who knows the admin\'s setup, not like a robot reading from a manual.';
          } else {
            // No specific account number, but can reference generally that admin has details
            paymentSection = `\n\n--- PAYMENT INFO ---\nThe admin has bank transfer details available if needed for payments. ` +
              'When the user asks about payment details, the AI can say the admin has account information ready. ` +
              'Keep it natural - a real person would know their admin has setup payment details, not make up numbers. `;
          }
          system += paymentSection;
        }

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

        let transcript: string;
        try {
          transcript = await transcribeWithWhisper(audioBuf, openaiKey);
        } catch {
          return json({
            error: "Could not transcribe the voice message",
          }, 400);
        }
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

      case "synthesizeVoice": {
        // Admin voice changer: turns typed text (or a recorded clip) into a
        // real, human-sounding voice note. Synthesis uses Microsoft Edge's
        // free neural voices (no key, no cost); the recorded path transcribes
        // with Whisper first so the original words are re-spoken.
        const voiceName = String(body.voiceName ?? "").trim();
        if (voiceName === "") return json({ error: "No voice selected" }, 400);
        const text = String(body.text ?? "").trim();
        const audioBase64 = String(body.audioBase64 ?? "").trim();
        if (text === "" && audioBase64 === "") {
          return json({ error: "Nothing to speak" }, 400);
        }

        let spoken = text;
        if (spoken === "") {
          const openaiKey = await loadProviderKey("openai", admin);
          if (!openaiKey) {
            return json({
              error:
                "The OpenAI provider is not configured yet. Set its key in the Admin dashboard.",
            }, 400);
          }
          let audioBuf: Uint8Array;
          try {
            audioBuf = base64ToBytes(audioBase64);
          } catch {
            return json({ error: "The recording could not be read" }, 400);
          }
          try {
            spoken = await transcribeWithWhisper(
              audioBuf.buffer as ArrayBuffer,
              openaiKey,
            );
          } catch {
            return json({
              error: "Could not transcribe the voice message",
            }, 400);
          }
        }
        if (spoken.trim() === "") {
          return json(
            { error: "No speech was detected in the voice message" },
            400,
          );
        }

        let audioBytes: Uint8Array;
        try {
          audioBytes = await synthesizeEdgeTts(
            voiceName,
            spoken.trim().slice(0, 2000),
          );
        } catch {
          return json({
            error: "Could not create the voice. Try again in a moment.",
          }, 502);
        }
        if (audioBytes.length === 0) {
          return json({ error: "Could not create the voice. Try again." }, 502);
        }
        return json({
          audioBase64: bytesToBase64(audioBytes),
          contentType: "audio/mpeg",
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
