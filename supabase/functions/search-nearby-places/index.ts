const DEFAULT_RADIUS_KM = 10;
const MAX_RESULTS = 10;
const ALLOWED_TYPES = new Set([
  "restaurant",
  "cafe",
  "bar",
  "museum",
  "park",
  "shopping_mall",
  "tourist_attraction",
]);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (req.method !== "POST") {
      return json({ error: "Method not allowed." }, 405);
    }

    const body = await req.json();
    const query = String(body.query ?? "").trim();
    if (query) {
      if (query.length > 200) {
        return json({ error: "Search query is too long." }, 400);
      }
      return await searchText(query);
    }

    const latitude = Number(body.latitude);
    const longitude = Number(body.longitude);
    const radiusKm = clamp(
      body.radius_km == null ? DEFAULT_RADIUS_KM : Number(body.radius_km),
      1,
      50,
    );
    const requestedTypes = Array.isArray(body.included_types)
      ? body.included_types.map(String)
      : [];
    const includedTypes = [...new Set(requestedTypes)]
      .filter((type) => ALLOWED_TYPES.has(type));

    if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90) {
      return json({ error: "Invalid latitude." }, 400);
    }
    if (!Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
      return json({ error: "Invalid longitude." }, 400);
    }
    if (!Number.isFinite(radiusKm)) {
      return json({ error: "Invalid radius." }, 400);
    }
    if (includedTypes.length === 0) {
      return json({ error: "A supported place type is required." }, 400);
    }

    const apiKey = requiredEnv("GOOGLE_PLACES_API_KEY");
    const googleResponse = await fetch(
      "https://places.googleapis.com/v1/places:searchNearby",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Goog-Api-Key": apiKey,
          "X-Goog-FieldMask": [
            "places.id",
            "places.displayName",
            "places.formattedAddress",
            "places.location",
            "places.rating",
            "places.userRatingCount",
            "places.types",
            "places.primaryType",
            "places.businessStatus",
          ].join(","),
        },
        body: JSON.stringify({
          includedTypes,
          maxResultCount: MAX_RESULTS,
          rankPreference: "DISTANCE",
          locationRestriction: {
            circle: {
              center: { latitude, longitude },
              radius: radiusKm * 1000,
            },
          },
        }),
      },
    );

    const googleData = await googleResponse.json();
    if (!googleResponse.ok) {
      console.error("Google Places Nearby Search failed", googleData);
      return json(
        {
          error: googleData?.error?.message ??
            "Google Places Nearby Search failed.",
        },
        googleResponse.status,
      );
    }

    const places = (Array.isArray(googleData?.places) ? googleData.places : [])
      .map(toFlutterPlace)
      .filter((place: Record<string, unknown> | null) => place != null);

    return json({ places, radius_km: radiusKm, source: "google_places" });
  } catch (error) {
    console.error(error);
    return json(
      { error: error instanceof Error ? error.message : "Unknown error." },
      500,
    );
  }
});

async function searchText(query: string) {
  const apiKey = requiredEnv("GOOGLE_PLACES_API_KEY");
  const googleResponse = await fetch(
    "https://places.googleapis.com/v1/places:searchText",
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": apiKey,
        "X-Goog-FieldMask": placeFieldMask(),
      },
      body: JSON.stringify({
        textQuery: query,
        maxResultCount: MAX_RESULTS,
        languageCode: "en",
        regionCode: "MY",
      }),
    },
  );

  const googleData = await googleResponse.json();
  if (!googleResponse.ok) {
    console.error("Google Places Text Search failed", googleData);
    return json(
      {
        error: googleData?.error?.message ?? "Google Places Text Search failed.",
      },
      googleResponse.status,
    );
  }

  const places = (Array.isArray(googleData?.places) ? googleData.places : [])
    .map(toFlutterPlace)
    .filter((place: Record<string, unknown> | null) => place != null);

  return json({ places, source: "google_places_text" });
}

function toFlutterPlace(place: Record<string, any>) {
  const name = String(place.displayName?.text ?? "").trim();
  const placeId = String(place.id ?? "").trim();
  const latitude = Number(place.location?.latitude);
  const longitude = Number(place.location?.longitude);
  if (
    !name || !placeId || !Number.isFinite(latitude) ||
    !Number.isFinite(longitude)
  ) return null;

  return {
    id: placeId,
    place_id: placeId,
    name,
    address: String(place.formattedAddress ?? ""),
    latitude,
    longitude,
    rating: Number.isFinite(Number(place.rating)) ? Number(place.rating) : null,
    user_ratings_total: Number.isFinite(Number(place.userRatingCount))
      ? Number(place.userRatingCount)
      : null,
    types: Array.isArray(place.types) ? place.types.map(String) : [],
    category: place.primaryType == null ? null : String(place.primaryType),
    business_status: place.businessStatus == null
      ? null
      : String(place.businessStatus),
  };
}

function placeFieldMask() {
  return [
    "places.id",
    "places.displayName",
    "places.formattedAddress",
    "places.location",
    "places.rating",
    "places.userRatingCount",
    "places.types",
    "places.primaryType",
    "places.businessStatus",
  ].join(",");
}

function json(body: unknown, status = 200) {
  return Response.json(body, { status, headers: corsHeaders });
}

function clamp(value: number, minimum: number, maximum: number) {
  return Math.min(maximum, Math.max(minimum, value));
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`Missing required secret: ${name}`);
  return value;
}
