const PLACES_TIMEOUT_MS = 10_000;
const PHOTO_URL_LIFETIME_SECONDS = 25 * 60 * 60;

type GooglePlace = {
  id?: string;
  displayName?: { text?: string };
  formattedAddress?: string;
  location?: { latitude?: number; longitude?: number };
  rating?: number;
  types?: string[];
  photos?: Array<{ name?: string; googleMapsUri?: string }>;
  googleMapsUri?: string;
};

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") {
      return json({ error: "Method not allowed." }, 405);
    }

    const body = await req.json() as Record<string, unknown>;
    const name = text(body.name);
    const latitude = finiteNumber(body.latitude);
    const longitude = finiteNumber(body.longitude);
    if (!name || latitude == null || longitude == null) {
      return json({ error: "A valid AR location is required." }, 400);
    }
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      return json({ error: "The AR location coordinates are invalid." }, 400);
    }

    const apiKey = requiredEnv("GOOGLE_PLACES_API_KEY");
    const googlePlaceIds = strings(body.google_place_ids).slice(0, 5);
    const searchNames = uniqueStrings([
      ...strings(body.search_names),
      name,
    ]).slice(0, 4);
    const maximumDistanceMeters = clamp(
      Math.max(finiteNumber(body.match_radius_meters) ?? 0, 1500),
      1500,
      5000,
    );

    let place: GooglePlace | null = null;
    for (const placeId of googlePlaceIds) {
      const candidate = await getPlace(placeId, apiKey);
      if (
        candidate &&
        placeDistanceMeters(candidate, latitude, longitude) <=
          maximumDistanceMeters
      ) {
        place = candidate;
        break;
      }
    }

    if (!place) {
      place = await searchForPlace({
        searchNames,
        address: text(body.address),
        latitude,
        longitude,
        maximumDistanceMeters,
        apiKey,
      });
    }

    if (!place) return json({ place: null });
    const placeId = text(place.id);
    const placeName = text(place.displayName?.text);
    const placeLatitude = finiteNumber(place.location?.latitude);
    const placeLongitude = finiteNumber(place.location?.longitude);
    if (!placeId || !placeName || placeLatitude == null || placeLongitude == null) {
      return json({ place: null });
    }

    const photo = place.photos?.find((item) => isValidPhotoResource(text(item.name)));
    const photoReference = text(photo?.name);
    const imageUrl = photoReference
      ? await buildSignedPhotoUrl(
        requiredEnv("SUPABASE_URL"),
        photoReference,
        requiredEnv("PLACES_PHOTO_SIGNING_SECRET"),
      )
      : null;

    return json({
      place: {
        place_id: placeId,
        name: placeName,
        address: text(place.formattedAddress) ?? text(body.address) ?? "",
        latitude: placeLatitude,
        longitude: placeLongitude,
        rating: finiteNumber(place.rating),
        types: strings(place.types),
        category: text(body.category) ?? strings(place.types)[0] ?? "AR attraction",
        photo_reference: photoReference,
        image_url: imageUrl,
        google_maps_uri: text(place.googleMapsUri) ?? text(photo?.googleMapsUri),
      },
    });
  } catch (error) {
    console.error("Unable to resolve AR site place:", error);
    return json({ error: "Unable to load this AR location's place details." }, 500);
  }
});

async function getPlace(placeId: string, apiKey: string): Promise<GooglePlace | null> {
  const response = await fetch(
    `https://places.googleapis.com/v1/places/${encodeURIComponent(placeId)}`,
    {
      headers: placesHeaders(apiKey, false),
      signal: AbortSignal.timeout(PLACES_TIMEOUT_MS),
    },
  );
  if (response.status === 404) return null;
  if (!response.ok) {
    console.error("Google Place Details failed", response.status);
    return null;
  }
  return await response.json() as GooglePlace;
}

