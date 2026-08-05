// Supabase Edge Function: delete-avatar-image
//
// Deletes the CALLER'S current profile picture from Cloudinary. Used when a
// user replaces their avatar, so the old image doesn't linger as an orphan.
//
// SECURITY: takes no input. It identifies the caller from their JWT, reads
// *their own* `users.avatar_url` with the service role, and deletes only that
// asset — a user can never target someone else's image.
//
// Response: { "result": "ok" | "not found" | "skipped" }
//
// Required secrets:
//   CLOUDINARY_CLOUD_NAME, CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET
// (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / SUPABASE_ANON_KEY are injected.)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cloudName = Deno.env.get("CLOUDINARY_CLOUD_NAME") ?? "";
const apiKey = Deno.env.get("CLOUDINARY_API_KEY") ?? "";
const apiSecret = Deno.env.get("CLOUDINARY_API_SECRET") ?? "";
const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

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

async function sha1Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-1", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/// Extracts a Cloudinary public_id from a delivery URL, or null if not a
/// Cloudinary image URL. Tolerates a transformation segment and version.
function cloudinaryPublicId(url: string): string | null {
  if (!url.startsWith("http") || !url.includes("res.cloudinary.com")) {
    return null;
  }
  const i = url.indexOf("/upload/");
  if (i === -1) return null;

  let path = url.substring(i + "/upload/".length).split("?")[0].split("#")[0];
  let segments = path.split("/").filter((s) => s.length > 0);

  if (
    segments.length > 1 &&
    /^[a-z]+_/.test(segments[0]) &&
    !segments[0].includes(".")
  ) {
    segments = segments.slice(1); // drop transformation
  }
  if (segments.length > 0 && /^v\d+$/.test(segments[0])) {
    segments = segments.slice(1); // drop version
  }
  if (segments.length === 0) return null;

  const last = segments[segments.length - 1];
  const dot = last.lastIndexOf(".");
  segments[segments.length - 1] = dot > 0 ? last.substring(0, dot) : last;
  return segments.join("/");
}

async function destroy(publicId: string) {
  const timestamp = Math.floor(Date.now() / 1000);
  const toSign = `public_id=${publicId}&timestamp=${timestamp}`;
  const signature = await sha1Hex(toSign + apiSecret);

  const form = new FormData();
  form.append("public_id", publicId);
  form.append("timestamp", `${timestamp}`);
  form.append("api_key", apiKey);
  form.append("signature", signature);

  const res = await fetch(
    `https://api.cloudinary.com/v1_1/${cloudName}/image/destroy`,
    { method: "POST", body: form },
  );
  const body = await res.json().catch(() => ({}));
  return body.result ?? "error";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (!cloudName || !apiKey || !apiSecret) {
    return json({ error: "Cloudinary credentials are not configured." }, 500);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) return json({ error: "Missing Authorization header." }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ error: "Invalid or expired session." }, 401);

  // Read the caller's own current avatar URL with the service role.
  const admin = createClient(supabaseUrl, serviceRoleKey);
  const { data: row, error } = await admin
    .from("users")
    .select("avatar_url")
    .eq("id", user.id)
    .maybeSingle();
  if (error) return json({ error: error.message }, 500);

  const publicId = cloudinaryPublicId(row?.avatar_url ?? "");
  if (!publicId) return json({ result: "skipped" }); // not a Cloudinary image

  const result = await destroy(publicId);
  return json({ result });
});
