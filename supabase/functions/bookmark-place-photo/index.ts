import { createClient } from "npm:@supabase/supabase-js@2";

const PHOTO_URL_LIFETIME_SECONDS = 25 * 60 * 60;

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return json({ error: "Method not allowed." }, 405);
    }

    const token = bearerToken(req.headers.get("Authorization"));
    if (!token) return json({ error: "Login is required." }, 401);

    const supabaseUrl = requiredEnv("SUPABASE_URL");
    const admin = createClient(
      supabaseUrl,
      requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    const { data: userData, error: userError } = await admin.auth.getUser(token);
    const user = userData.user;
    if (userError || !user) return json({ error: "Invalid session." }, 401);

    const body = await req.json() as Record<string, unknown>;
    const googlePlaceId = text(body.place_id);
    if (!googlePlaceId) return json({ error: "A valid place is required." }, 400);

    const { data: place, error: placeError } = await admin
      .from("places")
      .select("id")
      .eq("place_id", googlePlaceId)
      .maybeSingle();
    if (placeError) throw placeError;
    if (!place) return json({ error: "Place not found." }, 404);

    // Only the owner of a bookmark may request its place photo URL.
    const { data: bookmark, error: bookmarkError } = await admin
      .from("bookmarks")
      .select("id")
      .eq("user_id", user.id)
      .eq("place_id", place.id)
      .maybeSingle();
    if (bookmarkError) throw bookmarkError;
    if (!bookmark) return json({ error: "Bookmark not found." }, 403);

    // Google photo resource names can expire and must not be cached. Resolve
    // the current name from the stable Place ID whenever bookmarks load.
    const detailsResponse = await fetch(
      `https://places.googleapis.com/v1/places/${encodeURIComponent(googlePlaceId)}`,
      {
        headers: {
          "X-Goog-Api-Key": requiredEnv("GOOGLE_PLACES_API_KEY"),
          "X-Goog-FieldMask": "photos",
        },
      },
    );
    if (!detailsResponse.ok) {
      console.error("Google Place Details failed", detailsResponse.status);
      return json({ error: "Place photo is unavailable." }, 502);
    }
    const details = await detailsResponse.json() as {
      photos?: Array<{
        name?: string;
        googleMapsUri?: string;
        authorAttributions?: unknown[];
      }>;
    };
    const photo = details.photos?.[0];
    const resource = text(photo?.name);
    if (!isValidPhotoResource(resource)) {
      return json({ error: "This place has no available photo." }, 404);
    }

    const expires = Math.floor(Date.now() / 1000) + PHOTO_URL_LIFETIME_SECONDS;
    const signature = await hmacSha256(
      `${resource}|${expires}`,
      requiredEnv("PLACES_PHOTO_SIGNING_SECRET"),
    );
    const photoUrl = new URL(`${supabaseUrl}/functions/v1/place-photo`);
    photoUrl.searchParams.set("resource", resource);
    photoUrl.searchParams.set("expires", String(expires));
    photoUrl.searchParams.set("signature", signature);

    return json({
      image_url: photoUrl.toString(),
      google_maps_uri: text(photo?.googleMapsUri),
      author_attributions: photo?.authorAttributions ?? [],
    });
  } catch (error) {
    console.error(error);
    return json({ error: "Unable to load the bookmark photo." }, 500);
  }
});

function bearerToken(value: string | null): string | null {
  if (!value?.startsWith("Bearer ")) return null;
  return value.slice(7).trim() || null;
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function isValidPhotoResource(value: string): boolean {
  return /^places\/[A-Za-z0-9_-]+\/photos\/[A-Za-z0-9_-]+$/.test(value);
}

async function hmacSha256(value: string, secret: string): Promise<string> {
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(value));
  return bytesToBase64Url(new Uint8Array(signature));
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replace(/=+$/, "");
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Required environment variable ${name} is missing.`);
  return value;
}

function json(body: Record<string, unknown>, status = 200): Response {
  return Response.json(body, { status });
}
