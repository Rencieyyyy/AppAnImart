// Supabase Edge Function: listing-page
//
// Public share page for a listing — this is what the app's "Copy Link"
// copies (it used to be a fake farm.app URL that led nowhere). Renders a
// lightweight, self-contained HTML preview of the listing (title, photo,
// price, location, details) with OpenGraph tags so the link unfurls nicely
// in Messenger/social chats, plus a note to open the AniMart app.
//
// GET /functions/v1/listing-page?id=<listing id>
//
// verify_jwt is OFF (see supabase/config.toml): share links must work for
// people without the app or an account. Only fields already public in the
// app's browse feed are shown, and only for listings that aren't disabled.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

function esc(s: unknown): string {
  return String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function page(title: string, bodyHtml: string, meta = ""): Response {
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
${meta}
<style>
  :root { color-scheme: light; }
  * { box-sizing: border-box; margin: 0; }
  body { font-family: -apple-system, Segoe UI, Roboto, sans-serif;
         background: #f4faf7; color: #1a2e22; padding: 16px;
         display: flex; justify-content: center; }
  .card { background: #fff; border: 1px solid #e2efe9; border-radius: 18px;
          max-width: 480px; width: 100%; overflow: hidden; }
  .photo { width: 100%; aspect-ratio: 4 / 3; object-fit: cover;
           background: #d6f0e4; display: block; }
  .pad { padding: 20px; }
  .brand { display: flex; align-items: center; gap: 8px; padding: 14px 20px;
           border-bottom: 1px solid #eef4f1; font-weight: 800;
           color: #1d9e75; font-size: 15px; }
  h1 { font-size: 20px; margin-bottom: 4px; }
  .price { color: #1d9e75; font-weight: 800; font-size: 18px;
           margin-bottom: 10px; }
  .badge { display: inline-block; font-size: 11px; font-weight: 700;
           padding: 3px 10px; border-radius: 20px; background: #fff3e0;
           color: #e65100; margin-bottom: 10px; }
  .row { font-size: 13px; color: #3d5247; margin: 3px 0; }
  .label { color: #7c8b83; }
  .desc { font-size: 13.5px; color: #3d5247; line-height: 1.5;
          margin-top: 12px; white-space: pre-wrap; }
  .cta { margin-top: 18px; background: #6dbf99; color: #fff; border-radius: 14px;
         padding: 13px; text-align: center; font-weight: 700; font-size: 14px; }
  .foot { font-size: 11.5px; color: #7c8b83; text-align: center;
          padding: 12px 20px 18px; }
</style>
</head>
<body>
<div class="card">
  <div class="brand">🐓 AniMart</div>
  ${bodyHtml}
  <div class="foot">AniMart — the livestock &amp; poultry marketplace.<br>
  Browsing, offers and reservations happen in the AniMart app.</div>
</div>
</body>
</html>`;
  return new Response(html, {
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
}

Deno.serve(async (req) => {
  const id = new URL(req.url).searchParams.get("id")?.trim() ?? "";
  const unavailable = () =>
    page(
      "Listing unavailable — AniMart",
      `<div class="pad">
         <h1>This listing is unavailable</h1>
         <p class="desc">It may have been sold, removed, or the link is
         incorrect. Open the AniMart app to browse live listings.</p>
         <div class="cta">Open the AniMart app</div>
       </div>`,
    );

  if (!id) return unavailable();

  const admin = createClient(supabaseUrl, serviceRoleKey);
  const { data: l } = await admin
    .from("listings")
    .select(
      "id, title, price, image_url, category, location, description, " +
        "condition, breed, age, weight, status, seller_id",
    )
    .eq("id", id)
    .maybeSingle();

  if (!l || l.status === "disabled") return unavailable();

  let sellerName = "AniMart Seller";
  if (l.seller_id) {
    const { data: u } = await admin
      .from("users")
      .select("name")
      .eq("id", l.seller_id)
      .maybeSingle();
    if (u?.name?.trim()) sellerName = u.name.trim();
  }

  const title = (l.title ?? "").trim() || "AniMart Listing";
  const priceNum = Number(l.price);
  const price = Number.isFinite(priceNum)
    ? `₱${priceNum % 1 === 0 ? priceNum.toFixed(0) : priceNum.toFixed(2)}`
    : "";
  const img = (l.image_url ?? "").trim();
  const desc = (l.description ?? "").trim();
  const shortDesc = desc.length > 200 ? `${desc.slice(0, 199)}…` : desc;
  const badge = l.status === "sold"
    ? `<span class="badge">Sold</span>`
    : l.status === "reserved"
    ? `<span class="badge">Reserved</span>`
    : "";

  const rows = [
    ["Category", l.category],
    ["Breed", l.breed],
    ["Age", l.age],
    ["Weight", l.weight],
    ["Condition", l.condition],
    ["Location", l.location],
    ["Seller", sellerName],
  ]
    .filter(([, v]) => `${v ?? ""}`.trim() !== "")
    .map(([k, v]) =>
      `<div class="row"><span class="label">${esc(k)}:</span> ${esc(v)}</div>`
    )
    .join("");

  const meta = `
<meta property="og:title" content="${esc(`${title} — ${price} on AniMart`)}">
<meta property="og:description" content="${esc(shortDesc || "View this listing on AniMart.")}">
${img.startsWith("http") ? `<meta property="og:image" content="${esc(img)}">` : ""}
<meta property="og:type" content="product">`;

  return page(
    `${title} — AniMart`,
    `${
      img.startsWith("http")
        ? `<img class="photo" src="${esc(img)}" alt="${esc(title)}">`
        : ""
    }
     <div class="pad">
       ${badge}
       <h1>${esc(title)}</h1>
       ${price ? `<div class="price">${esc(price)}</div>` : ""}
       ${rows}
       ${shortDesc ? `<div class="desc">${esc(shortDesc)}</div>` : ""}
       <div class="cta">Open the AniMart app to message the seller
       or make an offer</div>
     </div>`,
    meta,
  );
});
