// Supabase Edge Function: send-plan-sale-push
//
// Delivers subscription plan-sale notifications to every registered device
// via Firebase Cloud Messaging (FCM HTTP v1) — this is what reaches users'
// phones even when the AniMart app is closed.
//
// HOW IT'S TRIGGERED
//   The announce_plan_sale() DB trigger (see migration
//   20260705010000_plan_sale_announcements.sql) queues a row in
//   public.plan_sale_pushes whenever an admin puts a plan on sale. Point a
//   Database Webhook (Dashboard → Database → Webhooks) at this function for
//   INSERTs on plan_sale_pushes, or invoke it on a schedule — either way it
//   simply drains all unsent queue rows, so duplicate invocations are safe.
//
// SECURITY: takes no meaningful input. The payload (title/body) is always
// read from the plan_sale_pushes queue — which only the DB trigger can write
// — so a caller can never push arbitrary content.
//
// Required secrets:
//   FIREBASE_SERVICE_ACCOUNT — the full JSON of a Firebase service account
//     key (Project settings → Service accounts → Generate new private key).
// (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected automatically.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ── FCM HTTP v1 auth: mint an OAuth2 access token from the service account ──

function base64UrlEncode(data: Uint8Array | string): string {
  const bytes =
    typeof data === "string" ? new TextEncoder().encode(data) : data;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const raw = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const der = Uint8Array.from(atob(raw), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

async function fetchAccessToken(
  sa: { client_email: string; private_key: string; token_uri: string },
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64UrlEncode(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: sa.token_uri,
    iat: now,
    exp: now + 3600,
  }));
  const key = await importPrivateKey(sa.private_key);
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${claims}`),
  );
  const jwt = `${header}.${claims}.${base64UrlEncode(new Uint8Array(signature))}`;

  const res = await fetch(sa.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) {
    throw new Error(`OAuth token request failed: ${await res.text()}`);
  }
  const data = await res.json();
  return data.access_token as string;
}

// ── Handler ──────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  if (!serviceAccountJson) {
    return json({ error: "FIREBASE_SERVICE_ACCOUNT secret is not set" }, 500);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);

  // Everything queued and not yet sent — never trust the request body.
  const { data: pending, error: queueError } = await admin
    .from("plan_sale_pushes")
    .select("id, title, body")
    .eq("sent", false)
    .order("created_at", { ascending: true });
  if (queueError) return json({ error: queueError.message }, 500);
  if (!pending || pending.length === 0) {
    return json({ result: "nothing to send" });
  }

  const { data: tokenRows, error: tokenError } = await admin
    .from("device_push_tokens")
    .select("token");
  if (tokenError) return json({ error: tokenError.message }, 500);
  const tokens = (tokenRows ?? []).map((r) => r.token as string);

  let sent = 0;
  const deadTokens = new Set<string>();

  if (tokens.length > 0) {
    const sa = JSON.parse(serviceAccountJson);
    const accessToken = await fetchAccessToken(sa);
    const endpoint =
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    for (const push of pending) {
      for (const token of tokens) {
        if (deadTokens.has(token)) continue;
        const res = await fetch(endpoint, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token,
              notification: { title: push.title, body: push.body },
              // No channel_id: the FCM Android SDK falls back to the channel
              // it creates itself, so notifications display without the app
              // having to pre-create one.
              android: { priority: "HIGH" },
              apns: {
                payload: { aps: { sound: "default" } },
              },
            },
          }),
        });
        if (res.ok) {
          sent++;
        } else {
          const text = await res.text();
          // Token no longer valid (app uninstalled / token rotated).
          if (text.includes("UNREGISTERED") || text.includes("NOT_FOUND")) {
            deadTokens.add(token);
          } else {
            console.error(`FCM send failed: ${res.status} ${text}`);
          }
        }
      }
    }
  }

  // Mark the queue drained even when there were no tokens, so old sales are
  // not re-broadcast to the first device that ever registers.
  await admin
    .from("plan_sale_pushes")
    .update({ sent: true })
    .in("id", pending.map((p) => p.id));

  if (deadTokens.size > 0) {
    await admin
      .from("device_push_tokens")
      .delete()
      .in("token", [...deadTokens]);
  }

  return json({
    result: "ok",
    pushes: pending.length,
    devices: tokens.length,
    delivered: sent,
    removedTokens: deadTokens.size,
  });
});