async function searchForPlace({
  searchNames,
  address,
  latitude,
  longitude,
  maximumDistanceMeters,
  apiKey,
}: {
  searchNames: string[];
  address: string | null;
  latitude: number;
  longitude: number;
  maximumDistanceMeters: number;
  apiKey: string;
}): Promise<GooglePlace | null> {
  let best: { place: GooglePlace; score: number } | null = null;
  for (const searchName of searchNames) {
    const response = await fetch(
      "https://places.googleapis.com/v1/places:searchText",
      {
        method: "POST",
        headers: placesHeaders(apiKey, true),
        body: JSON.stringify({
          textQuery: [searchName, address].filter(Boolean).join(", "),
          maxResultCount: 5,
          locationBias: {
            circle: {
              center: { latitude, longitude },
              radius: Math.max(1000, maximumDistanceMeters),
            },
          },
        }),
        signal: AbortSignal.timeout(PLACES_TIMEOUT_MS),
      },
    );
    if (!response.ok) {
      console.error("Google Places Text Search failed", response.status);
      continue;
    }
    const data = await response.json() as { places?: GooglePlace[] };
    for (const candidate of data.places ?? []) {
      const distance = placeDistanceMeters(candidate, latitude, longitude);
      if (!Number.isFinite(distance) || distance > maximumDistanceMeters) continue;
      const similarity = nameSimilarity(searchName, text(candidate.displayName?.text) ?? "");
      if (similarity <= 0) continue;
      const score = similarity * 10_000 - distance;
      if (best == null || score > best.score) best = { place: candidate, score };
    }
    // An exact/near-exact named result is authoritative; avoid extra billable
    // searches once it is found.
    if (best != null && best.score >= 8_000) break;
  }
  return best?.place ?? null;
}

function placesHeaders(apiKey: string, hasBody: boolean): HeadersInit {
  return {
    ...(hasBody ? { "Content-Type": "application/json" } : {}),
    "X-Goog-Api-Key": apiKey,
    "X-Goog-FieldMask": [
      hasBody ? "places.id" : "id",
      hasBody ? "places.displayName" : "displayName",
      hasBody ? "places.formattedAddress" : "formattedAddress",
      hasBody ? "places.location" : "location",
      hasBody ? "places.rating" : "rating",
      hasBody ? "places.types" : "types",
      hasBody ? "places.photos" : "photos",
      hasBody ? "places.googleMapsUri" : "googleMapsUri",
    ].join(","),
  };
}

function placeDistanceMeters(
  place: GooglePlace,
  latitude: number,
  longitude: number,
): number {
  const placeLatitude = finiteNumber(place.location?.latitude);
  const placeLongitude = finiteNumber(place.location?.longitude);
  if (placeLatitude == null || placeLongitude == null) return Number.POSITIVE_INFINITY;
  const toRadians = (value: number) => value * Math.PI / 180;
  const latitudeDelta = toRadians(placeLatitude - latitude);
  const longitudeDelta = toRadians(placeLongitude - longitude);
  const a = Math.sin(latitudeDelta / 2) ** 2 +
    Math.cos(toRadians(latitude)) * Math.cos(toRadians(placeLatitude)) *
      Math.sin(longitudeDelta / 2) ** 2;
  return 6_371_000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function nameSimilarity(left: string, right: string): number {
  const leftTokens = new Set(normalize(left).split(" ").filter((token) => token.length > 2));
  const rightTokens = new Set(normalize(right).split(" ").filter((token) => token.length > 2));
  if (leftTokens.size === 0 || rightTokens.size === 0) return 0;
  let matches = 0;
  for (const token of leftTokens) if (rightTokens.has(token)) matches++;
  return matches / Math.max(leftTokens.size, rightTokens.size);
}

function normalize(value: string): string {
  return value.toLowerCase().replaceAll(/[^a-z0-9]+/g, " ").trim();
}

async function buildSignedPhotoUrl(
  supabaseUrl: string,
  photoReference: string,
  signingSecret: string,
): Promise<string> {
  const expires = Math.floor(Date.now() / 1000) + PHOTO_URL_LIFETIME_SECONDS;
  const signature = await hmacSha256(
    `${photoReference}|${expires}`,
    signingSecret,
  );
  const url = new URL(`${supabaseUrl}/functions/v1/place-photo`);
  url.searchParams.set("resource", photoReference);
  url.searchParams.set("expires", String(expires));
  url.searchParams.set("signature", signature);
  return url.toString();
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

function isValidPhotoResource(value: string | null): value is string {
  return value != null && /^places\/[A-Za-z0-9_-]+\/photos\/[A-Za-z0-9_-]+$/.test(value);
}

function finiteNumber(value: unknown): number | null {
  if (value == null || value === "") return null;
  const number = Number(value);
  return Number.isFinite(number) ? number : null;
}

function text(value: unknown): string | null {
  const result = typeof value === "string" ? value.trim() : "";
  return result || null;
}

function strings(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.map(text).filter((item): item is string => item != null);
}

function uniqueStrings(values: string[]): string[] {
  return [...new Set(values.map((value) => value.trim()).filter(Boolean))];
}

function clamp(value: number, minimum: number, maximum: number): number {
  return Math.min(maximum, Math.max(minimum, value));
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Required environment variable ${name} is missing.`);
  return value;
}

function json(body: Record<string, unknown>, status = 200): Response {
  return Response.json(body, { status });
}
