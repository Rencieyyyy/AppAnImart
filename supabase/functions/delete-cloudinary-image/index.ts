// Supabase Edge Function: delete-cloudinary-image
//
// Deletes the Cloudinary images belonging to a listing, using the Admin API.
// The Cloudinary API secret lives only here (as a Supabase secret) and never
// ships inside the Flutter app.
//
// SECURITY: the caller only supplies a `listing_id`. The function then:
//   1. Identifies the caller from their JWT.
//   2. Looks up the listing with the service role.
//   3. Verifies the caller is the listing's seller — otherwise 403.
//   4. Derives the image public_ids from the DB row (never from client input),
//      so a user can only delete images attached to their own listing.
//
// Request body:  { "listing_id": "<uuid>" }
// Response:      { "results": [{ "public_id": "...", "result": "ok" }, ...] }
//
// Required secrets (set with `supabase secrets set ...`):
//   CLOUDINARY_CLOUD_NAME
//   CLOUDINARY_API_KEY
//   CLOUDINARY_API_SECRET
// (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.)

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

/// Computes the SHA-1 hex digest Cloudinary requires for signed requests.
async function sha1Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-1", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/// Extracts a Cloudinary public_id from a delivery URL, or null if [url] is not
/// a Cloudinary image URL (e.g. a bundled asset path). Tolerates inline
/// transformation segments between `/upload/` and the version.
function cloudinaryPublicId(url: string): string | null {
  if (!url.startsWith("http") || !url.includes("res.cloudinary.com")) {
    return null;
  }
  const marker = "/upload/";
  const i = url.indexOf(marker);
  if (i === -1) return null;

  let path = url.substring(i + marker.length).split("?")[0].split("#")[0];
  let segments = path.split("/").filter((s) => s.length > 0);

  // Drop a leading transformation segment, if present. Cloudinary
  // transformations look like `w_300,c_fill,q_auto` — comma-separated
  // `key_value` tokens — and never contain a dot (unlike the public_id file).
  if (
    segments.length > 1 &&
    /^[a-z]+_/.test(segments[0]) &&
    !segments[0].includes(".")
  ) {
    segments = segments.slice(1);
  }
  // Drop a leading version segment (e.g. `v1700000000`).
  if (segments.length > 0 && /^v\d+$/.test(segments[0])) {
    segments = segments.slice(1);
  }
  if (segments.length === 0) return null;

  // Strip the file extension from the final segment.
  const last = segments[segments.length - 1];
  const dot = last.lastIndexOf(".");
  segments[segments.length - 1] = dot > 0 ? last.substring(0, dot) : last;

  return segments.join("/");
}

/// Calls Cloudinary's `destroy` endpoint for a single public_id.
async function destroy(publicId: string) {
  const timestamp = Math.floor(Date.now() / 1000);
  // Params (other than file/cloud_name/api_key/signature) sorted alphabetically.
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
  // Cloudinary returns { result: "ok" } on success, "not found" otherwise.
  return { public_id: publicId, result: body.result ?? "error" };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (!cloudName || !apiKey || !apiSecret) {
    return json({ error: "Cloudinary credentials are not configured." }, 500);
  }

  // ── Identify the caller from their JWT ──────────────────────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader) return json({ error: "Missing Authorization header." }, 401);

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ error: "Invalid or expired session." }, 401);

  // ── Parse input ─────────────────────────────────────────────────────
  let listingId: string | undefined;
  try {
    listingId = (await req.json())?.listing_id;
  } catch (_) {
    return json({ error: "Invalid JSON body." }, 400);
  }
  if (!listingId || typeof listingId !== "string") {
    return json({ error: "listing_id is required." }, 400);
  }

  // ── Verify ownership and read images using the service role ──────────
  const admin = createClient(supabaseUrl, serviceRoleKey);
  const { data: listing, error } = await admin
    .from("listings")
    .select("seller_id, image_url, image_urls")
    .eq("id", listingId)
    .maybeSingle();

  if (error) return json({ error: error.message }, 500);
  if (!listing) return json({ error: "Listing not found." }, 404);
  if (listing.seller_id !== user.id) {
    return json({ error: "You do not own this listing." }, 403);
  }

  // ── Derive public_ids from the DB row (not from client input) ───────
  const urls: string[] = [
    ...(typeof listing.image_url === "string" ? [listing.image_url] : []),
    ...(Array.isArray(listing.image_urls) ? listing.image_urls.map(String) : []),
  ];
  const publicIds = [
    ...new Set(urls.map(cloudinaryPublicId).filter((v): v is string => !!v)),
  ];
  if (publicIds.length === 0) return json({ results: [] });

  const results = await Promise.all(publicIds.map(destroy));
  return json({ results });
});
