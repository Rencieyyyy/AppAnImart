# delete-cloudinary-image

Edge Function that deletes a listing's images from Cloudinary using the Admin
API. The Cloudinary **API secret stays here on the server** — it is never
shipped in the Flutter app.

Called by the app (`deleteListingImages` in `lib/cloudinary_function.dart`)
when a listing is deleted, so its photos don't linger as orphans.

## Security model

The caller only sends a `listing_id`. The function then:

1. Identifies the caller from their JWT.
2. Looks up the listing with the service role.
3. Verifies the caller is the listing's `seller_id` — otherwise returns 403.
4. Derives the image `public_id`s from the **database row**, never from client
   input — so a user can only ever delete images attached to their own listing.

## One-time setup

1. **Install the Supabase CLI** — https://supabase.com/docs/guides/cli
   (e.g. `npm i -g supabase`, `scoop install supabase`, or `winget install Supabase.CLI`).

2. **Link the project** (run from the repo root):

   ```bash
   supabase login
   supabase link --project-ref kzhlhrhhfupgvpzjllce
   ```

3. **Set the Cloudinary secrets** (find these in your Cloudinary dashboard →
   Settings → API Keys). They are stored server-side, not in the app:

   ```bash
   supabase secrets set \
     CLOUDINARY_CLOUD_NAME=dor6aqawk \
     CLOUDINARY_API_KEY=<your-api-key> \
     CLOUDINARY_API_SECRET=<your-api-secret>
   ```

4. **Deploy:**

   ```bash
   supabase functions deploy delete-cloudinary-image
   ```

5. **Apply the listings RLS policies** (`supabase/migrations/*_listings_rls.sql`).
   Either push migrations:

   ```bash
   supabase db push
   ```

   …or paste the SQL into the Supabase dashboard → SQL Editor and run it.
   Review your existing policies first.

## Request / response

```jsonc
// POST body
{ "listing_id": "<uuid>" }

// 200 response
{ "results": [ { "public_id": "Animart/abc123", "result": "ok" } ] }
```

`verify_jwt` is on (see `supabase/config.toml`), so only authenticated app
users can invoke it — and the ownership check above restricts *which* listing's
images each user can delete.
